pragma Singleton

import ".."
import QtQuick
import Quickshell
import Burl.Config
import Burl.Services
import qs.services
import qs.utils

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(GlobalConfig.launcher.actionPrefix.length);
    }

    list: variants.instances
    useFuzzy: GlobalConfig.launcher.useFuzzy.actions ?? true

    Variants {
        id: variants

        model: GlobalConfig.launcher.actions.filter(a => (a.enabled ?? true) && (GlobalConfig.launcher.enableDangerousActions || !(a.dangerous ?? false)))

        Action {}
    }

    component Action: QtObject {
        required property var modelData
        readonly property string name: modelData.name ?? qsTr("Unnamed")
        readonly property string desc: modelData.description ?? qsTr("No description")
        readonly property string icon: modelData.icon ?? "help_outline"
        readonly property list<string> command: modelData.command ?? []

        function activate(searchField: var, visibilities: var): void {
            if (command.length === 0)
                return;
            if (command[0] === "autocomplete" && command.length > 1) {
                searchField.text = `${GlobalConfig.launcher.actionPrefix}${command[1]} `;
            } else if (command[0] === "setText" && command.length > 1) {
                searchField.text = command[1];
            } else if (command[0] === "setMode" && command.length > 1) {
                visibilities.launcher = false;
                Colours.setMode(command[1]);
            } else {
                visibilities.launcher = false;
                if (!IdleInhibitor.execSessionAction(command))
                    Quickshell.execDetached(command);
            }
        }
    }
}
