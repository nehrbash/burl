pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config
import "ServiceStatus.js" as Status

Singleton {
    id: root

    readonly property bool enabled: GlobalConfig.services.tailscaleEnabled
    property var details: ({state: "Unknown", name: "", ip: "", tailnet: "", health: [], peers: [], authUrl: ""})
    property string error: ""
    property string actionError: ""
    readonly property bool connected: !error && details.state === "Running"
    readonly property bool busy: action.running
    readonly property string summary: !enabled ? qsTr("Disabled") : error ? qsTr("Unavailable") : connected ? qsTr("Connected") : details.state
    readonly property int onlineCount: details.peers.filter(p => p.online).length

    function refresh(): void {
        if (enabled && !poll.running && !busy)
            poll.running = true;
    }

    function run(args: var): void {
        if (!enabled || busy)
            return;
        actionError = "";
        action.exec(["tailscale", ...args]);
    }

    function toggle(): void {
        run(connected ? ["down"] : ["up", "--timeout=15s"]);
    }

    function setExitNode(ip: string): void {
        run(["set", "--exit-node=" + ip]);
    }

    function clearDetails(): void {
        details = {state: "Unknown", name: "", ip: "", tailnet: "", health: [], peers: [], authUrl: ""};
    }

    onEnabledChanged: {
        if (enabled) refresh();
        else { poll.running = false; error = ""; actionError = ""; clearDetails(); }
    }
    Component.onCompleted: refresh()

    Timer {
        interval: 15000
        running: root.enabled
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 10000
        running: poll.running
        onTriggered: { poll.running = false; root.error = qsTr("Tailscale status timed out"); root.clearDetails(); }
    }

    Timer {
        interval: 20000
        running: action.running
        onTriggered: { action.running = false; root.actionError = qsTr("Tailscale action timed out"); root.refresh(); }
    }

    Process {
        id: poll
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector { id: output }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (!root.enabled) return;
            try {
                if (code !== 0) throw new Error("unavailable");
                root.details = Status.tailscale(JSON.parse(output.text));
                root.error = "";
            } catch (e) {
                root.error = qsTr("Cannot read Tailscale status. Check that tailscaled is running.");
                root.clearDetails();
            }
        }
    }

    Process {
        id: action
        stdout: StdioCollector {}
        stderr: StdioCollector { id: actionOutput }
        onExited: (code, status) => {
            if (code !== 0) root.actionError = actionOutput.text.trim() || qsTr("Tailscale action failed");
            root.refresh();
        }
    }
}
