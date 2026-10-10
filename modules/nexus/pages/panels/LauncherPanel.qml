pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Launcher")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Enabled")
            checked: Config.launcher.enabled
            onToggled: GlobalConfig.launcher.enabled = checked
        }

        SectionHeader {
            text: qsTr("Display")
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Max wallpapers")
            value: Config.launcher.maxWallpapers
            from: 1
            to: 30
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxWallpapers = v
        }

        SectionHeader {
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Vim keybinds")
            subtext: qsTr("Navigate results with Ctrl+hjkl")
            checked: GlobalConfig.launcher.vimKeybinds
            onToggled: GlobalConfig.launcher.vimKeybinds = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Enable dangerous actions")
            subtext: qsTr("Allow actions that shut down or log out")
            checked: GlobalConfig.launcher.enableDangerousActions
            onToggled: GlobalConfig.launcher.enableDangerousActions = checked
        }

        SectionHeader {
            text: qsTr("Fuzzy search")
        }

        ToggleRow {
            first: true
            last: true
            text: qsTr("Actions")
            checked: GlobalConfig.launcher.useFuzzy.actions
            onToggled: GlobalConfig.launcher.useFuzzy.actions = checked
        }
    }
}
