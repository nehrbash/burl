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
                text: [Syncthing.summary,
                    Syncthing.available ? qsTr("%1/%2 devices online").arg(Syncthing.connectedCount).arg(Syncthing.devices.length) : "",
                    Syncthing.updatedAt ? qsTr("checked %1").arg(Syncthing.ago(Syncthing.updatedAt)) : ""].filter(t => t).join(" · ")
                color: Colours.palette.m3onSurfaceVariant
                wrapMode: Text.Wrap
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
                subtext: [root.compact && folder.modelData.state !== "Up to date" ? folder.modelData.state : "",
                    folder.modelData.needed ? qsTr("%1 items remaining · %2 errors").arg(folder.modelData.needed).arg(folder.modelData.errors)
                    : folder.modelData.lastChange ? qsTr("changed %1").arg(Syncthing.ago(folder.modelData.lastChange)) : qsTr("no changes yet"),
                    !root.compact && folder.modelData.lastScan ? qsTr("scanned %1").arg(Syncthing.ago(folder.modelData.lastScan)) : ""].filter(t => t).join(" · ")
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
        visible: Syncthing.devices.length > 0
        text: qsTr("Devices")
    }
    Repeater {
        model: Syncthing.devices
        delegate: ColumnLayout {
            id: device
            required property var modelData
            Layout.fillWidth: true
            InfoRow {
                first: true
                last: true
                label: device.modelData.name
                subtext: [device.modelData.connected ? qsTr("Online") : device.modelData.lastSeen ? qsTr("Last seen %1").arg(Syncthing.ago(device.modelData.lastSeen)) : qsTr("Never seen"),
                    root.compact ? "" : device.modelData.address].filter(t => t).join(" · ")
                value: device.modelData.paused ? qsTr("Paused")
                    : device.modelData.completion < 0 ? ""
                    : device.modelData.completion >= 100 ? qsTr("Up to date")
                    : qsTr("%1% · %2 items behind").arg(Math.floor(device.modelData.completion)).arg(device.modelData.needed)
                icon: device.modelData.connected ? "devices" : "devices_off"
                iconColour: device.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
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
