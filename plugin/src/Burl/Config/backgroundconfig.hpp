#pragma once

#include "configobject.hpp"

#include <qstring.h>

namespace burl::config {

class DesktopClockBackground : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, false)
    CONFIG_PROPERTY(qreal, opacity, 0.7)
    CONFIG_PROPERTY(bool, blur, true)

public:
    explicit DesktopClockBackground(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class DesktopClockShadow : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(qreal, opacity, 0.7)
    CONFIG_PROPERTY(qreal, blur, 0.4)

public:
    explicit DesktopClockShadow(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class DesktopClock : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, false)
    CONFIG_PROPERTY(qreal, scale, 1.0)
    CONFIG_PROPERTY(QString, position, QStringLiteral("bottom-right"))
    CONFIG_PROPERTY(bool, invertColors, false)
    CONFIG_SUBOBJECT(DesktopClockBackground, background)
    CONFIG_SUBOBJECT(DesktopClockShadow, shadow)

public:
    explicit DesktopClock(QObject* parent = nullptr)
        : ConfigObject(parent)
        , m_background(new DesktopClockBackground(this))
        , m_shadow(new DesktopClockShadow(this)) {}
};

class BackgroundVisualiser : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, false)
    CONFIG_PROPERTY(bool, autoHide, true)
    CONFIG_PROPERTY(bool, blur, false)
    CONFIG_PROPERTY(qreal, rounding, 1)
    CONFIG_PROPERTY(qreal, spacing, 1)

public:
    explicit BackgroundVisualiser(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

// Animated (video) wallpapers. burl does not decode video itself: it owns an
// mpvpaper child process (see services/Wallpapers.qml) that paints on the wlr
// background layer while burl's own background window goes transparent above
// it.
//
// `enabled' is the per-monitor switch: turn it off for one screen to keep
// painting the still there. That screen does NOT stop mpvpaper -- one process
// serves the whole `output' target and has no notion of a per-screen opt-out
// -- so burl cannot paint its still on the *background* layer there either:
// mpvpaper is already on that layer, and two clients on one wlr layer is
// undefined stacking. See Background.qml -- the opted-out screen sits on
// *bottom*, fully opaque, covering the video with the still from one layer up.
//
// The rest are global-only, and they are deliberately config rather than a
// separate state file: burl restarts (`herd restart quickshell') far more
// often than the wallpaper changes, and `path' being config is what brings the
// video back by itself afterwards.
//   path            absolute video path; "" = still-image mode
//   output          connector name, or a space-separated list; "" = all screens
//   speed           mpv playback speed (0.5 = half; a wallpaper is peripheral
//                   vision, and this clip reads as busy at 1.0)
//   previousStill   the still that was showing before video mode started;
//                   what clearVideoWallpaper() restores
class BackgroundVideo : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_GLOBAL_PROPERTY(QString, path, QStringLiteral(""))
    CONFIG_GLOBAL_PROPERTY(QString, output, QStringLiteral(""))
    CONFIG_GLOBAL_PROPERTY(qreal, speed, 0.5)
    CONFIG_GLOBAL_PROPERTY(QString, previousStill, QStringLiteral(""))

public:
    explicit BackgroundVideo(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class BackgroundConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(bool, wallpaperEnabled, true)
    CONFIG_SUBOBJECT(DesktopClock, desktopClock)
    CONFIG_SUBOBJECT(BackgroundVisualiser, visualiser)
    CONFIG_SUBOBJECT(BackgroundVideo, video)

public:
    explicit BackgroundConfig(QObject* parent = nullptr)
        : ConfigObject(parent)
        , m_desktopClock(new DesktopClock(this))
        , m_visualiser(new BackgroundVisualiser(this))
        , m_video(new BackgroundVideo(this)) {}
};

} // namespace burl::config
