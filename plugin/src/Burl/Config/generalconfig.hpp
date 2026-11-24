#pragma once

#include "configobject.hpp"

#include <qstring.h>
#include <qstringlist.h>
#include <qvariant.h>

namespace burl::config {

using Qt::StringLiterals::operator""_s;

class GeneralApps : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(QStringList, terminal, { u"alacritty"_s })
    CONFIG_GLOBAL_PROPERTY(QStringList, audio, { u"pavucontrol"_s })
    CONFIG_GLOBAL_PROPERTY(QStringList, playback)
    CONFIG_GLOBAL_PROPERTY(QStringList, explorer)
    CONFIG_GLOBAL_PROPERTY(QString, terminalDesktop)
    CONFIG_GLOBAL_PROPERTY(QString, playbackDesktop)
    CONFIG_GLOBAL_PROPERTY(QString, explorerDesktop)

public:
    explicit GeneralApps(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class GeneralIdle : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(bool, lockBeforeSleep, true)
    CONFIG_GLOBAL_PROPERTY(bool, inhibitWhenAudio, true)
    CONFIG_GLOBAL_PROPERTY(bool, inhibitWhenCharging, false)
    CONFIG_GLOBAL_PROPERTY(int, lockAfter, 300)
    CONFIG_GLOBAL_PROPERTY(int, screenOffAfter, 600)
    CONFIG_GLOBAL_PROPERTY(int, sleepAfter, 0)
    // suspend | suspendThenHibernate | hibernate
    CONFIG_GLOBAL_PROPERTY(QString, sleepAction, u"suspend"_s)
    // Advanced: a non-empty list replaces the three stages above.
    CONFIG_GLOBAL_PROPERTY(QVariantList, timeouts)

public:
    explicit GeneralIdle(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class GeneralLid : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    // false: Burl takes no logind inhibitor and logind's own lid policy applies.
    CONFIG_GLOBAL_PROPERTY(bool, handle, true)
    // sleep | lock | screenOff | nothing. `sleep` follows general.idle.sleepAction.
    CONFIG_GLOBAL_PROPERTY(QString, action, u"sleep"_s)
    CONFIG_GLOBAL_PROPERTY(QString, actionOnPower, u"sleep"_s)
    // Used whenever an external monitor is connected, on battery or not.
    CONFIG_GLOBAL_PROPERTY(QString, actionDocked, u"nothing"_s)

public:
    explicit GeneralLid(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class GeneralBattery : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(QVariantList, warnLevels,
        {
            vmap({
                { u"level"_s, 20 },
                { u"title"_s, u"Low battery"_s },
                { u"message"_s, u"You might want to plug in a charger"_s },
                { u"icon"_s, u"battery_android_frame_2"_s },
            }),
            vmap({
                { u"level"_s, 10 },
                { u"title"_s, u"Did you see the previous message?"_s },
                { u"message"_s, u"You should probably plug in a charger <b>now</b>"_s },
                { u"icon"_s, u"battery_android_frame_1"_s },
            }),
            vmap({
                { u"level"_s, 5 },
                { u"title"_s, u"Critical battery level"_s },
                { u"message"_s, u"PLUG THE CHARGER RIGHT NOW!!"_s },
                { u"icon"_s, u"battery_android_alert"_s },
                { u"critical"_s, true },
            }),
        })
    CONFIG_GLOBAL_PROPERTY(int, criticalLevel, 3)

public:
    explicit GeneralBattery(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class GeneralConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_GLOBAL_PROPERTY(QString, logo)
    CONFIG_PROPERTY(bool, showOverFullscreen, false)
    CONFIG_PROPERTY(qreal, mediaGifSpeedAdjustment, 300)
    CONFIG_SUBOBJECT(GeneralApps, apps)
    CONFIG_SUBOBJECT(GeneralIdle, idle)
    CONFIG_SUBOBJECT(GeneralLid, lid)
    CONFIG_SUBOBJECT(GeneralBattery, battery)

public:
    explicit GeneralConfig(QObject* parent = nullptr)
        : ConfigObject(parent)
        , m_apps(new GeneralApps(this))
        , m_idle(new GeneralIdle(this))
        , m_lid(new GeneralLid(this))
        , m_battery(new GeneralBattery(this)) {}
};

} // namespace burl::config
