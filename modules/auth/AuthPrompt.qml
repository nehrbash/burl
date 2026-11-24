pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

StyledWindow {
    id: win

    required property var auth
    // Resolved when the prompt opens so it does not hop monitors mid-typing.
    readonly property ShellScreen target: Quickshell.screens.find(s => Hypr.monitorFor(s)?.id === Hypr.focusedMonitor?.id) ?? Quickshell.screens[0]

    screen: target
    name: "auth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    AuthPanel {
        anchors.fill: parent
        auth: win.auth
    }
}
