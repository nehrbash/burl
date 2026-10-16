pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import qs.services
import "MouseSettingsPolicy.js" as Policy

Singleton {
    id: root

    readonly property bool accelerationEnabled: actual.accel_profile === "adaptive"
    readonly property string accelerationProfile: actual.accel_profile ?? ""
    readonly property real sensitivity: actual.sensitivity ?? 0
    readonly property bool naturalScroll: actual.natural_scroll ?? false
    readonly property bool leftHanded: actual.left_handed ?? false
    property bool ready: false
    property bool busy: false
    property string error: ""
    property var actual: ({})
    property var snapshot: ({})
    property var patch: ({})
    property bool saveChoice: false
    property bool refreshPending: false
    property bool reapplyPending: false
    property bool writeFailed: false
    property bool timedOut: false
    property int index: 0
    property string operation: ""

    function launch(command: list<string>): void {
        timedOut = false;
        process.command = command;
        process.running = true;
        deadline.restart();
    }

    function readNext(): void {
        operation = "read";
        launch(["hyprctl", "-j", "getoption", "input:" + Policy.keys[index]]);
    }

    function begin(values: var, save: bool): void {
        busy = true;
        error = "";
        patch = values;
        saveChoice = save;
        writeFailed = false;
        snapshot = {};
        index = 0;
        if (Object.keys(values).length) {
            operation = "write";
            launch(["hyprctl", "eval", Policy.command(values)]);
        } else {
            readNext();
        }
    }

    function refresh(reapply: bool): void {
        if (busy) {
            refreshPending = true;
            reapplyPending = reapplyPending || reapply;
            return;
        }
        begin(reapply ? Policy.overrides(GlobalConfig.mouse) : {}, false);
    }

    function setValue(key: string, value: var): void {
        if (!ready || busy || !Policy.valid(key, value))
            return;
        const values = {};
        values[key] = value;
        begin(values, true);
    }

    function toggleAcceleration(): void {
        setValue("accel_profile", accelerationEnabled ? "flat" : "adaptive");
    }

    function finish(): void {
        busy = false;
        operation = "";
        if (refreshPending) {
            const reapply = reapplyPending;
            refreshPending = false;
            reapplyPending = false;
            Qt.callLater(() => root.refresh(reapply));
        }
    }

    function completed(success: bool, text: string): void {
        if (operation === "write") {
            writeFailed = !success;
            if (!success)
                error = qsTr("Could not apply mouse settings.");
            Qt.callLater(readNext);
            return;
        }
        if (!success) {
            ready = false;
            error = qsTr("Could not read mouse settings.");
            finish();
            return;
        }
        try {
            snapshot[Policy.keys[index]] = Policy.read(Policy.keys[index], text);
        } catch (failure) {
            ready = false;
            error = qsTr("Could not read mouse settings.");
            finish();
            return;
        }
        index++;
        if (index < Policy.keys.length) {
            Qt.callLater(readNext);
            return;
        }
        actual = snapshot;
        ready = true;
        if (!Policy.matches(actual, patch)) {
            error = qsTr("The compositor did not accept the mouse settings.");
        } else if (saveChoice && !writeFailed) {
            GlobalConfig.mouse = Object.assign({}, Policy.overrides(GlobalConfig.mouse), patch);
        }
        finish();
    }

    Component.onCompleted: refresh(true)

    Process {
        id: process
        stdout: StdioCollector { id: output }
        onExited: (exitCode, exitStatus) => {
            deadline.stop();
            root.completed(exitCode === 0 && exitStatus === 0 && !root.timedOut, output.text);
        }
    }

    Timer {
        id: deadline
        interval: 3000
        onTriggered: {
            root.timedOut = true;
            if (process.running)
                process.signal(9);
            else
                root.completed(false, "");
        }
    }

    Connections {
        target: Hypr
        function onConfigReloaded(): void { root.refresh(true); }
    }

    Connections {
        target: GlobalConfig
        function onLoaded(): void { root.refresh(true); }
    }
}
