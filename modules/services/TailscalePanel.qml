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
            StyledText { Layout.fillWidth: true; text: "Tailscale"; font: Tokens.font.title.medium }
            StyledText { Layout.fillWidth: true; text: Tailscale.summary; color: Colours.palette.m3onSurfaceVariant; elide: Text.ElideRight }
        }
        ServiceActionButton {
            icon: Tailscale.connected ? "link_off" : "link"
            description: Tailscale.busy ? qsTr("Working…") : Tailscale.connected ? qsTr("Disconnect Tailscale") : qsTr("Connect Tailscale")
            enabled: Tailscale.enabled && !Tailscale.busy && !Tailscale.error
            onClicked: Tailscale.toggle()
        }
        ServiceActionButton {
            icon: "refresh"
            description: qsTr("Refresh Tailscale")
            enabled: Tailscale.enabled && !Tailscale.busy
            onClicked: Tailscale.refresh()
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: Tailscale.error || Tailscale.actionError || Tailscale.details.health.join("\n")
        color: Colours.palette.m3error
        wrapMode: Text.Wrap
    }
    InfoRow {
        visible: !!Tailscale.details.ip
        first: true
        last: true
        icon: "computer"
        label: Tailscale.details.name
        subtext: Tailscale.details.ip
        value: root.compact ? "" : Tailscale.details.tailnet
        trailingComponent: CopyAddress { address: Tailscale.details.ip }
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
        delegate: InfoRow {
            id: peer

            required property var modelData
            readonly property string peerStatus: modelData.online ? qsTr("Online") : qsTr("Offline")

            first: true
            last: true
            label: modelData.name
            subtext: modelData.ip + (root.compact ? " · " + peerStatus : "") + (modelData.exitNode ? " · " + qsTr("Exit node") : "")
            value: root.compact ? "" : peerStatus + (modelData.online ? " · " + modelData.connection : "")
            icon: modelData.online ? "devices" : "cloud_off"
            iconColour: modelData.online ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            trailingComponent: RowLayout {
                spacing: Tokens.spacing.extraSmall

                ServiceActionButton {
                    visible: !root.compact && (peer.modelData.exitAvailable || peer.modelData.exitNode)
                    icon: peer.modelData.exitNode ? "logout" : "public"
                    description: peer.modelData.exitNode ? qsTr("Stop using exit node") : qsTr("Use exit node")
                    enabled: Tailscale.connected && !Tailscale.busy && (peer.modelData.online || peer.modelData.exitNode)
                    onClicked: Tailscale.setExitNode(peer.modelData.exitNode ? "" : peer.modelData.ip)
                }
                CopyAddress { address: peer.modelData.ip }
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

    component CopyAddress: ServiceActionButton {
        id: copy

        required property string address
        property bool copied: false

        icon: copied ? "check" : "content_copy"
        description: copied ? qsTr("Copied") : qsTr("Copy IP address")
        enabled: !!address
        onClicked: {
            Quickshell.clipboardText = address;
            copied = true;
            feedback.restart();
        }

        Timer {
            id: feedback
            interval: 1500
            onTriggered: copy.copied = false
        }
    }
}
