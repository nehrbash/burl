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

    SyncthingPanel {
        Layout.fillWidth: true
        compact: true
    }
    TextButton {
        text: qsTr("Syncthing settings")
        onClicked: root.popouts.detachRequested("syncthing")
    }
}
