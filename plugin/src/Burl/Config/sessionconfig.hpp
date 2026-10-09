#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qstringlist.h>

namespace burl::config {

using Qt::StringLiterals::operator""_s;

class SessionIcons : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(QString, logout, u"logout"_s)
    CONFIG_PROPERTY(QString, shutdown, u"power_settings_new"_s)
    CONFIG_PROPERTY(QString, hibernate, u"downloading"_s)
    CONFIG_PROPERTY(QString, reboot, u"cached"_s)
    CONFIG_PROPERTY(QString, lock, u"lock"_s)
    CONFIG_PROPERTY(QString, windows, u"desktop_windows"_s)

public:
    explicit SessionIcons(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class SessionCommands : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(QStringList, logout, { u"logout"_s })
    CONFIG_PROPERTY(QStringList, shutdown, { u"poweroff"_s })
    CONFIG_PROPERTY(QStringList, hibernate, { u"hibernate"_s })
    CONFIG_PROPERTY(QStringList, reboot, { u"reboot"_s })
    CONFIG_PROPERTY(QStringList, lock, { u"loginctl"_s, u"lock-session"_s })
    CONFIG_PROPERTY(QStringList, windows, {})

public:
    explicit SessionCommands(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class SessionConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_SUBOBJECT(SessionIcons, icons)
    CONFIG_SUBOBJECT(SessionCommands, commands)

public:
    explicit SessionConfig(QObject* parent = nullptr)
        : ConfigObject(parent)
        , m_icons(new SessionIcons(this))
        , m_commands(new SessionCommands(this)) {}
};

} // namespace burl::config
