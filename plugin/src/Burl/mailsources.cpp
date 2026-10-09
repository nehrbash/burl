#include "mailsources.hpp"

#include <qdir.h>
#include <qfileinfo.h>
#include <qjsonarray.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qloggingcategory.h>
#include <qstandardpaths.h>

Q_LOGGING_CATEGORY(lcMailSources, "burl.mailsources", QtInfoMsg)

namespace burl {

namespace {

// mu's json keys are keyword-style (":subject", ":from"). Pull a string,
// falling back to empty.
QString jstr(const QJsonObject& o, const char* key) {
    return o.value(QLatin1String(key)).toString();
}

// :from / :to are arrays of { ":email", ":name" }. Return the first
// contact's display name (or email if unnamed).
QVariantMap firstContact(const QJsonValue& v) {
    QVariantMap out;
    if (v.isArray()) {
        const auto arr = v.toArray();
        if (!arr.isEmpty()) {
            const auto c = arr.first().toObject();
            const QString email = c.value(QStringLiteral(":email")).toString();
            QString name = c.value(QStringLiteral(":name")).toString();
            // mu sometimes stores the name as "<email>" when absent.
            if (name.isEmpty() || name == QStringLiteral("<") + email + QStringLiteral(">")) {
                name = email;
            }
            out.insert(QStringLiteral("email"), email);
            out.insert(QStringLiteral("name"), name);
        }
    }
    return out;
}

} // namespace

MailSources::MailSources(QObject* parent) : QObject(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(400);
    QObject::connect(&m_debounce, &QTimer::timeout, this, &MailSources::reload);

    QObject::connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        scheduleReload();
    });

    m_proc.setProcessChannelMode(QProcess::SeparateChannels);
    QObject::connect(&m_proc, &QProcess::finished, this, &MailSources::onFinished);

    // Locate `mu` on PATH; fall back to the Guix home profile.
    m_muPath = QStandardPaths::findExecutable(QStringLiteral("mu"));
    if (m_muPath.isEmpty()) {
        const QString guix = QDir::homePath() + QStringLiteral("/.guix-home/profile/bin/mu");
        if (QFileInfo::exists(guix)) m_muPath = guix;
    }
    m_xapianDir = QDir::homePath() + QStringLiteral("/.cache/mu/xapian");

    rewatch();
    QTimer::singleShot(0, this, &MailSources::reload);
}

void MailSources::setQuery(const QString& q) {
    if (m_query == q) return;
    m_query = q;
    emit queryChanged();
    scheduleReload();
}

void MailSources::setMuPath(const QString& p) {
    if (m_muPath == p) return;
    m_muPath = p;
    emit muPathChanged();
    scheduleReload();
}

void MailSources::setXapianDir(const QString& d) {
    if (m_xapianDir == d) return;
    m_xapianDir = d;
    emit xapianDirChanged();
    rewatch();
}

void MailSources::setMessageLimit(int n) {
    if (m_messageLimit == n) return;
    m_messageLimit = n;
    emit messageLimitChanged();
    scheduleReload();
}

void MailSources::reload() {
    if (m_muPath.isEmpty()) {
        qCWarning(lcMailSources) << "mu executable not found; no mail nodes";
        return;
    }
    if (m_proc.state() != QProcess::NotRunning) {
        // A scan is already in flight; coalesce by re-arming the debounce.
        scheduleReload();
        return;
    }
    m_proc.start(m_muPath,
                 { QStringLiteral("find"), m_query,
                   QStringLiteral("--format=json"),
                   QStringLiteral("--sortfield=date"), QStringLiteral("--reverse"),
                   QStringLiteral("--maxnum"), QString::number(m_messageLimit) });
}

void MailSources::rewatch() {
    if (!m_watcher.directories().isEmpty()) {
        m_watcher.removePaths(m_watcher.directories());
    }
    if (!m_xapianDir.isEmpty() && QFileInfo::exists(m_xapianDir)) {
        m_watcher.addPath(m_xapianDir);
    }
}

void MailSources::scheduleReload() {
    if (!m_debounce.isActive()) m_debounce.start();
}

void MailSources::onFinished(int exitCode, QProcess::ExitStatus status) {
    QVariantList messages;
    QVariantList links;

    if (status != QProcess::NormalExit || exitCode != 0) {
        // `mu find` exits non-zero when there are zero matches — that is a
        // legitimate empty result, not an error. Only warn if it also
        // wrote to stderr (a real failure).
        const QByteArray err = m_proc.readAllStandardError();
        if (!err.isEmpty()) {
            qCWarning(lcMailSources) << "mu find:" << err.trimmed();
        }
    }

    const QByteArray out = m_proc.readAllStandardOutput();
    if (!out.isEmpty()) {
        QJsonParseError perr;
        const auto doc = QJsonDocument::fromJson(out, &perr);
        if (perr.error != QJsonParseError::NoError) {
            qCWarning(lcMailSources) << "json parse:" << perr.errorString();
        } else if (doc.isArray()) {
            // Track the first message seen per sender email — that node
            // becomes the hub the rest of that sender's mail links to.
            QHash<QString, QString> hubBySender;
            for (const auto& v : doc.array()) {
                const auto o = v.toObject();
                const QString id = jstr(o, ":message-id");
                if (id.isEmpty()) continue;
                const QVariantMap from = firstContact(o.value(QStringLiteral(":from")));
                const QString senderEmail = from.value(QStringLiteral("email")).toString();
                const QString senderName = from.value(QStringLiteral("name")).toString();

                const auto flags = o.value(QStringLiteral(":flags")).toArray();
                const bool unread = flags.contains(QJsonValue(QStringLiteral("unread")));
                const bool flagged = flags.contains(QJsonValue(QStringLiteral("flagged")));

                QVariantMap row;
                row.insert(QStringLiteral("kind"), QStringLiteral("mail"));
                row.insert(QStringLiteral("id"), id);
                row.insert(QStringLiteral("subject"), jstr(o, ":subject"));
                row.insert(QStringLiteral("from"), senderName);
                row.insert(QStringLiteral("fromEmail"), senderEmail);
                row.insert(QStringLiteral("path"), jstr(o, ":path"));
                row.insert(QStringLiteral("date"), o.value(QStringLiteral(":changed-unix")).toVariant());
                row.insert(QStringLiteral("unread"), unread);
                row.insert(QStringLiteral("flagged"), flagged);
                messages.append(row);

                if (!senderEmail.isEmpty()) {
                    auto it = hubBySender.constFind(senderEmail);
                    if (it == hubBySender.constEnd()) {
                        hubBySender.insert(senderEmail, id);
                    } else if (it.value() != id) {
                        QVariantMap link;
                        link.insert(QStringLiteral("source"), id);
                        link.insert(QStringLiteral("dest"), it.value());
                        links.append(link);
                    }
                }
            }
        }
    }

    if (messages != m_messages) {
        m_messages = std::move(messages);
        emit messagesChanged();
    }
    if (links != m_senderLinks) {
        m_senderLinks = std::move(links);
        // senderLinks shares the messagesChanged notify (declared in hpp).
    }
}

} // namespace burl
