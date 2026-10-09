pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed
    property bool needsStart
    property list<string> startArgs
    property bool needsStop
    property bool needsPause

    // Region mode is user-paced (slurp waits for a drag), so the recorder
    // process only appears once the selection is made. Reconciliation below
    // has to wait that out instead of treating the gap as a failed start.
    readonly property bool regionMode: startArgs.some(a => a.startsWith("-") && a.includes("r"))

    function start(extraArgs = []): void {
        needsStart = true;
        startArgs = extraArgs;
        checkProc.running = true;
    }

    function stop(): void {
        needsStop = true;
        checkProc.running = true;
    }

    function togglePause(): void {
        needsPause = true;
        checkProc.running = true;
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    Process {
        id: checkProc

        running: true
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => { // qmllint disable signal-handler-parameters
            props.running = code === 0;

            if (code === 0) {
                if (root.needsStop) {
                    Quickshell.execDetached(["burl-record"]);
                    props.running = false;
                    props.paused = false;
                } else if (root.needsPause) {
                    Quickshell.execDetached(["burl-record", "-p"]);
                    props.paused = !props.paused;
                }
            } else if (root.needsStart) {
                Quickshell.execDetached(["burl-record", ...root.startArgs]);
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
            }

            root.needsStart = false;
            root.needsStop = false;
            root.needsPause = false;
        }
    }

    // `running` is set optimistically on dispatch, but a start can fail to
    // materialise (failed recorder init, or a cancelled region selection — a
    // normal user action). Poll liveness while we believe it's recording, so
    // a phantom REC doesn't linger; the timer stops itself once cleared.
    Timer {
        running: props.running
        interval: root.regionMode ? 60000 : 5000
        repeat: true
        onTriggered: verifyProc.running = true
    }

    Process {
        id: verifyProc

        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code !== 0) {
                props.running = false;
                props.paused = false;
            }
        }
    }

    Connections {
        function onSecondsChanged(): void {
            if (props.running && !props.paused)
                props.elapsed++;
        }

        target: Time // qmllint disable incompatible-type
    }
}
