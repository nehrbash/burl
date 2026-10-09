#pragma once

#include <qfilesystemwatcher.h>
#include <qobject.h>
#include <qprocess.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>
#include <qvariant.h>

namespace burl {

// Surfaces unread / flagged mail from the local mu (maildir) index by
// shelling out to `mu find ... --format=json` and parsing the result.
// mu is not a plain SQLite DB (it is a Xapian index), so unlike the other
// sources this one runs a child process rather than opening a file.
//
// Watches the mu xapian directory so a fresh `mbsync` + `mu index` (or
// mu4e marking mail read) triggers a debounced rescan.
//
// senderLinks gives hub-and-spoke edges grouping messages by sender:
// every message links to the earliest message from the same From: email.
// (mu's JSON output carries no thread id, so we cluster by sender rather
// than by conversation — which also reads well: all unread from one
// correspondent cluster together.)
class MailSources : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    Q_PROPERTY(QString muPath READ muPath WRITE setMuPath NOTIFY muPathChanged)
    Q_PROPERTY(QString xapianDir READ xapianDir WRITE setXapianDir NOTIFY xapianDirChanged)
    Q_PROPERTY(int messageLimit READ messageLimit WRITE setMessageLimit NOTIFY messageLimitChanged)

    Q_PROPERTY(QVariantList messages READ messages NOTIFY messagesChanged)
    // Edges: { source: messageId, dest: senderHubMessageId }.
    Q_PROPERTY(QVariantList senderLinks READ senderLinks NOTIFY messagesChanged)

public:
    explicit MailSources(QObject* parent = nullptr);

    [[nodiscard]] QString query() const { return m_query; }
    void setQuery(const QString& q);

    [[nodiscard]] QString muPath() const { return m_muPath; }
    void setMuPath(const QString& p);

    [[nodiscard]] QString xapianDir() const { return m_xapianDir; }
    void setXapianDir(const QString& d);

    [[nodiscard]] int messageLimit() const { return m_messageLimit; }
    void setMessageLimit(int n);

    [[nodiscard]] QVariantList messages() const { return m_messages; }
    [[nodiscard]] QVariantList senderLinks() const { return m_senderLinks; }

    Q_INVOKABLE void reload();

signals:
    void queryChanged();
    void muPathChanged();
    void xapianDirChanged();
    void messageLimitChanged();
    void messagesChanged();

private:
    void rewatch();
    void scheduleReload();
    void onFinished(int exitCode, QProcess::ExitStatus status);

    // mu find query selecting which mail to surface. Default: unread or
    // flagged, since those are the actionable messages worth a graph node.
    QString m_query = QStringLiteral("flag:unread OR flag:flagged");
    QString m_muPath;     // path to the `mu` executable
    QString m_xapianDir;  // ~/.cache/mu/xapian (watched for reindex)
    int m_messageLimit = 200;

    QVariantList m_messages;
    QVariantList m_senderLinks;

    QProcess m_proc;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

} // namespace burl
