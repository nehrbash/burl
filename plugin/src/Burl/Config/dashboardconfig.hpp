#pragma once

#include "configobject.hpp"

#include <qstring.h>

namespace burl::config {

class DashboardPerformance : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, showBattery, true)
    CONFIG_PROPERTY(bool, showGpu, true)
    CONFIG_PROPERTY(bool, showCpu, true)
    CONFIG_PROPERTY(bool, showMemory, true)
    CONFIG_PROPERTY(bool, showStorage, true)
    CONFIG_PROPERTY(bool, showNetwork, true)

public:
    explicit DashboardPerformance(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

class DashboardConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(bool, enabled, true)
    CONFIG_PROPERTY(bool, showOnHover, true)
    CONFIG_PROPERTY(bool, showDashboard, true)
    CONFIG_PROPERTY(bool, showMedia, true)
    CONFIG_PROPERTY(bool, showPerformance, true)
    CONFIG_PROPERTY(bool, showWeather, true)
    CONFIG_GLOBAL_PROPERTY(int, mediaUpdateInterval, 500)
    CONFIG_GLOBAL_PROPERTY(int, resourceUpdateInterval, 1000)
    CONFIG_PROPERTY(int, dragThreshold, 50)
    // Navigation chrome: "living" (full-screen growing tree, bottom-middle trigger) or "tabs"
    // (legacy top TabBar, fallback only). Both consume the same section list, so this flips
    // the whole navigation in one setting; any other value lands on the tab bar.
    // "living" must be the COMPILED default, not just a shell.json override: Interactions.qml
    // guards its close path on this value, and where an attached read fell back to a compiled
    // "tabs" the guard went false and any pointer motion outside the interior slammed the
    // tree shut.
    CONFIG_PROPERTY(QString, navStyle, QStringLiteral("living"))
    // living navStyle only: hovering the bottom-edge sprout grows the tree (mirrors the old
    // showOnHover reflex).
    CONFIG_PROPERTY(bool, livingHoverGrow, true)
    // Arrow/Tab navigation inside the dashboard. Off hands those keys back to
    // the application underneath.
    CONFIG_PROPERTY(bool, keyboardNav, true)
    CONFIG_SUBOBJECT(DashboardPerformance, performance)

public:
    explicit DashboardConfig(QObject* parent = nullptr)
        : ConfigObject(parent)
        , m_performance(new DashboardPerformance(this)) {}
};

} // namespace burl::config
