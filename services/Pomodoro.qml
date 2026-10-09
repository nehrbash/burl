pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl

Singleton {
    id: root

    property int workMinutes: 25
    property int breakMinutes: 5

    // A session exists (running or paused); no session = idle
    property bool active: false
    property bool running: false
    property bool onBreak: false
    property int sessionsCompleted: 0
    property int remaining: workMinutes * 60

    readonly property bool paused: active && !running
    readonly property int total: (onBreak ? breakMinutes : workMinutes) * 60
    readonly property real progress: active ? 1 - remaining / total : 0
    readonly property string remainingStr: `${Math.floor(remaining / 60)}:${(remaining % 60).toString().padStart(2, "0")}`

    function start(): void {
        if (!active) {
            active = true;
            onBreak = false;
            remaining = workMinutes * 60;
        }
        running = true;
    }

    function pause(): void {
        running = false;
    }

    function toggle(): void {
        if (running)
            pause();
        else
            start();
    }

    function reset(): void {
        active = false;
        running = false;
        onBreak = false;
        sessionsCompleted = 0;
        remaining = workMinutes * 60;
    }

    function advance(): void {
        if (onBreak) {
            onBreak = false;
            remaining = workMinutes * 60;
            Toaster.toast(qsTr("Break over"), qsTr("Back to focus — a new seed is planted"), "potted_plant");
        } else {
            sessionsCompleted++;
            onBreak = true;
            remaining = breakMinutes * 60;
            Toaster.toast(qsTr("Focus complete"), qsTr("Take a %1 minute break").arg(breakMinutes), "local_cafe");
        }
    }

    Timer {
        running: root.running
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.remaining > 1)
                root.remaining--;
            else
                root.advance();
        }
    }

    IpcHandler {
        target: "pomodoro"

        function start(): void {
            root.start();
        }

        function stop(): void {
            root.reset();
        }

        function toggle(): void {
            root.toggle();
        }

        function reset(): void {
            root.reset();
        }

        function isRunning(): bool {
            return root.running;
        }

        function status(): string {
            if (!root.active)
                return "idle";
            return `${root.onBreak ? "break" : "focus"} ${root.paused ? "paused " : ""}${root.remainingStr}`;
        }
    }
}
