pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var entries: []
    property var modes: []
    property string catalogError
    property string modeError
    property string applyError
    readonly property string error: applyError || catalogError || modeError
    readonly property bool busy: apply.running || catalog.running || availableModes.running

    function refresh(): void {
        catalog.running = true;
        availableModes.running = true;
    }

    function select(name: string, flavour: string): void {
        if (busy)
            return;
        applyError = "";
        apply.command = ["burl", "scheme", "set", "--name", name, "--flavour", flavour];
        apply.running = true;
    }

    function setMode(mode: string): void {
        if (busy || !["light", "dark"].includes(mode))
            return;
        applyError = "";
        apply.command = ["burl", "scheme", "set", "--mode", mode];
        apply.running = true;
    }

    Connections {
        target: Colours
        function onSchemeChanged(): void { availableModes.running = true; }
        function onFlavourChanged(): void { availableModes.running = true; }
    }

    Process {
        id: catalog
        command: ["burl", "scheme", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const schemes = JSON.parse(text);
                    const entries = [];
                    const names = Object.keys(schemes).sort((a, b) => {
                        if (a === b) return 0;
                        if (a === "nocturne") return -1;
                        if (b === "nocturne") return 1;
                        return a.localeCompare(b);
                    });
                    for (const name of names) {
                        for (const flavour of Object.keys(schemes[name]).sort())
                            entries.push({ name, flavour, colours: schemes[name][flavour] });
                    }
                    root.entries = entries;
                    root.catalogError = "";
                } catch (e) {
                    root.catalogError = qsTr("Could not load colour schemes.");
                }
            }
        }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            Colours.reloadScheme();
            if (code !== 0)
                root.catalogError = qsTr("Could not load colour schemes: %1").arg(stderr.text.trim());
        }
    }

    Process {
        id: availableModes
        command: ["burl", "scheme", "list", "--modes"]
        stderr: StdioCollector {}
        onExited: (code, status) => {
            root.modeError = code === 0 ? "" : qsTr("Could not load appearances: %1").arg(stderr.text.trim());
        }
        stdout: StdioCollector {
            onStreamFinished: root.modes = text.trim().split("\n").filter(mode => ["light", "dark"].includes(mode))
        }
    }

    Process {
        id: apply
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (code !== 0) {
                root.applyError = qsTr("Could not apply colour scheme: %1").arg(stderr.text.trim());
                Quickshell.execDetached(["notify-send", "-a", "burl", qsTr("Colour scheme error"), stderr.text.trim()]);
            }
            Colours.reloadScheme();
            root.refresh();
        }
    }
}
