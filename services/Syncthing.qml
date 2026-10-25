pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import "ServiceStatus.js" as Status

Singleton {
    id: root

    readonly property bool enabled: GlobalConfig.services.syncthingEnabled
    readonly property string baseUrl: GlobalConfig.services.syncthingUrl.replace(/\/$/, "")
    readonly property string configPath: GlobalConfig.services.syncthingConfigPath || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/syncthing/config.xml"
    property var folders: []
    property var devices: []
    property string error: ""
    property string actionError: ""
    property bool available: false
    property bool busy: false
    property bool refreshing: false
    property var requests: []
    property int generation: 0
    readonly property string summary: !enabled ? qsTr("Disabled") : error ? qsTr("Unavailable") : !available ? qsTr("Connecting")
        : folders.some(f => f.state === "Error") ? qsTr("Sync errors")
        : folders.some(f => ["Syncing", "Scanning"].includes(f.state)) ? qsTr("Syncing")
        : folders.some(f => f.state === "Out of sync") ? qsTr("Out of sync")
        : folders.some(f => f.state === "Local changes") ? qsTr("Local changes")
        : folders.some(f => f.paused) ? qsTr("Paused") : folders.length ? qsTr("Up to date") : qsTr("No folders")
    readonly property int connectedCount: devices.filter(d => d.connected).length

    function cancel(): void {
        generation++;
        const old = requests;
        requests = [];
        for (const xhr of old) xhr.abort();
        refreshing = false;
        busy = false;
        deadline.stop();
    }

    function reset(): void {
        cancel();
        available = false;
        folders = [];
        devices = [];
        error = "";
        actionError = "";
        if (enabled) Qt.callLater(refresh);
    }

    function request(method, path, body, done): void {
        const key = Status.apiKey(credentials.text());
        if (!Status.localUrl(baseUrl) || !key) {
            done(null, !key ? qsTr("Cannot read an API key from the Syncthing configuration") : qsTr("Use a local HTTP address, such as http://127.0.0.1:8384"));
            return;
        }
        const epoch = generation;
        const xhr = new XMLHttpRequest();
        requests = [...requests, xhr];
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || epoch !== generation) return;
            requests = requests.filter(r => r !== xhr);
            if (!requests.length) deadline.stop();
            if (xhr.status < 200 || xhr.status >= 300) {
                done(null, xhr.status === 401 || xhr.status === 403 ? qsTr("Syncthing rejected the API key") : qsTr("Syncthing request failed (%1)").arg(xhr.status || qsTr("connection unavailable")));
                return;
            }
            let data;
            try { data = xhr.responseText ? JSON.parse(xhr.responseText) : {}; }
            catch (e) { done(null, qsTr("Invalid response from Syncthing")); return; }
            if (method === "GET" && !Status.validResponse(path, data)) {
                done(null, qsTr("Incomplete response from Syncthing"));
                return;
            }
            done(data, "");
        };
        xhr.open(method, baseUrl + "/rest/" + path);
        xhr.setRequestHeader("X-API-Key", key);
        xhr.setRequestHeader("Content-Type", "application/json");
        deadline.restart();
        xhr.send(body === null ? "" : JSON.stringify(body));
    }

    function fail(message): void {
        cancel();
        error = message;
        available = false;
        folders = [];
        devices = [];
    }

    function refresh(): void {
        if (!enabled || refreshing || busy) return;
        refreshing = true;
        request("GET", "system/status", null, (system, problem) => {
            if (problem) { fail(problem); return; }
            request("GET", "config/devices", null, (configs, problem) => {
                if (problem) { fail(problem); return; }
                request("GET", "system/connections", null, (connections, problem) => {
                    if (problem) { fail(problem); return; }
                    const peers = configs.filter(d => d.deviceID !== system.myID).map(d => ({
                        id: d.deviceID, name: d.name || d.deviceID, paused: d.paused === true,
                        connected: connections.connections?.[d.deviceID]?.connected === true,
                        address: connections.connections?.[d.deviceID]?.address || ""
                    }));
                    request("GET", "config/folders", null, (configs, problem) => {
                        if (problem) { fail(problem); return; }
                        const results = [];
                        function next(index) {
                            if (index === configs.length) {
                                root.folders = results;
                                root.devices = peers;
                                root.available = true;
                                root.error = "";
                                root.refreshing = false;
                                return;
                            }
                            const config = configs[index];
                            if (config.paused) {
                                results.push(Status.folder(config, {}));
                                next(index + 1);
                                return;
                            }
                            request("GET", "db/status?folder=" + encodeURIComponent(config.id), null, (status, problem) => {
                                results.push(Status.folder(config, problem ? {error: problem} : status));
                                next(index + 1);
                            });
                        }
                        next(0);
                    });
                });
            });
        });
    }

    function act(method, path, body): void {
        if (!enabled || !available || busy) return;
        cancel();
        busy = true;
        actionError = "";
        request(method, path, body, (data, problem) => {
            busy = false;
            actionError = problem;
            refresh();
        });
    }

    function pauseFolder(folder): void {
        act("PATCH", "config/folders/" + encodeURIComponent(folder.id), {paused: !folder.paused});
    }

    function scan(folder): void {
        act("POST", "db/scan?folder=" + encodeURIComponent(folder.id), null);
    }

    function pauseDevice(device): void {
        act("PATCH", "config/devices/" + encodeURIComponent(device.id), {paused: !device.paused});
    }

    onEnabledChanged: reset()
    onBaseUrlChanged: reset()
    onConfigPathChanged: reset()
    Component.onCompleted: reset()
    Component.onDestruction: cancel()

    FileView {
        id: credentials
        path: root.enabled ? root.configPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.reset()
        onLoadFailed: if (root.enabled) root.fail(qsTr("Cannot read the Syncthing configuration file"))
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.enabled
        onTriggered: root.refresh()
    }

    Timer {
        id: deadline
        interval: 10000
        onTriggered: {
            const wasBusy = root.busy;
            root.fail(qsTr("Syncthing request timed out"));
            if (wasBusy) root.actionError = qsTr("Action timed out; refresh before retrying");
        }
    }
}
