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

PageBase {
    id: root

    title: "Tailscale"

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        ToggleRow {
            first: true
            last: true
            text: qsTr("Show Tailscale in the bar")
            subtext: qsTr("Monitor the local service")
            checked: GlobalConfig.services.tailscaleEnabled
            onToggled: GlobalConfig.services.tailscaleEnabled = checked
        }
        TailscalePanel { Layout.fillWidth: true }
    }
}
