#pragma once

#include <qdbusconnection.h>
#include <qdbusunixfiledescriptor.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

#include <optional>

namespace burl::services {

class SessionManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool lidPresent READ lidPresent NOTIFY lidPresentChanged)
    Q_PROPERTY(bool lidClosed READ lidClosed NOTIFY lidClosedChanged)
    // While true, a logind "handle-lid-switch" block inhibitor is held and logind leaves the lid to us.
    Q_PROPERTY(bool lidInhibited READ lidInhibited WRITE setLidInhibited NOTIFY lidInhibitedChanged)

public:
    explicit SessionManager(QObject* parent = nullptr);

    Q_INVOKABLE void logout();
    Q_INVOKABLE void suspend();
    Q_INVOKABLE void suspendThenHibernate();
    Q_INVOKABLE void hibernate();
    Q_INVOKABLE void poweroff();
    Q_INVOKABLE void reboot();
    // Emits lockRequested() rather than calling logind: elogind never
    // delivers the session Lock signal back to us, so `loginctl
    // lock-session` locks nothing. The QML side owns the WlSessionLock.
    Q_INVOKABLE void lock();

    Q_INVOKABLE bool exec(const QStringList& command);

    [[nodiscard]] bool lidPresent() const { return m_lidPresent; }
    [[nodiscard]] bool lidClosed() const { return m_lidClosed; }
    [[nodiscard]] bool lidInhibited() const { return m_lidInhibitor.isValid(); }
    void setLidInhibited(bool inhibited);

signals:
    void aboutToSleep();
    void resumed();
    void lockRequested();
    void unlockRequested();
    void lidPresentChanged();
    void lidClosedChanged();
    void lidInhibitedChanged();

private slots:
    void handlePrepareForSleep(bool sleep);
    void handleLockRequested();
    void handleUnlockRequested();
    void handlePropertiesChanged(const QString& iface, const QVariantMap& changed, const QStringList&);

private:
    void initLid(QDBusConnection& bus);
    void setLidClosed(bool closed);
    void setLidPresent(bool present);

    [[nodiscard]] std::optional<QDBusConnection> getSystemBus() const;
    [[nodiscard]] bool queryHibernateAvailable() const;
    void call(const QString& path, const QString& iface, const QString& method, const QVariantList& args = {});
    void callManager(const QString& method);
    void callSession(const QString& method);

    QString m_sessionPath;
    QDBusUnixFileDescriptor m_lidInhibitor;
    bool m_lidPresent = false;
    bool m_lidClosed = false;
};

} // namespace burl::services
