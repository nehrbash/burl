pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Burl.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    property bool compact: false

    spacing: Tokens.spacing.small

    StyledText {
        Layout.fillWidth: true
        text: "Syncthing · " + Syncthing.summary
        font: Tokens.font.title.medium
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: Syncthing.error || Syncthing.actionError
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        text: qsTr("%1 devices connected · local folder status").arg(Syncthing.connectedCount)
        wrapMode: Text.Wrap
    }
    RowLayout {
        TextButton {
            text: Syncthing.refreshing ? qsTr("Refreshing…") : qsTr("Refresh")
            enabled: Syncthing.enabled && !Syncthing.refreshing && !Syncthing.busy
            onClicked: Syncthing.refresh()
        }
        TextButton {
            text: qsTr("Open web interface")
            enabled: Syncthing.available
            onClicked: Qt.openUrlExternally(Syncthing.baseUrl)
        }
    }
    Repeater {
        model: root.compact ? Syncthing.folders.slice(0, 4) : Syncthing.folders
        delegate: ColumnLayout {
            id: folder
            required property var modelData
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            InfoRow {
                first: true
                last: true
                icon: folder.modelData.state === "Error" ? "sync_problem" : folder.modelData.paused ? "pause" : "folder"
                label: folder.modelData.name
                subtext: folder.modelData.needed ? qsTr("%1 items remaining · %2 errors").arg(folder.modelData.needed).arg(folder.modelData.errors) : folder.modelData.path
                value: folder.modelData.state
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                visible: !folder.modelData.paused
                color: Colours.palette.m3surfaceContainerHighest
                Rectangle {
                    width: parent.width * folder.modelData.progress
                    height: parent.height
                    radius: parent.radius
                    color: folder.modelData.state === "Error" ? Colours.palette.m3error : Colours.palette.m3primary
                }
            }
            RowLayout {
                TextButton {
                    text: folder.modelData.paused ? qsTr("Resume") : qsTr("Pause")
                    enabled: Syncthing.available && !Syncthing.busy
                    onClicked: Syncthing.pauseFolder(folder.modelData)
                }
                TextButton {
                    text: qsTr("Rescan")
                    enabled: Syncthing.available && !Syncthing.busy && !folder.modelData.paused
                    onClicked: Syncthing.scan(folder.modelData)
                }
            }
        }
    }
    StyledText {
        visible: Syncthing.available && !Syncthing.folders.length
        text: qsTr("No shared folders configured")
    }
    SectionHeader {
        visible: !root.compact
        text: qsTr("Devices")
    }
    Repeater {
        model: root.compact ? [] : Syncthing.devices
        delegate: ColumnLayout {
            id: device
            required property var modelData
            Layout.fillWidth: true
            InfoRow {
                first: true
                last: true
                label: device.modelData.name
                subtext: device.modelData.address
                value: device.modelData.paused ? qsTr("Paused") : device.modelData.connected ? qsTr("Connected") : qsTr("Disconnected")
                icon: "devices"
            }
            TextButton {
                text: device.modelData.paused ? qsTr("Resume") : qsTr("Pause")
                enabled: Syncthing.available && !Syncthing.busy
                onClicked: Syncthing.pauseDevice(device.modelData)
            }
        }
    }
}
