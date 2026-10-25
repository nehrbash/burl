pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Burl.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

import qs.modules.services

ColumnLayout {
    id: root

    required property PopoutState popouts

    width: 380
    spacing: Tokens.spacing.small

    TailscalePanel {
        Layout.fillWidth: true
        compact: true
    }
    TextButton {
        text: qsTr("Tailscale settings")
        onClicked: root.popouts.detachRequested("tailscale")
    }
}
