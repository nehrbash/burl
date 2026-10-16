pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Burl.Config
import qs.modules.nexus.common
import qs.components
import qs.components.controls
import qs.modules.launcher.services
import "../../../launcher/SearchQuery.js" as SearchQuery
import "../../../launcher/services/CommandArguments.js" as CommandArguments

PageBase {
    id: root

    title: qsTr("Launcher")
    isSubPage: true

    readonly property var sourceLabels: ({
        apps: qsTr("Applications"), files: qsTr("Files"), roam: qsTr("Notes"),
        recents: qsTr("Recent files"), bookmarks: qsTr("Bookmarks"), wallpaper: qsTr("Wallpapers"),
        web: qsTr("All browser sources"), webbm: qsTr("Browser bookmarks"), webfolder: qsTr("Browser folders"),
        webhist: qsTr("Browser history"), tabs: qsTr("Browser tabs"), spotify: qsTr("All Spotify sources"),
        playlists: qsTr("Spotify playlists"), tracks: qsTr("Spotify tracks"), clients: qsTr("Windows"),
        monitors: qsTr("Monitors"), workspaces: qsTr("Workspaces"), category: qsTr("Application categories"),
        projects: qsTr("Projects"), mail: qsTr("Mail"), cal: qsTr("Calendar"), clip: qsTr("Clipboard"), emoji: qsTr("Emoji")
    })
    readonly property var sourceKeywords: SearchQuery.sourceKeywords()
    readonly property var appCategories: {
        const categories = new Set();
        for (const app of Apps.list ?? [])
            for (const category of SearchQuery.categoriesFor(app.entry ?? app))
                categories.add(category.toLowerCase());
        for (const preference of GlobalConfig.launcher.onlyShowWhenFiltered)
            if (preference.startsWith("category:")) categories.add(preference.slice(9));
        return Array.from(categories).sort();
    }

    function setFilteredOnly(key: string, enabled: bool): void {
        const preferences = Array.from(GlobalConfig.launcher.onlyShowWhenFiltered);
        GlobalConfig.launcher.onlyShowWhenFiltered = enabled
            ? Array.from(new Set(preferences.concat([key])))
            : preferences.filter(preference => preference !== key);
    }

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

        SectionHeader {
            text: qsTr("Only show when filtered")
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Hide these sources from general search and the background graph. Select their filter to show them.")
            wrapMode: Text.Wrap
            font: Tokens.font.body.small
        }

        Repeater {
            model: root.sourceKeywords

            ToggleRow {
                required property string modelData
                required property int index
                objectName: "sourceVisibility_" + modelData
                first: index === 0
                last: index === root.sourceKeywords.length - 1
                text: root.sourceLabels[modelData] ?? modelData
                subtext: GlobalConfig.launcher.actionPrefix + modelData
                checked: GlobalConfig.launcher.onlyShowWhenFiltered.includes(modelData)
                onToggled: root.setFilteredOnly(modelData, checked)
            }
        }

        SectionHeader {
            text: qsTr("Application categories")
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Hide applications in these categories until you select the category or type its filter, such as %1games. Category nodes stay available to select.").arg(GlobalConfig.launcher.actionPrefix)
            wrapMode: Text.Wrap
            font: Tokens.font.body.small
        }

        Repeater {
            model: root.appCategories

            ToggleRow {
                required property string modelData
                required property int index
                objectName: "categoryVisibility_" + modelData
                first: index === 0
                last: index === root.appCategories.length - 1
                text: modelData === "game" ? qsTr("Games") : modelData.charAt(0).toUpperCase() + modelData.slice(1)
                subtext: GlobalConfig.launcher.actionPrefix + SearchQuery.categoryKeyword(modelData)
                checked: GlobalConfig.launcher.onlyShowWhenFiltered.includes("category:" + modelData)
                onToggled: root.setFilteredOnly("category:" + modelData, checked)
            }
        }

        SectionHeader {
            text: qsTr("Commands")
        }

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Run named commands from the launcher. Changes are saved in your Burl settings.")
            wrapMode: Text.Wrap
            font: Tokens.font.body.small
        }

        CommandEditor {
            id: commandEditor
            objectName: "commandEditor"
            Layout.fillWidth: true
        }

        IconTextButton {
            objectName: "commandAdd"
            visible: !commandEditor.editing
            icon: "add"
            text: qsTr("Add command")
            onClicked: commandEditor.begin(-1)
        }

        Repeater {
            model: commandEditor.editing ? [] : GlobalConfig.launcher.actions

            NavRow {
                required property var modelData
                required property int index
                first: index === 0
                last: index === GlobalConfig.launcher.actions.length - 1
                label: modelData.name ?? qsTr("Unnamed command")
                icon: modelData.icon ?? "terminal"
                status: GlobalConfig.launcher.actionPrefix + CommandArguments.keywordFor(modelData)
                    + ((modelData.enabled ?? true) ? "" : qsTr(" · disabled"))
                    + (modelData.description ? " · " + modelData.description : "")
                onClicked: commandEditor.begin(index)
            }
        }
    }
}
