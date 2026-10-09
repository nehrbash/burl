pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Burl.Config
import qs.components
import qs.services
import qs.modules.nexus.common

ItemList {
    id: root

    property var nodes: []
    // Paired Bluetooth devices with no PipeWire node yet — listed after the real
    // devices so connecting one is a normal part of picking an output.
    property var offlineDevices: []
    property int currentId: -1
    property string iconName: "speaker"

    signal selected(node: PwNode)

    last: true
    showList: true

    model: ScriptModel {
        values: [...root.nodes].sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || "")).concat([...root.offlineDevices].sort((a, b) => a.name.localeCompare(b.name)))
    }

    delegate: Item {
        id: device

        required property var modelData
        required property int index
        // BluetoothDevice has an address; PwNode does not
        readonly property bool offline: device.modelData?.address !== undefined
        readonly property bool active: !device.offline && device.modelData?.id === root.currentId

        anchors.left: root.list.contentItem.left
        anchors.right: root.list.contentItem.right
        implicitHeight: deviceLayout.implicitHeight + deviceLayout.anchors.margins * 2

        StateLayer {
            radius: Tokens.rounding.extraSmall
            bottomLeftRadius: device.index === root?.list.count - 1 ? Tokens.rounding.extraLarge : radius
            bottomRightRadius: device.index === root?.list.count - 1 ? Tokens.rounding.extraLarge : radius
            onClicked: {
                if (device.offline)
                    Audio.connectBluetoothSink(device.modelData);
                else
                    root.selected(device.modelData);
            }
        }

        RowLayout {
            id: deviceLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: devIcon.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: device.active ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: devIcon

                    anchors.centerIn: parent
                    text: device.offline ? "bluetooth" : root.iconName
                    color: device.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.medium
                    fill: device.active ? 1 : 0

                    Behavior on fill {
                        Anim {}
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: device.modelData?.description || device.modelData?.name || qsTr("Unknown")
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            MaterialIcon {
                text: device.offline ? "link" : "check"
                color: device.offline ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
                opacity: device.active || device.offline ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}
