pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import Burl.Config
import qs.services

// Distraction-free mode. Strips Hyprland window chrome — no gaps
// (padding), no rounding, no animations, no opacity (transparency) — and
// hides the qs bar. Everything but the bar is Hyprland state, so it
// mirrors GameMode: push runtime options via IPC on enter, restore by
// reloading the Hyprland config on exit. BarWrapper reads `enabled` to
// override bar.persistent; writing the config instead would persist the
// hidden bar to shell.json across restarts.
Singleton {
    id: root

    property alias enabled: props.enabled

    // Sent as raw lua evals (not applyOptions) because applyOptions falls
    // back to `keyword` when Hyprland.usingLua is unset, and this config's
    // non-legacy parser rejects `keyword`. hl.config is the lua-native path.
    function setDynamicConfs(): void {
        Hypr.extras.batchMessage(["eval hl.config({ animations = { enabled = 0 } })", "eval hl.config({ general = { gaps_in = 0 } })", "eval hl.config({ general = { gaps_out = 0 } })", "eval hl.config({ decoration = { rounding = 0 } })", "eval hl.config({ decoration = { active_opacity = 1 } })", "eval hl.config({ decoration = { inactive_opacity = 1 } })"]);
    }

    onEnabledChanged: {
        if (enabled) {
            setDynamicConfs();
            ShellState.setBarAll(false);
        } else {
            Hypr.extras.message("reload");
        }
        Toaster.toast(enabled ? qsTr("Focus mode on") : qsTr("Focus mode off"), enabled ? qsTr("Bar hidden; gaps, rounding, animations, opacity off") : qsTr("Bar and window chrome restored"), "center_focus_strong");
    }

    // Hyprland options are wiped by a config reload (monitor hotplug, etc).
    // Re-apply while focus mode is still on, same as GameMode.
    Connections {
        function onConfigReloaded(): void {
            if (props.enabled)
                root.setDynamicConfs();
        }

        target: Hypr
    }

    PersistentProperties {
        id: props

        property bool enabled

        reloadableId: "focusMode"
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            props.enabled = true;
        }

        function disable(): void {
            props.enabled = false;
        }

        target: "focusMode"
    }
}
