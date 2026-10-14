#include "calendarsources.hpp"

#include <qdatetime.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qhash.h>
#include <qloggingcategory.h>
#include <qregularexpression.h>
#include <qtextstream.h>

Q_LOGGING_CATEGORY(lcCalendarSources, "burl.calendarsources", QtInfoMsg)

namespace burl {

CalendarSources::CalendarSources(QObject* parent) : QObject(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    QObject::connect(&m_debounce, &QTimer::timeout, this, &CalendarSources::reload);

    QObject::connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        // org rewrites the file (rename-on-save) — re-add the path.
        rewatch();
        scheduleReload();
    });

    m_agendaFile = qEnvironmentVariable("BURL_CALENDAR_FILE");
    rewatch();
    QTimer::singleShot(0, this, &CalendarSources::reload);
}

void CalendarSources::setAgendaFile(const QString& path) {
    if (m_agendaFile == path) return;
    m_agendaFile = path;
    emit agendaFileChanged();
    rewatch();
    reload();
}

void CalendarSources::setHorizonDays(int n) {
    if (m_horizonDays == n) return;
    m_horizonDays = n;
    emit horizonDaysChanged();
    reload();
}

void CalendarSources::reload() {
    QVariantList events;
    QVariantList links;

    // `* Heading` lines, and active org timestamps `<YYYY-MM-DD Day HH:MM...>`
    // (the time/range part is optional for all-day events).
    static const QRegularExpression headingRe(QStringLiteral("^\\*+\\s+(.*)$"));
    static const QRegularExpression tsRe(QStringLiteral(
        "<(\\d{4})-(\\d{2})-(\\d{2})[^>]*?(?:\\s(\\d{2}:\\d{2})(?:-(\\d{2}:\\d{2}))?)?>"));
    static const QRegularExpression locRe(QStringLiteral("^\\s*:LOCATION:\\s*(.+)$"),
                                          QRegularExpression::CaseInsensitiveOption);
    static const QRegularExpression tagsRe(QStringLiteral("^#\\+FILETAGS:.*@work"),
                                           QRegularExpression::CaseInsensitiveOption);
    // Conferencing links only: arbitrary URLs in event bodies are mostly noise.
    static const QRegularExpression linkRe(QStringLiteral(
        "https://(?:meet\\.google\\.com|[\\w.-]*zoom\\.us|teams\\.microsoft\\.com|[\\w.-]*webex\\.com)/[^\\s>\\])]+"));

    const QDate today = QDate::currentDate();
    const QDate horizon = today.addDays(m_horizonDays);
    QHash<QString, QString> hubByDay;
    int counter = 0;

    for (const QString& path : files()) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) continue;

        const QString calendar = QFileInfo(path).fileName().contains(QLatin1String("work"), Qt::CaseInsensitive)
            ? QStringLiteral("work") : QStringLiteral("personal");
        bool fileWork = calendar == QLatin1String("work");

        // Properties precede the timestamp in org-gcal output, so hold them
        // until it arrives; the link lives in the body after it.
        QString pendingTitle, pendingLoc;
        QVariantMap row;
        bool haveRow = false;
        auto flush = [&]() {
            if (haveRow) events.append(row);
            haveRow = false;
        };

        QTextStream in(&f);
        while (!in.atEnd()) {
            const QString line = in.readLine();
            if (events.isEmpty() && !haveRow && pendingTitle.isEmpty() && tagsRe.match(line).hasMatch())
                fileWork = true;

            const auto hm = headingRe.match(line);
            if (hm.hasMatch()) {
                flush();
                pendingTitle = hm.captured(1).trimmed();
                pendingLoc.clear();
                continue;
            }
            if (haveRow) {
                if (row.value(QStringLiteral("link")).toString().isEmpty()) {
                    const auto lm = linkRe.match(line);
                    if (lm.hasMatch()) row.insert(QStringLiteral("link"), lm.captured(0));
                }
                continue;
            }
            if (pendingTitle.isEmpty()) continue;

            const auto om = locRe.match(line);
            if (om.hasMatch()) {
                pendingLoc = om.captured(1).trimmed();
                continue;
            }

            const auto tm = tsRe.match(line);
            if (!tm.hasMatch()) continue;

            const QDate date(tm.captured(1).toInt(), tm.captured(2).toInt(), tm.captured(3).toInt());
            if (!date.isValid() || date < today || date > horizon) {
                pendingTitle.clear();
                continue;
            }

            const QString startTime = tm.captured(4);  // may be empty (all-day)
            const QString dayKey = date.toString(Qt::ISODate);
            // Stable id: day + counter so duplicate titles don't collide.
            const QString id = QStringLiteral("event:%1:%2").arg(dayKey).arg(counter++);

            row.clear();
            row.insert(QStringLiteral("kind"), QStringLiteral("event"));
            row.insert(QStringLiteral("id"), id);
            row.insert(QStringLiteral("title"), pendingTitle);
            row.insert(QStringLiteral("date"), dayKey);
            row.insert(QStringLiteral("day"), date.toString(QStringLiteral("ddd MMM d")));
            row.insert(QStringLiteral("time"), startTime);
            row.insert(QStringLiteral("endTime"), tm.captured(5));
            row.insert(QStringLiteral("allDay"), startTime.isEmpty());
            row.insert(QStringLiteral("daysAway"), static_cast<int>(today.daysTo(date)));
            row.insert(QStringLiteral("calendar"), fileWork ? QStringLiteral("work") : QStringLiteral("personal"));
            row.insert(QStringLiteral("location"), pendingLoc);
            row.insert(QStringLiteral("link"), QString());
            haveRow = true;

            auto it = hubByDay.constFind(dayKey);
            if (it == hubByDay.constEnd()) {
                hubByDay.insert(dayKey, id);
            } else {
                QVariantMap link;
                link.insert(QStringLiteral("source"), id);
                link.insert(QStringLiteral("dest"), it.value());
                links.append(link);
            }
            pendingTitle.clear();
        }
        flush();
    }

    if (events != m_events) {
        m_events = std::move(events);
        emit eventsChanged();
    }
    if (links != m_dayLinks) {
        m_dayLinks = std::move(links);
    }
}

QStringList CalendarSources::files() const {
    return m_agendaFile.split(QLatin1Char(':'), Qt::SkipEmptyParts);
}

void CalendarSources::rewatch() {
    if (!m_watcher.files().isEmpty()) {
        m_watcher.removePaths(m_watcher.files());
    }
    for (const QString& p : files()) {
        if (QFileInfo::exists(p)) m_watcher.addPath(p);
    }
}

void CalendarSources::scheduleReload() {
    if (!m_debounce.isActive()) m_debounce.start();
}

} // namespace burl
