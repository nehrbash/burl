#include "calendarsources.hpp"

#include <qdatetime.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
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

    m_agendaFile = QDir::homePath() + QStringLiteral("/doc/gcal.org");
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

    QFile f(m_agendaFile);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (events != m_events) {
            m_events = events;
            emit eventsChanged();
        }
        return;
    }

    // `* Heading` lines, and active org timestamps `<YYYY-MM-DD Day HH:MM...>`
    // (the time/range part is optional for all-day events).
    static const QRegularExpression headingRe(QStringLiteral("^\\*+\\s+(.*)$"));
    static const QRegularExpression tsRe(QStringLiteral(
        "<(\\d{4})-(\\d{2})-(\\d{2})[^>]*?(?:\\s(\\d{2}:\\d{2})(?:-(\\d{2}:\\d{2}))?)?>"));

    const QDate today = QDate::currentDate();
    const QDate horizon = today.addDays(m_horizonDays);

    // First event seen per day → hub for that day's dayLinks.
    QHash<QString, QString> hubByDay;

    QTextStream in(&f);
    QString pendingTitle;
    int counter = 0;
    while (!in.atEnd()) {
        const QString line = in.readLine();
        const auto hm = headingRe.match(line);
        if (hm.hasMatch()) {
            pendingTitle = hm.captured(1).trimmed();
            continue;
        }
        if (pendingTitle.isEmpty()) continue;

        const auto tm = tsRe.match(line);
        if (!tm.hasMatch()) continue;

        const QDate date(tm.captured(1).toInt(), tm.captured(2).toInt(), tm.captured(3).toInt());
        if (!date.isValid() || date < today || date > horizon) {
            pendingTitle.clear();
            continue;
        }

        const QString startTime = tm.captured(4);  // may be empty (all-day)
        const QString endTime = tm.captured(5);
        const QString dayKey = date.toString(Qt::ISODate);
        // Stable id: day + counter so duplicate titles don't collide.
        const QString id = QStringLiteral("event:%1:%2").arg(dayKey).arg(counter++);

        QVariantMap row;
        row.insert(QStringLiteral("kind"), QStringLiteral("event"));
        row.insert(QStringLiteral("id"), id);
        row.insert(QStringLiteral("title"), pendingTitle);
        row.insert(QStringLiteral("date"), dayKey);
        row.insert(QStringLiteral("day"),
                   date.toString(QStringLiteral("ddd MMM d")));
        row.insert(QStringLiteral("time"), startTime);
        row.insert(QStringLiteral("endTime"), endTime);
        row.insert(QStringLiteral("allDay"), startTime.isEmpty());
        row.insert(QStringLiteral("daysAway"), static_cast<int>(today.daysTo(date)));
        events.append(row);

        auto it = hubByDay.constFind(dayKey);
        if (it == hubByDay.constEnd()) {
            hubByDay.insert(dayKey, id);
        } else if (it.value() != id) {
            QVariantMap link;
            link.insert(QStringLiteral("source"), id);
            link.insert(QStringLiteral("dest"), it.value());
            links.append(link);
        }

        pendingTitle.clear();
    }
    f.close();

    if (events != m_events) {
        m_events = std::move(events);
        emit eventsChanged();
    }
    if (links != m_dayLinks) {
        m_dayLinks = std::move(links);
        // dayLinks shares eventsChanged (declared in hpp).
    }
}

void CalendarSources::rewatch() {
    if (!m_watcher.files().isEmpty()) {
        m_watcher.removePaths(m_watcher.files());
    }
    if (!m_agendaFile.isEmpty() && QFileInfo::exists(m_agendaFile)) {
        m_watcher.addPath(m_agendaFile);
    }
}

void CalendarSources::scheduleReload() {
    if (!m_debounce.isActive()) m_debounce.start();
}

} // namespace burl
