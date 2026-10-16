import QtQuick
import Quickshell
import Burl.Config
import qs.components

ShellRoot {
    id: root
    settings.watchFiles: false

    ScreenState {
        id: navigation
        modelData: Quickshell.screens[0]
    }

    PersistentProperties {
        id: progress
        reloadableId: "navigation-fixture-progress"
        property int phase: 0
        onLoaded: Qt.callLater(root.run)
    }

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    function equal(actual, expected, message) {
        check(JSON.stringify(actual) === JSON.stringify(expected),
              message + ": " + JSON.stringify(actual));
    }

    function run() {
        try {
            if (progress.phase === 0)
                initial();
            else if (progress.phase === 1)
                reloaded();
            else if (progress.phase === 2)
                invalidRestored();
            else if (progress.phase === 3)
                disabledRestored();
            else
                throw new Error("unexpected reload phase " + progress.phase);
        } catch (error) {
            console.error("NAVIGATION-FAIL", error.message);
            Qt.quit();
        }
    }

    function initial() {
        equal(navigation.dashboardSectionIds,
              ["dashboard", "media", "performance", "weather", "tasks"],
              "ordered catalog exists before any view");
        equal(navigation.dashboardEnabledIds,
              ["dashboard", "media", "performance", "tasks"],
              "global disabled setting is resolved before any view");
        check(!navigation.selectDashboardSection("weather"), "disabled section rejected");
        check(!navigation.selectDashboardSection("missing"), "unknown section rejected");
        check(navigation.selectDashboardTab(1), "tab command accepted before any view");
        check(navigation.dashboardSection === "media" && navigation.dashboardTab === 1,
              "tab command resolved immediately");

        const config = GlobalConfig.forScreen(navigation.modelData.name).dashboard;
        check(GlobalConfig.dashboard.navStyle === "living", "global navigation default is living");
        config.navStyle = "tabs";
        check(navigation.dashboardConfig.navStyle === "tabs" && GlobalConfig.dashboard.navStyle === "living",
              "screen tabs override is independent of global living");
        GlobalConfig.dashboard.navStyle = "tabs";
        config.navStyle = "living";
        check(navigation.dashboardConfig.navStyle === "living" && GlobalConfig.dashboard.navStyle === "tabs",
              "screen living override is independent of global tabs");
        config.showWeather = true;
        check(!GlobalConfig.dashboard.showWeather, "screen override does not change global config");
        check(navigation.dashboardEnabledIds.includes("weather"), "screen override reaches catalog");
        config.showMedia = false;
        equal(navigation.dashboardOpenSections, [], "disabled open section is folded");
        check(navigation.dashboardSection === "dashboard", "disabled selection reconciles");
        equal(navigation.dashboardEnabledIds, ["dashboard", "performance", "weather", "tasks"],
              "catalog follows screen config changes");

        navigation.openWorldRoom("dashboard");
        check(navigation.selectDashboardSection("tasks"), "select persistent intent");
        navigation.dashboardWantsKeyboard = true;
        navigation.dashboardOpenedByKey = true;
        navigation.dashboardTreePinned = true;
        navigation.dashboardTreeGrown = true;
        navigation.dashboardMaskRects = [{x: 1, y: 2, width: 3, height: 4}];
        navigation.dashboardTrunkRect = {x: 1, y: 2, width: 3, height: 4};
        progress.phase = 1;
        console.log("NAVIGATION-INITIAL-PASS");
        Qt.callLater(function () { Quickshell.reload(false); });
    }

    function reloaded() {
        check(navigation.dashboard && !navigation.launcher, "open room survives reload");
        check(navigation.dashboardSection === "tasks", "selected intent survives reload");
        equal(navigation.dashboardOpenSections, ["tasks"], "open section survives reload");
        check(navigation.dashboardFocusSection === "tasks", "focus ring survives reload");
        check(!navigation.dashboardWantsKeyboard && !navigation.dashboardOpenedByKey
              && !navigation.dashboardTreePinned && !navigation.dashboardTreeGrown,
              "transient focus and presentation reset");
        equal(navigation.dashboardMaskRects, [], "mask rectangles reset");
        check(navigation.dashboardTrunkRect === null, "trunk rectangle resets");

        const config = GlobalConfig.forScreen(navigation.modelData.name).dashboard;
        config.showPerformance = false;
        check(!navigation.dashboardEnabledIds.includes("performance"), "enabled binding survives reload");
        check(navigation.dashboardTab === navigation.dashboardEnabledIds.indexOf("tasks"),
              "derived tab binding survives reload");
        config.showPerformance = true;
        check(navigation.dashboardEnabledIds.includes("performance"), "enabled binding reacts twice");
        check(navigation.dashboardTab === navigation.dashboardEnabledIds.indexOf("tasks"),
              "derived tab index follows restored config");
        console.log("NAVIGATION-RELOAD-PASS");
        config.showWeather = false;
        navigation.dashboardSection = "missing";
        navigation.dashboardFocusSection = "weather";
        check(navigation.dashboardSection === "missing", "unknown intent seeded before reload");
        progress.phase = 2;
        Qt.callLater(function () { Quickshell.reload(false); });
    }

    function invalidRestored() {
        check(navigation.dashboardSection === "tasks", "unknown restored selection reconciles to open section");
        check(navigation.dashboardFocusSection === navigation.dashboardEnabledIds[0],
              "disabled restored focus reconciles");
        equal(navigation.dashboardOpenSections, ["tasks"], "valid open intent survives invalid selection");
        navigation.dashboardSection = "weather";
        navigation.dashboardFocusSection = "missing";
        check(navigation.dashboardSection === "weather", "disabled intent seeded before reload");
        progress.phase = 3;
        Qt.callLater(function () { Quickshell.reload(false); });
    }

    function disabledRestored() {
        check(!navigation.dashboardEnabledIds.includes("weather"), "restored disabled fixture remains disabled");
        check(navigation.dashboardSection === "tasks", "disabled restored selection reconciles");
        check(navigation.dashboardFocusSection === navigation.dashboardEnabledIds[0],
              "unknown restored focus reconciles");
        check(navigation.dashboardTab === navigation.dashboardEnabledIds.indexOf("tasks"),
              "tab binding follows reconciled selection");
        console.log("NAVIGATION-RESTORE-RECONCILE-PASS");
        Qt.quit();
    }
}
