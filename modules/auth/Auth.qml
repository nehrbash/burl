pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import qs.services

// One prompt for polkit requests and sudo's SUDO_ASKPASS (bin/burl-askpass).
// Askpass wire format: the client sends one line (the prompt); Burl answers with
// one line (the password) or closes the connection without writing, which is a cancel.
Scope {
    id: root

    readonly property string askpassDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/burl`
    readonly property var flow: agent.flow
    readonly property bool polkitOpen: agent.isActive && flow !== null && !flow.isCompleted
    readonly property bool askpassOpen: askpassConn !== null
    readonly property bool open: polkitOpen || askpassOpen

    readonly property string title: polkitOpen ? flow.message : qsTr("Authentication required")
    readonly property string detail: polkitOpen ? flow.actionId : ""
    readonly property string body: askpassOpen ? askpassPrompt : ""
    readonly property string inputPrompt: polkitOpen ? flow.inputPrompt.replace(/:\s*$/, "") : qsTr("Password")
    readonly property bool echo: polkitOpen && flow.responseVisible
    readonly property bool busy: polkitOpen && !flow.isResponseRequired
    readonly property string error: polkitOpen ? (flow.supplementaryMessage || (flow.failed ? qsTr("Authentication failed. Try again.") : "")) : ""
    readonly property bool errorIsError: !polkitOpen || flow.supplementaryIsError || flow.failed

    property var askpassConn: null
    property string askpassPrompt

    function submit(secret: string): void {
        if (polkitOpen) {
            if (flow.isResponseRequired)
                flow.submit(secret);
        } else if (askpassConn) {
            const conn = askpassConn;
            askpassConn = null;
            conn.write(secret + "\n");
            conn.flush();
            conn.connected = false;
        }
    }

    function cancel(): void {
        if (polkitOpen) {
            flow.cancelAuthenticationRequest();
        } else if (askpassConn) {
            const conn = askpassConn;
            askpassConn = null;
            conn.connected = false;
        }
    }

    function askpassLine(conn: var, line: string): void {
        if (conn.seen)
            return;
        conn.seen = true;
        // One request at a time: a second asker is closed, which reads as a cancel.
        if (open) {
            conn.connected = false;
            return;
        }
        askpassPrompt = line.replace(/[\x00-\x1F\x7F]/g, " ").trim().slice(0, 300);
        askpassConn = conn;
    }

    function askpassGone(conn: var): void {
        if (askpassConn === conn)
            askpassConn = null;
    }

    PolkitAgent {
        id: agent
    }

    Process {
        running: true
        command: ["sh", "-c", `mkdir -p "$1" && chmod 700 "$1"`, "sh", root.askpassDir]
        onExited: code => server.active = code === 0
    }

    SocketServer {
        id: server

        path: `${root.askpassDir}/askpass.sock`

        handler: Socket {
            id: sock

            property bool seen

            parser: SplitParser {
                onRead: line => root.askpassLine(sock, line)
            }
            onConnectedChanged: {
                if (!connected)
                    root.askpassGone(sock);
            }
        }
    }

    LazyLoader {
        active: root.open

        AuthPrompt {
            auth: root
        }
    }
}
