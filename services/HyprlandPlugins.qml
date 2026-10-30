pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Burl.Config
import "HyprlandPluginPolicy.js" as Policy

Singleton {
    id: root

    property var installed: []
    property var loaded: []
    readonly property var choices: GlobalConfig.hyprlandPlugins
    readonly property bool performance: PowerProfiles.profile === PowerProfile.Performance
    readonly property var plugins: Policy.entries(installed, loaded, choices, performance)
    property bool ready: false
    property bool busy: false
    property string error: ""
    property string operation: ""
    property var attempted: ({})
    property bool refreshPending: false
    property bool changed: false
    property string savedLoaderText: ""
    property string pendingLoaderText: ""

    function setChoice(plugin: var, key: string, value: bool): void {
        if (busy || !ready || !["enabled", "disableInPerformance"].includes(key))
            return;
        const updated = Object.assign({ enabled: plugin.enabled }, choices[plugin.id] || {});
        updated[key] = value;
        const next = Object.assign({}, choices);
        next[plugin.id] = updated;
        GlobalConfig.hyprlandPlugins = next;
    }

    function refresh(): void {
        if (busy) {
            refreshPending = true;
            return;
        }
        busy = true;
        error = "";
        attempted = {};
        changed = false;
        operation = "save";
        pendingLoaderText = Policy.loaderSettings(choices, performance);
        if (pendingLoaderText === savedLoaderText)
            readLoaded();
        else
            loaderSettings.setText(pendingLoaderText);
    }

    function launch(kind: string, command: list<string>): void {
        operation = kind;
        process.command = command;
        process.running = true;
    }

    function readLoaded(): void {
        launch("read", ["timeout", "5", "hyprctl", "-j", "plugin", "list"]);
    }

    function finish(): void {
        busy = false;
        operation = "";
        if (refreshPending) {
            refreshPending = false;
            Qt.callLater(refresh);
        }
    }

    function reconcile(): void {
        const next = plugins.find(plugin => plugin.loaded !== plugin.desired && !attempted[plugin.id]);
        if (next) {
            attempted[next.id] = true;
            changed = true;
            launch("write", ["timeout", "5", "hyprctl", "plugin", next.desired ? "load" : "unload", next.path]);
        } else if (plugins.some(plugin => plugin.loaded !== plugin.desired)) {
            error = error || qsTr("Hyprland did not accept the plugin settings.");
            finish();
        } else if (changed) {
            changed = false;
            // Reload applies the user's configuration for newly loaded plugins.
            launch("reload", ["timeout", "5", "hyprctl", "reload"]);
        } else {
            finish();
        }
    }

    function completed(code: int, output: string): void {
        if (operation === "write") {
            if (code !== 0)
                error = output.trim() || qsTr("Could not change a Hyprland plugin.");
            Qt.callLater(readLoaded);
        } else if (operation === "reload") {
            if (code !== 0)
                error = qsTr("Plugins changed, but Hyprland configuration could not be reloaded.");
            finish();
        } else if (operation === "read") {
            try {
                if (code !== 0)
                    throw new Error(output.trim() || qsTr("Could not read loaded plugins."));
                const result = JSON.parse(output);
                if (!Array.isArray(result) || !result.every(plugin => typeof plugin.name === "string"))
                    throw new Error(qsTr("Invalid plugin list from Hyprland."));
                loaded = result;
                ready = true;
                Qt.callLater(reconcile);
            } catch (failure) {
                ready = false;
                error = String(failure);
                finish();
            }
        }
    }

    onChoicesChanged: Qt.callLater(refresh)
    onPerformanceChanged: Qt.callLater(refresh)

    FileView {
        path: Quickshell.env("BURL_HYPRLAND_PLUGIN_MANIFEST") || Quickshell.env("HOME") + "/.config/hypr-plugins.lua"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.installed = Policy.manifest(text());
            root.refresh();
        }
        onLoadFailed: {
            root.error = qsTr("No installed Hyprland plugin manifest was found.");
            root.ready = false;
        }
    }

    FileView {
        id: loaderSettings
        path: Quickshell.env("HOME") + "/.config/hypr/plugins-generated.lua"
        preload: false
        onSaved: {
            root.savedLoaderText = root.pendingLoaderText;
            root.readLoaded();
        }
        onSaveFailed: {
            root.error = qsTr("Could not save plugin startup settings.");
            root.finish();
        }
    }

    Process {
        id: process
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: code => root.completed(code, code === 0 ? output.text : output.text + errors.text)
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void {
            if (root.operation !== "reload")
                root.refresh();
        }
    }
}
