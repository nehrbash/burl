import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Burl
import Burl.Config
import Burl.Services

Scope {
    id: root

    readonly property list<var> warnLevels: [...GlobalConfig.general.battery.warnLevels].sort((a, b) => b.level - a.level)
    readonly property int hibernateGraceSeconds: 60

    // Critical warnings stay on screen until the charger is connected; a
    // timed toast is easy to miss while away from the laptop.
    property list<QtObject> stickyToasts

    function closeStickyToasts(): void {
        for (const toast of stickyToasts)
            toast?.close();
        stickyToasts = [];
    }

    Connections {
        function onOnBatteryChanged(): void {
            if (UPower.onBattery) {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(qsTr("Charger unplugged"), qsTr("Battery is discharging"), "power_off");
            } else {
                hibernateTimer.stop();
                root.closeStickyToasts();
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(qsTr("Charger plugged in"), qsTr("Battery is charging"), "power");
                for (const level of root.warnLevels)
                    level.warned = false;
            }
        }

        target: UPower
    }

    Connections {
        function onPercentageChanged(): void {
            if (!UPower.onBattery)
                return;

            const p = UPower.displayDevice.percentage * 100;
            for (const level of root.warnLevels) {
                if (p <= level.level && !level.warned) {
                    level.warned = true;
                    const toast = Toaster.toast(level.title ?? qsTr("Battery warning"), level.message ?? qsTr("Battery level is low"), level.icon ?? "battery_android_alert", level.critical ? Toast.Error : Toast.Warning, level.critical ? -1 : 0);
                    if (level.critical)
                        root.stickyToasts.push(toast);
                }
            }

            if (!hibernateTimer.running && p <= GlobalConfig.general.battery.criticalLevel) {
                root.stickyToasts.push(Toaster.toast(qsTr("Hibernating in %1 seconds").arg(root.hibernateGraceSeconds), qsTr("Plug in a charger to cancel"), "battery_android_alert", Toast.Error, -1));
                hibernateTimer.start();
            }
        }

        target: UPower.displayDevice
    }

    Timer {
        id: hibernateTimer

        interval: root.hibernateGraceSeconds * 1000
        onTriggered: {
            root.closeStickyToasts();
            if (UPower.onBattery)
                SessionManager.hibernate();
        }
    }
}
