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

    title: "Syncthing"

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        ToggleRow {
            first: true
            last: true
            text: qsTr("Show Syncthing in the bar")
            subtext: qsTr("Monitor the local service")
            checked: GlobalConfig.services.syncthingEnabled
            onToggled: GlobalConfig.services.syncthingEnabled = checked
        }
        StyledTextField {
            Layout.fillWidth: true
            text: GlobalConfig.services.syncthingUrl
            placeholderText: qsTr("Local API address")
            supportingText: qsTr("Local HTTP endpoint; default http://127.0.0.1:8384")
            onEditingFinished: GlobalConfig.services.syncthingUrl = text.trim()
        }
        StyledTextField {
            Layout.fillWidth: true
            text: GlobalConfig.services.syncthingConfigPath
            placeholderText: Syncthing.configPath
            supportingText: qsTr("Configuration file containing the API key; blank uses the default path")
            onEditingFinished: GlobalConfig.services.syncthingConfigPath = text.trim()
        }
        SyncthingPanel { Layout.fillWidth: true }
    }
}
