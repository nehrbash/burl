pragma Singleton

import ".."
import "CommandArguments.js" as CommandArguments
import "ActionSearch.js" as ActionSearch
import QtQuick
import Quickshell
import Burl
import Burl.Config
import Burl.Services
import qs.services

Singleton {
    id: root

    function query(search: string): var {
        const prefix = GlobalConfig.launcher.actionPrefix;
        const text = search.startsWith(prefix) ? search.slice(prefix.length) : search;
        return ActionSearch.query(variants.instances, text, GlobalConfig.launcher.useFuzzy.actions ?? true);
    }

    Variants {
        id: variants

        model: GlobalConfig.launcher.actions.filter(a => (a.enabled ?? true) && (GlobalConfig.launcher.enableDangerousActions || !(a.dangerous ?? false)))

        Action {}
    }

    component Action: QtObject {
        required property var modelData
        readonly property string name: modelData.name ?? qsTr("Unnamed")
        readonly property string desc: modelData.description ?? qsTr("No description")
        readonly property string keyword: CommandArguments.keywordFor(modelData)
        readonly property bool acceptArgs: modelData.acceptArgs ?? false
        readonly property string icon: modelData.icon ?? "help_outline"
        readonly property list<string> command: modelData.command ?? []

        function activate(searchField: var, visibilities: var): void {
            const prefix = GlobalConfig.launcher.actionPrefix;
            const text = searchField.text.startsWith(prefix) ? searchField.text.slice(prefix.length) : searchField.text;
            const invocation = CommandArguments.invocation(modelData, text);
            if (invocation.error) {
                Toaster.toast(qsTr("Cannot run command"), invocation.error, "error");
                return;
            }
            const argv = invocation.command;
            try {
                if (argv[0] === "autocomplete" && argv.length > 1) {
                    searchField.text = `${prefix}${argv[1]} `;
                } else if (argv[0] === "setText" && argv.length > 1) {
                    searchField.text = argv[1];
                } else if (argv[0] === "setMode" && argv.length > 1) {
                    Colours.setMode(argv[1]);
                    visibilities.launcher = false;
                    visibilities.dashboard = false;
                } else {
                    if (!IdleInhibitor.execSessionAction(argv))
                        Quickshell.execDetached(argv);
                    visibilities.launcher = false;
                    visibilities.dashboard = false;
                }
            } catch (error) {
                Toaster.toast(qsTr("Cannot run command"), String(error), "error");
            }
        }
    }
}
