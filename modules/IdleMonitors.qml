pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Burl.Config
import Burl.Services
import qs.services
// Aliased so the IdleInhibitor singleton can be named unambiguously: a bare
// `IdleInhibitor` resolves to the Quickshell.Wayland *type* of the same name
// (imported for IdleMonitor), which shadowed the singleton and made every read
// return undefined -- so the "Keep Awake" toggle was silently never observed.
import qs.services as Services

Scope {
    id: root

    required property Lock lock
    readonly property bool hasPlayer: Players.list.some(p => p.isPlaying)
    readonly property bool isCharging: !UPower.onBattery
    readonly property bool enabled: {
        if (GlobalConfig.general.idle.inhibitWhenAudio && hasPlayer)
            return false;
        if (GlobalConfig.general.idle.inhibitWhenCharging && isCharging)
            return false;
        return true;
    }

    // "Keep Awake" state. The monitors below gate on this directly rather than
    // relying on the compositor honouring the inhibit surface: Hyprland only
    // respects idle inhibitors on toplevel windows, not on the layer-shell
    // surface this singleton creates, so "Keep Awake" would otherwise still
    // lock/dpms/suspend.
    readonly property bool idleInhibited: Services.IdleInhibitor.enabled

    // A binding alone does not eagerly load a lazy Quickshell singleton; touch
    // it from JS at startup so its persisted state + inhibit surface come up
    // immediately rather than only when the utilities card is first opened.
    Component.onCompleted: void Services.IdleInhibitor.enabled

    Connections {
        target: root.lock.lock
        function onLockedChanged(): void {
            if (root.lock.lock.locked && Tasks.clockedIn)
                Tasks.clockOut();
        }
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock")
            lock.lock.locked = true;
        else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(Hypr.usingLua && ["dpms off", "dpms on"].includes(action) ? `hl.dsp.dpms({ action = "${action === "dpms off" ? "disable" : "enable"}" })` : action);
        else if (!Services.IdleInhibitor.execSessionAction(action))
            Quickshell.execDetached(action);
    }

    Connections {
        function onAboutToSleep(): void {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }

        function onLockRequested(): void {
            root.lock.lock.locked = true;
        }

        function onUnlockRequested(): void {
            root.lock.lock.unlock();
        }

        target: SessionManager
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: {
                if (!root.enabled || root.idleInhibited || !(modelData.enabled ?? true))
                    return false;
                if (modelData.inhibitWhenAudio && root.hasPlayer)
                    return false;
                if (modelData.inhibitWhenCharging && root.isCharging)
                    return false;
                return true;
            }
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
