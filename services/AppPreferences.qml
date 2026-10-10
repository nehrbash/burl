pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl
import Burl.Config
import "AppCommands.js" as Commands

Singleton {
    id: root

    readonly property var entries: DesktopEntries.applications.values

    function label(kind: string): string {
        const preferences = GlobalConfig.general.apps;
        const id = preferences[kind + "Desktop"];
        if (id) return entries.find(entry => entry.id === id)?.name ?? qsTr("Unavailable: %1").arg(id);
        const command = preferences[kind];
        return command.length ? (Commands.legacyEntry(command, entries)?.name ?? command.join(" ")) : qsTr("Desktop default");
    }

    function select(kind: string, entry: var): void {
        GlobalConfig.general.apps[kind + "Desktop"] = entry?.id ?? "";
        GlobalConfig.general.apps[kind] = [];
    }

    function supportsTerminal(entry: var): bool {
        return Commands.terminalFlag(entry.command) !== null;
    }

    function open(kind: string, path: string): void {
        try {
            const preferences = GlobalConfig.general.apps;
            const command = Commands.fileCommand(preferences[kind + "Desktop"], preferences[kind], entries, path);
            if (command[0] === "gtk-launch") {
                const process = desktopLauncher.createObject(root, {command});
                process.running = true;
            } else Quickshell.execDetached(command);
        } catch (error) {
            Toaster.toast(qsTr("Cannot open application"), String(error), "error");
        }
    }

    function launchTerminal(child: var, workingDirectory: string): void {
        try {
            const preferences = GlobalConfig.general.apps;
            const launch = Commands.resolve(preferences.terminalDesktop, preferences.terminal, entries, "foot");
            launch.command = Commands.terminalCommand(launch.command, child);
            launch.workingDirectory = workingDirectory;
            Quickshell.execDetached({command: launch.command, workingDirectory: launch.workingDirectory});
        } catch (error) {
            Toaster.toast(qsTr("Cannot open terminal"), String(error), "error");
        }
    }

    function migrate(): void {
        const preferences = GlobalConfig.general.apps;
        for (const kind of ["terminal", "explorer", "playback"]) {
            if (preferences[kind + "Desktop"] || !preferences[kind][0]?.startsWith("/gnu/store/")) continue;
            const entry = Commands.legacyEntry(preferences[kind], entries);
            if (entry) select(kind, entry);
        }
    }


    Component {
        id: desktopLauncher

        Process {
            id: process
            property bool didStart: false
            onStarted: didStart = true
            stderr: StdioCollector { id: errorOutput }
            onExited: (code, status) => {
                if (code !== 0 || status !== 0)
                    Toaster.toast(qsTr("Cannot open application"), errorOutput.text.trim() || qsTr("Desktop launcher failed"), "error");
                destroy();
            }
            onRunningChanged: {
                if (!running && !didStart) {
                    Toaster.toast(qsTr("Cannot open application"), qsTr("Desktop launcher could not start"), "error");
                    destroy();
                }
            }
        }
    }

    Component.onCompleted: migrate()
    onEntriesChanged: migrate()
}
