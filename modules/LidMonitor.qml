import "../services/IdlePolicy.js" as IdlePolicy
import "../services/LidPolicy.js" as LidPolicy
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Burl.Config
import Burl.Services
import qs.services

Scope {
    id: root

    required property var idle
    readonly property var lid: GlobalConfig.general.lid
    readonly property bool active: lid.handle && SessionManager.lidPresent
    property string performed

    function run(steps: var): void {
        for (const step of steps)
            idle.handleIdleAction(step);
    }

    function handleClosed(): void {
        const name = LidPolicy.actionFor(lid, {
            onBattery: UPower.onBattery,
            docked: LidPolicy.docked(Hypr.monitors.values.map(m => m.name))
        });
        performed = name;
        run(LidPolicy.closeSteps(name, {
            lockBeforeSleep: GlobalConfig.general.idle.lockBeforeSleep,
            sleepAction: IdlePolicy.sleepAction(GlobalConfig.general.idle.sleepAction)
        }));
    }

    function handleOpened(): void {
        const steps = LidPolicy.openSteps(performed);
        performed = "";
        run(steps);
    }

    Binding {
        target: SessionManager
        property: "lidInhibited"
        value: root.active
    }

    Connections {
        function onLidClosedChanged(): void {
            if (!root.active)
                return;
            if (SessionManager.lidClosed)
                root.handleClosed();
            else
                root.handleOpened();
        }

        target: SessionManager
    }
}
