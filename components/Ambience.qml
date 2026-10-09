pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Master switch for every ambient (always-running, non-reactive) animation in
// the shell. Deliberately imports NO qs.services — it must be safe to use from
// components/ without an import cycle, exactly like Woodland.qml. Callers that
// also want to stop during games AND in `!GameMode.enabled` at the call site.
//
//   BURL_NO_AMBIENT=1   env kill switch (applies at shell start)
//   qs -c qs ipc call ambience off | on | toggle | status
//
// Idle cost: zero — four booleans and one IPC registration, nothing ticks.
Singleton {
    id: root

    property bool master: Quickshell.env("BURL_NO_AMBIENT") !== "1"
    // Per-family switches; break the binding to master to override one family.
    property bool leaves: master
    property bool sway: master
    property bool grow: master

    IpcHandler {
        function on(): string {
            root.master = true;
            return "ambient motion on";
        }

        function off(): string {
            root.master = false;
            return "ambient motion off";
        }

        function toggle(): string {
            root.master = !root.master;
            return root.master ? "ambient motion on" : "ambient motion off";
        }

        function status(): string {
            return `master=${root.master} leaves=${root.leaves} sway=${root.sway} grow=${root.grow}`;
        }

        target: "ambience"
    }
}
