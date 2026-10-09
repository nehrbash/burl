pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// cliphist history, read on demand.
//
// The list is only refreshed while something is looking at it (refCount > 0):
// `cliphist list` forks and reads the whole bolt DB, so a standing poll would
// be a per-second fork for a panel nobody has open.
Singleton {
    id: root

    // [{ id, preview, binary }] newest first, as cliphist orders them.
    property list<var> entries: []
    property int refCount
    property bool loading

    readonly property int maxEntries: 200

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function copy(id: string): void {
        if (!id)
            return;
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy', "sh", id]);
    }

    function remove(id: string): void {
        if (!id)
            return;
        Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | cliphist delete', "sh", id]);
        // The delete is detached, so the list cannot be re-read immediately;
        // drop the row here and let the next refresh confirm it.
        root.entries = root.entries.filter(e => e.id !== id);
    }

    function wipe(): void {
        Quickshell.execDetached(["cliphist", "wipe"]);
        root.entries = [];
    }

    onRefCountChanged: {
        if (refCount > 0)
            refresh();
    }

    Process {
        id: listProc

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line)
                        continue;
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const preview = line.slice(tab + 1);
                    out.push({
                        id: line.slice(0, tab),
                        preview: preview,
                        // cliphist renders non-text entries as a bracketed
                        // placeholder; they cannot be previewed as a label.
                        binary: preview.startsWith("[[ binary data")
                    });
                    if (out.length >= root.maxEntries)
                        break;
                }
                root.entries = out;
            }
        }

        onRunningChanged: root.loading = running
        onExited: code => {
            if (code !== 0)
                root.entries = [];
        }
    }

    IpcHandler {
        function reload(): void {
            root.refresh();
        }

        function wipeAll(): void {
            root.wipe();
        }

        target: "clipboard"
    }
}
