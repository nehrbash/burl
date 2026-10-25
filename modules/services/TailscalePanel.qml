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
        text: "Tailscale · " + Tailscale.summary
        font: Tokens.font.title.medium
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: Tailscale.error || Tailscale.actionError || Tailscale.details.health.join("\n")
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        text: [Tailscale.details.name, Tailscale.details.ip, Tailscale.details.tailnet].filter(Boolean).join(" · ")
        wrapMode: Text.Wrap
    }
    RowLayout {
        TextButton {
            text: Tailscale.busy ? qsTr("Working…") : Tailscale.connected ? qsTr("Disconnect") : qsTr("Connect")
            enabled: Tailscale.enabled && !Tailscale.busy && !Tailscale.error
            onClicked: Tailscale.toggle()
        }
        TextButton {
            text: qsTr("Copy IP")
            enabled: Tailscale.connected && !!Tailscale.details.ip
            onClicked: Quickshell.clipboardText = Tailscale.details.ip
        }
        TextButton {
            text: qsTr("Refresh")
            enabled: Tailscale.enabled && !Tailscale.busy
            onClicked: Tailscale.refresh()
        }
    }
    TextButton {
        visible: !!Tailscale.details.authUrl
        text: qsTr("Sign in")
        onClicked: Qt.openUrlExternally(Tailscale.details.authUrl)
    }
    SectionHeader {
        text: qsTr("Peers · %1 online").arg(Tailscale.onlineCount)
    }
    Repeater {
        model: root.compact ? Tailscale.details.peers.slice(0, 4) : Tailscale.details.peers
        delegate: ColumnLayout {
            id: peer
            required property var modelData
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            InfoRow {
                first: true
                last: true
                label: peer.modelData.name
                subtext: peer.modelData.ip + (peer.modelData.exitNode ? " · " + qsTr("Exit node") : "")
                value: peer.modelData.online ? qsTr("Online") + " · " + peer.modelData.connection : qsTr("Offline")
                icon: peer.modelData.online ? "devices" : "cloud_off"
            }
            RowLayout {
                TextButton {
                    text: qsTr("Copy IP")
                    enabled: !!peer.modelData.ip
                    onClicked: Quickshell.clipboardText = peer.modelData.ip
                }
                TextButton {
                    visible: !root.compact && (peer.modelData.exitAvailable || peer.modelData.exitNode)
                    text: peer.modelData.exitNode ? qsTr("Stop using exit node") : qsTr("Use exit node")
                    enabled: Tailscale.connected && !Tailscale.busy && (peer.modelData.online || peer.modelData.exitNode)
                    onClicked: Tailscale.setExitNode(peer.modelData.exitNode ? "" : peer.modelData.ip)
                }
            }
        }
    }
    StyledText {
        visible: !Tailscale.details.peers.length
        text: qsTr("No peers to display")
        color: Colours.palette.m3onSurfaceVariant
    }
    TextButton {
        visible: !root.compact
        text: qsTr("Open Tailscale admin")
        onClicked: Qt.openUrlExternally("https://login.tailscale.com/admin/machines")
    }
}
