pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Burl.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.misc
import qs.services
import qs.utils

// Keybind cheatsheet. Reads keybinds.json, which files/hypr/lib.lua writes on
// every Hyprland config load — `hyprctl binds` cannot serve this, because under
// the lua config every dispatcher comes back as "__lua" with an opaque callback
// index and an empty description.
Scope {
    id: root

    property bool open
    property string filter

    // [{ key, desc, group }], as written by Bind.dump.
    property var binds: []

    readonly property var groups: {
        const needle = root.filter.trim().toLowerCase();
        const out = [];
        const byName = new Map();
        for (const b of root.binds) {
            if (needle && !`${b.key} ${b.desc}`.toLowerCase().includes(needle))
                continue;
            const name = b.group || qsTr("Other");
            let g = byName.get(name);
            if (!g) {
                g = {
                    name: name,
                    binds: []
                };
                byName.set(name, g);
                out.push(g);
            }
            g.binds.push(b);
        }
        return out;
    }

    function show(): void {
        root.filter = "";
        binds.reload();
        root.open = true;
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "cheatsheet"
        description: "Show the keybind cheatsheet"
        onPressed: root.open ? root.open = false : root.show()
    }

    IpcHandler {
        function toggle(): void {
            if (root.open)
                root.open = false;
            else
                root.show();
        }

        target: "cheatsheet"
    }

    FileView {
        id: binds

        path: `${Paths.state}/keybinds.json`
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                root.binds = JSON.parse(text());
            } catch (e) {
                root.binds = [];
            }
        }
        onLoadFailed: root.binds = []
    }

    LazyLoader {
        active: root.open

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData
                readonly property bool onFocused: Hypr.monitorFor(modelData)?.id === Hypr.focusedMonitor?.id

                screen: modelData
                name: "cheatsheet"
                visible: onFocused
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                WlrLayershell.exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Woodland.barkEdge, 0.62)
                    focus: true

                    Component.onCompleted: forceActiveFocus()
                    onVisibleChanged: if (visible)
                        forceActiveFocus()

                    Keys.onEscapePressed: root.open = false
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Backspace) {
                            root.filter = root.filter.slice(0, -1);
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

                        implicitWidth: Math.min(parent.width - Tokens.padding.large * 4, 1180)
                        implicitHeight: Math.min(parent.height - Tokens.padding.large * 4, header.implicitHeight + flick.contentHeight + Tokens.padding.large * 3)

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

                            text: root.filter ? qsTr("Keybinds — %1").arg(root.filter) : qsTr("Keybinds — type to filter")
                            color: Woodland.creamSecondary
                            font: Tokens.font.label.large
                            elide: Text.ElideRight
                        }

                        StyledFlickable {
                            id: flick

                            anchors.top: header.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Tokens.padding.large
                            anchors.topMargin: Tokens.spacing.medium

                            flickableDirection: Flickable.VerticalFlick
                            contentWidth: width
                            contentHeight: columns.implicitHeight

                            StyledScrollBar.vertical: StyledScrollBar {
                                flickable: flick
                            }

                            Flow {
                                id: columns

                                width: flick.width
                                spacing: Tokens.spacing.extraLarge

                                Repeater {
                                    model: ScriptModel {
                                        values: root.groups
                                    }

                                    ColumnLayout {
                                        id: group

                                        required property var modelData

                                        width: (flick.width - Tokens.spacing.extraLarge * 2) / 3
                                        spacing: Tokens.spacing.extraSmall

                                        StyledText {
                                            Layout.bottomMargin: Tokens.spacing.extraSmall
                                            text: group.modelData.name
                                            color: Colours.palette.m3primary
                                            font: Tokens.font.label.medium
                                        }

                                        Repeater {
                                            model: ScriptModel {
                                                values: group.modelData.binds
                                            }

                                            RowLayout {
                                                id: bind

                                                required property var modelData

                                                Layout.fillWidth: true
                                                spacing: Tokens.spacing.medium

                                                StyledRect {
                                                    Layout.preferredWidth: keyLabel.implicitWidth + Tokens.padding.small * 2
                                                    Layout.preferredHeight: keyLabel.implicitHeight + Tokens.padding.extraSmall

                                                    radius: Tokens.rounding.small
                                                    color: Colours.palette.m3surfaceContainerHighest

                                                    StyledText {
                                                        id: keyLabel

                                                        anchors.centerIn: parent
                                                        text: bind.modelData.key.replace(/SUPER/g, "Super").replace(/SHIFT/g, "Shift").replace(/CTRL/g, "Ctrl").replace(/ALT/g, "Alt")
                                                        color: Woodland.creamPrimary
                                                        font: Tokens.font.mono.small
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: bind.modelData.desc
                                                    elide: Text.ElideRight
                                                    color: Woodland.creamSecondary
                                                    font: Tokens.font.body.small
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
}
