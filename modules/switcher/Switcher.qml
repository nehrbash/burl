pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.misc
import qs.services
import qs.utils

// Window switcher overlay: every toplevel across every workspace as a live
// preview card, ordered by focus history.
//
// Deliberately NOT bound to Alt+Tab. It is opened by whatever key the user
// binds to the `switcher` global shortcut (or the `switcher` IPC), and all
// navigation happens inside the overlay — so the modifier-hold dance that
// makes Alt+Tab awkward on a tiling compositor never comes up.
Scope {
    id: root

    property bool open

    // Frozen at open. Recomputing while the overlay is up would reshuffle the
    // cards under the cursor every time focus or a title changed.
    property var entries: []
    property int selectedIndex
    property string filter

    readonly property var shown: {
        if (!root.filter)
            return root.entries;
        const needle = root.filter.toLowerCase();
        return root.entries.filter(t => `${t.title} ${t.lastIpcObject?.class ?? ""}`.toLowerCase().includes(needle));
    }

    readonly property HyprlandToplevel current: root.shown[root.selectedIndex] ?? null

    function snapshot(): void {
        const order = Hypr.mru;
        const rank = t => {
            const i = order.indexOf(t.address);
            return i < 0 ? order.length + 1 : i;
        };
        root.entries = Hypr.toplevels.values.slice().sort((a, b) => rank(a) - rank(b));
    }

    function show(): void {
        root.filter = "";
        root.snapshot();
        // Second entry, not the first: the first IS the focused window, and
        // "switch to what I am already on" is never the intent.
        root.selectedIndex = root.entries.length > 1 ? 1 : 0;
        root.open = true;
    }

    function step(delta: int): void {
        const n = root.shown.length;
        if (n === 0)
            return;
        root.selectedIndex = (root.selectedIndex + delta + n) % n;
    }

    function activate(): void {
        const t = root.current;
        root.open = false;
        if (t)
            Hypr.dispatch(`focuswindow address:0x${t.address}`);
    }

    function closeCurrent(): void {
        const t = root.current;
        if (!t)
            return;
        Hypr.dispatch(`killwindow address:0x${t.address}`);
        root.entries = root.entries.filter(e => e !== t);
        if (root.selectedIndex >= root.shown.length)
            root.selectedIndex = Math.max(0, root.shown.length - 1);
        if (root.entries.length === 0)
            root.open = false;
    }

    onFilterChanged: selectedIndex = 0

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "switcher"
        description: "Toggle the window switcher"
        onPressed: root.open ? root.activate() : root.show()
    }

    IpcHandler {
        function toggle(): void {
            if (root.open)
                root.activate();
            else
                root.show();
        }

        // Named show/hide, not open/close: an IpcHandler function whose name
        // matches a property on the enclosing scope is silently dropped.
        function show(): void {
            root.show();
        }

        function hide(): void {
            root.open = false;
        }

        function next(): void {
            if (!root.open)
                root.show();
            else
                root.step(1);
        }

        function prev(): void {
            if (!root.open)
                root.show();
            else
                root.step(-1);
        }

        target: "switcher"
    }

    LazyLoader {
        active: root.open

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData
                // One overlay, on the monitor that has focus. Mirroring it onto
                // every screen would mean N screencopy streams of the same
                // window and two places to look for the selection.
                readonly property bool onFocused: Hypr.monitorFor(modelData)?.id === Hypr.focusedMonitor?.id

                screen: modelData
                name: "switcher"
                visible: onFocused
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    id: dim

                    anchors.fill: parent
                    color: Qt.alpha(Woodland.barkEdge, 0.62)
                    focus: true

                    Component.onCompleted: forceActiveFocus()
                    onVisibleChanged: if (visible)
                        forceActiveFocus()

                    Keys.onEscapePressed: root.open = false
                    Keys.onReturnPressed: root.activate()
                    Keys.onEnterPressed: root.activate()
                    Keys.onLeftPressed: root.step(-1)
                    Keys.onRightPressed: root.step(1)
                    Keys.onUpPressed: root.step(-grid.cols)
                    Keys.onDownPressed: root.step(grid.cols)
                    Keys.onTabPressed: root.step(1)
                    Keys.onBacktabPressed: root.step(-1)

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Backspace) {
                            root.filter = root.filter.slice(0, -1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                            root.closeCurrent();
                            event.accepted = true;
                        } else if (event.text && event.text.charCodeAt(0) >= 0x20) {
                            root.filter += event.text;
                            event.accepted = true;
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.open = false
                    }

                    WoodPanel {
                        anchors.centerIn: parent

                        implicitWidth: Math.min(parent.width - Tokens.padding.large * 4, grid.width + Tokens.padding.large * 2)
                        implicitHeight: header.implicitHeight + grid.implicitHeight + Tokens.padding.large * 3

                        radius: Tokens.rounding.extraLarge
                        framed: true
                        fill: Colours.palette.m3surfaceContainer

                        MouseArea {
                            anchors.fill: parent
                        }

                        StyledText {
                            id: header

                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Tokens.padding.large

                            text: root.filter ? qsTr("%1 — %2 of %3").arg(root.filter).arg(root.shown.length ? root.selectedIndex + 1 : 0).arg(root.shown.length) : qsTr("%1 window%2 — type to filter, Ctrl+W closes").arg(root.shown.length).arg(root.shown.length === 1 ? "" : "s")
                            color: Woodland.creamSecondary
                            font: Tokens.font.label.large
                            elide: Text.ElideRight
                        }

                        Column {
                            id: grid

                            readonly property int cols: Math.max(1, Math.min(4, root.shown.length))
                            readonly property real cellW: 300
                            readonly property real cellH: 200
                            readonly property int rows: Math.ceil(root.shown.length / cols)

                            anchors.top: header.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: Tokens.padding.large

                            width: grid.cols * grid.cellW + (grid.cols - 1) * Tokens.spacing.medium
                            spacing: Tokens.spacing.medium

                            Repeater {
                                model: grid.rows

                                // Hand-rolled rows rather than a Grid: a Grid
                                // left-aligns a short final row, which reads as
                                // a layout bug next to the centred ones.
                                Row {
                                    id: rowItem

                                    required property int index

                                    // Column owns y only, so setting x here
                                    // centres the row without fighting it (an
                                    // anchor would).
                                    x: (grid.width - width) / 2
                                    spacing: Tokens.spacing.medium

                                    Repeater {
                                        model: ScriptModel {
                                            values: root.shown.slice(rowItem.index * grid.cols, (rowItem.index + 1) * grid.cols)
                                        }

                                        Card {
                                            id: card

                                            required property int index
                                            required property var modelData

                                            readonly property int flatIndex: rowItem.index * grid.cols + card.index

                                            width: grid.cellW
                                            height: grid.cellH

                                            client: modelData
                                            selected: card.flatIndex === root.selectedIndex
                                            live: card.flatIndex === root.selectedIndex

                                            onActivated: {
                                                root.selectedIndex = card.flatIndex;
                                                root.activate();
                                            }
                                            onCloseRequested: {
                                                root.selectedIndex = card.flatIndex;
                                                root.closeCurrent();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
