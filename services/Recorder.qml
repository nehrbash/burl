pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property alias state: props.state
    property bool statusPending: false
    property bool watcherReady: false
    readonly property bool running: state !== "idle"
    readonly property bool paused: state === "paused"
    readonly property bool capturing: state === "recording" || paused
    readonly property alias elapsed: props.elapsed

    function start(extraArgs = []): void {
        if (!running)
            Quickshell.execDetached(["burl-record", "--start", ...extraArgs]);
    }

    function stop(): void {
        Quickshell.execDetached(["burl-record", "--stop"]);
    }

    function togglePause(): void {
        if (capturing)
            Quickshell.execDetached(["burl-record", "--pause"]);
    }

    function applyState(text: string): void {
        try {
            const next = JSON.parse(text).state;
            if (!["idle", "selecting", "starting", "recording", "paused", "cancelling", "saving"].includes(next))
                return;
            if (next !== "idle" && root.state === "idle")
                props.elapsed = 0;
            props.state = next;
        } catch (e) {
            console.warn("Recorder: invalid state:", e);
        }
    }

    function refreshStatus(): void {
        if (statusProc.running)
            statusPending = true;
        else
            statusProc.running = true;
    }

    PersistentProperties {
        id: props

        property string state: "idle"
        property real elapsed: 0
        reloadableId: "recorder"
    }

    FileView {
        id: stateView

        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/burl/recording.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.refreshStatus()
    }

    Process {
        id: statusProc

        running: true
        command: ["burl-record", "--status"]
        onExited: {
            if (!root.watcherReady) {
                root.watcherReady = true;
                stateView.reload();
            }
            if (root.statusPending) {
                root.statusPending = false;
                Qt.callLater(root.refreshStatus);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: root.applyState(text)
        }
    }

    Connections {
        function onSecondsChanged(): void {
            if (root.state === "recording")
                props.elapsed++;
        }

        target: Time // qmllint disable incompatible-type
    }
}
