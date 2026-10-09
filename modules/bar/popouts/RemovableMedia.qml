pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Burl.Config
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts

    width: 300
    spacing: Tokens.spacing.small

    StyledText {
        Layout.topMargin: Tokens.padding.medium
        Layout.rightMargin: Tokens.padding.small
        text: qsTr("Removable media")
        font.weight: 500
    }

    StyledText {
        Layout.rightMargin: Tokens.padding.small
        text: {
            const n = Disks.mounted.length;
            return qsTr("%1 drive%2 mounted").arg(n).arg(n === 1 ? "" : "s");
        }
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: Tokens.font.body.small.pointSize
    }

    Repeater {
        model: ScriptModel {
            values: Disks.mounted
        }

        RowLayout {
            id: drive

            required property var modelData

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            opacity: 0
            scale: 0.7

            Component.onCompleted: {
                opacity = 1;
                scale = 1;
            }

            Behavior on opacity {
                Anim {}
            }

            Behavior on scale {
                Anim {}
            }

            StyledRect {
                Layout.fillWidth: true
                implicitHeight: labels.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.small
                color: "transparent"

                StateLayer {
                    radius: Tokens.rounding.small
                    onClicked: Disks.open(drive.modelData)
                }

                MaterialIcon {
                    id: driveIcon

                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.small
                    anchors.verticalCenter: parent.verticalCenter
                    text: "usb"
                }

                ColumnLayout {
                    id: labels

                    anchors.left: driveIcon.right
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: drive.modelData.label
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `${drive.modelData.fstype || qsTr("unknown")} · ${drive.modelData.size}`
                        elide: Text.ElideRight
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.font.body.small.pointSize
                    }
                }
            }

            StyledRect {
                id: ejectBtn

                implicitWidth: implicitHeight
                implicitHeight: ejectIcon.implicitHeight + Tokens.padding.small

                radius: Tokens.rounding.full
                color: Colours.palette.m3secondaryContainer

                StateLayer {
                    color: Colours.palette.m3onSecondaryContainer
                    disabled: Disks.busy
                    onClicked: Disks.eject(drive.modelData)
                }

                MaterialIcon {
                    id: ejectIcon

                    anchors.centerIn: parent
                    text: "eject"
                    color: Colours.palette.m3onSecondaryContainer
                }
            }
        }
    }
}
