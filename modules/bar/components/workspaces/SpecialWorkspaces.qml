pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.components
import qs.components.widgets
import qs.services
import Burl.Config
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property string activeSpecial: (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? monitor : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace?.name ?? ""

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: view.contentHeight

    // Hit-test for the workspace branch popout — y in this item's space.
    // Returns [wsId, centerY] or null.
    function wsAt(y: real): var {
        const d = view.itemAt(view.width / 2, y + view.contentY) as SpecialWsDelegate;
        return d ? [d.wsId, d.y - view.contentY + d.implicitHeight / 2] : null;
    }

    ListView {
        id: view

        anchors.fill: parent
        spacing: Tokens.spacing.medium
        interactive: false

        currentIndex: model.values.findIndex(w => w.name === root.activeSpecial)
        onCurrentIndexChanged: currentIndex = Qt.binding(() => model.values.findIndex(w => w.name === root.activeSpecial))

        model: ScriptModel {
            values: Hypr.workspaces.values.filter(w => w.name.startsWith("special:") && (!GlobalConfig.bar.workspaces.perMonitorWorkspaces || w.monitor === root.monitor))
        }

        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        highlightRangeMode: ListView.StrictlyEnforceRange

        highlightFollowsCurrentItem: false
        highlight: Item {
            y: view.currentItem?.y ?? 0
            implicitHeight: (view.currentItem as SpecialWsDelegate)?.size ?? 0

            Behavior on y {
                Anim {}
            }
        }

        delegate: SpecialWsDelegate {}

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        remove: Transition {
            Anim {
                property: "scale"
                to: 0.5
                duration: Tokens.anim.durations.small
            }
            Anim {
                property: "opacity"
                to: 0
                duration: Tokens.anim.durations.small
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        displaced: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }
    }

    MouseArea {
        property real startY

        anchors.fill: view

        drag.target: view.contentItem
        drag.axis: Drag.YAxis
        drag.maximumY: 0
        drag.minimumY: Math.min(0, view.height - view.contentHeight - Tokens.padding.extraSmall)

        onPressed: event => startY = event.y

        onClicked: event => {
            if (Math.abs(event.y - startY) > drag.threshold)
                return;

            const ws = view.itemAt(event.x, event.y) as SpecialWsDelegate;
            if (ws?.modelData)
                ShellState.selectWorkspace([Hypr.usingLua ? `hl.dsp.workspace.toggle_special("${ws.modelData.name.slice(8)}")` : `togglespecialworkspace ${ws.modelData.name.slice(8)}`]);
            else
                ShellState.selectWorkspace([Hypr.usingLua ? 'hl.dsp.workspace.toggle_special("special")' : "togglespecialworkspace special"]);
        }
    }

    component SpecialWsDelegate: Item {
        id: ws

        required property HyprlandWorkspace modelData
        readonly property bool isActive: modelData?.name === root.activeSpecial
            && Config.bar.workspaces.activeIndicator
        readonly property int size: Tokens.sizes.bar.innerWidth
        property int wsId
        property string icon

        readonly property bool hasWindows: Config.bar.workspaces.showWindowsOnSpecialWorkspaces && Hypr.toplevels.values.some(c => c.workspace?.id === ws.wsId)

        anchors.left: view.contentItem.left
        anchors.right: view.contentItem.right
        implicitHeight: size + (hasWindows ? windowLoader.height * 0.55 : 0)

        Component.onCompleted: {
            wsId = modelData.id;
            icon = Icons.getSpecialWsIcon(modelData.name);
        }

        // modelData gets destroyed before the remove anim finishes
        Connections {
            function onIdChanged(): void {
                if (ws.modelData)
                    ws.wsId = ws.modelData.id;
            }

            function onNameChanged(): void {
                if (ws.modelData)
                    ws.icon = Icons.getSpecialWsIcon(ws.modelData.name);
            }

            target: ws.modelData ?? null
        }

        BarkSocket {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (ws.size - height) / 2
            width: ws.size * 0.72
            height: width
        }

        Shape {
            id: seal
            anchors.horizontalCenter: parent.horizontalCenter
            y: (ws.size - height) / 2
            width: ws.size - 1
            height: width
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: ws.isActive ? Colours.palette.m3tertiary : Qt.alpha(Woodland.parchmentEdge, 0.58)
                strokeWidth: ws.isActive ? 1.6 : 1
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: seal.width / 2
                    centerY: seal.height / 2
                    radiusX: seal.width * 0.45
                    radiusY: radiusX
                    startAngle: 135
                    sweepAngle: 270
                }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(ws.isActive ? Colours.palette.m3tertiary : Woodland.parchmentEdge, ws.isActive ? 0.72 : 0.34)
                strokeWidth: 1
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: seal.width / 2
                    centerY: seal.height / 2
                    radiusX: seal.width * 0.30
                    radiusY: radiusX
                    startAngle: 20
                    sweepAngle: 48
                }
            }
        }

        Repeater {
            model: 7
            delegate: Rectangle {
                required property int index
                readonly property real angle: (150 + index * 40) * Math.PI / 180
                x: ws.width / 2 + Math.cos(angle) * ws.size * 0.4 - width / 2
                y: ws.size / 2 + Math.sin(angle) * ws.size * 0.4 - height / 2
                width: 1
                height: ws.size * 0.08
                rotation: 150 + index * 40 + 90
                color: ws.isActive ? Colours.palette.m3tertiary : Qt.alpha(Woodland.parchmentEdge, 0.58)
            }
        }

        Loader {
            id: windowLoader

            anchors.horizontalCenter: parent.horizontalCenter
            y: ws.size - height * 0.45
            width: ws.size * 0.55
            height: width

            asynchronous: true
            visible: active
            active: ws.hasWindows

            sourceComponent: BarkSocket {
                id: appSeal
                readonly property string activeClass: {
                    const tls = Hypr.toplevels.values.filter(c => c.workspace?.id === ws.wsId);
                    const active = tls.find(t => t.activated) ?? tls[0];
                    return active ? (active.lastIpcObject?.class ?? active.wayland?.appId ?? "") : "";
                }

                IconImage {
                    anchors.fill: parent
                    anchors.margins: parent.width * 0.16
                    source: Icons.getAppIcon(appSeal.activeClass, "application-x-executable")
                    asynchronous: true
                }
            }
        }

        readonly property int glyphSize: Math.round((Tokens.sizes.bar.innerWidth - 4) * 0.55)

        Loader {
            id: label

            asynchronous: true
            anchors.horizontalCenter: parent.horizontalCenter
            y: (ws.size - height) / 2

            sourceComponent: ws.icon.length === 1 ? letterComp : iconComp

            Component {
                id: iconComp

                Item {
                    implicitWidth: ws.glyphSize
                    implicitHeight: ws.glyphSize

                    MaterialIcon {
                        anchors.centerIn: parent
                        fill: 1
                        text: ws.icon
                        color: Woodland.parchment
                        font.pixelSize: ws.glyphSize
                        horizontalAlignment: Qt.AlignHCenter
                        verticalAlignment: Qt.AlignVCenter
                    }
                }
            }

            Component {
                id: letterComp

                Item {
                    implicitWidth: ws.glyphSize
                    implicitHeight: ws.glyphSize

                    StyledText {
                        anchors.centerIn: parent
                        text: ws.icon
                        color: Woodland.parchment
                        font.pixelSize: ws.glyphSize
                        horizontalAlignment: Qt.AlignHCenter
                        verticalAlignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }
}
