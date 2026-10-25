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

    RowLayout {
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { text: "Syncthing"; font: Tokens.font.title.medium }
            StyledText {
                Layout.fillWidth: true
                text: Syncthing.summary + " · " + qsTr("%1 connected").arg(Syncthing.connectedCount)
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }
        }
        ServiceActionButton {
            icon: "refresh"
            description: Syncthing.refreshing ? qsTr("Refreshing…") : qsTr("Refresh Syncthing")
            enabled: Syncthing.enabled && !Syncthing.refreshing && !Syncthing.busy
            onClicked: Syncthing.refresh()
        }
        ServiceActionButton {
            icon: "open_in_new"
            description: qsTr("Open Syncthing web interface")
            enabled: Syncthing.available
            onClicked: Qt.openUrlExternally(Syncthing.baseUrl)
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: Syncthing.error || Syncthing.actionError
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
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
                subtext: root.compact ? folder.modelData.state : folder.modelData.needed ? qsTr("%1 items remaining · %2 errors").arg(folder.modelData.needed).arg(folder.modelData.errors) : folder.modelData.path
                value: root.compact ? "" : folder.modelData.state
                trailingComponent: RowLayout {
                    spacing: Tokens.spacing.extraSmall
                    ServiceActionButton {
                        icon: folder.modelData.paused ? "play_arrow" : "pause"
                        description: folder.modelData.paused ? qsTr("Resume folder") : qsTr("Pause folder")
                        enabled: Syncthing.available && !Syncthing.busy
                        onClicked: Syncthing.pauseFolder(folder.modelData)
                    }
                    ServiceActionButton {
                        icon: "refresh"
                        description: qsTr("Rescan folder")
                        enabled: Syncthing.available && !Syncthing.busy && !folder.modelData.paused
                        onClicked: Syncthing.scan(folder.modelData)
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 4
                radius: 2
                visible: !folder.modelData.paused && ["Syncing", "Out of sync"].includes(folder.modelData.state)
                color: Colours.palette.m3surfaceContainerHighest
                Rectangle {
                    width: parent.width * folder.modelData.progress
                    height: parent.height
                    radius: parent.radius
                    color: folder.modelData.state === "Error" ? Colours.palette.m3error : Colours.palette.m3primary
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
                trailingComponent: ServiceActionButton {
                    icon: device.modelData.paused ? "play_arrow" : "pause"
                    description: device.modelData.paused ? qsTr("Resume device") : qsTr("Pause device")
                    enabled: Syncthing.available && !Syncthing.busy
                    onClicked: Syncthing.pauseDevice(device.modelData)
                }
            }
        }
    }
}
