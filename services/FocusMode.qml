pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import Burl.Config
import qs.services

Singleton {
    id: root

    // Create the owner before PersistentProperties restores the reload graph.
    readonly property var compositorEffects: CompositorEffects

    property alias enabled: props.enabled

    onEnabledChanged: {
        root.compositorEffects.setMode("focus", enabled);
        if (enabled)
            ShellState.setBarAll(false);
        Toaster.toast(enabled ? qsTr("Focus mode on") : qsTr("Focus mode off"), enabled ? qsTr("Bar hidden; gaps, rounding, animations, opacity off") : qsTr("Bar and window chrome restored"), "center_focus_strong");
    }

    PersistentProperties {
        id: props

        property bool enabled

        reloadableId: "focusMode"
        onLoaded: root.compositorEffects.setMode("focus", enabled)
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
