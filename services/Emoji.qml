pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Emoji search for the launcher's `>emoji` scope.
//
// The table is ~12k lines, so it is parsed once on first use and never turned
// into graph nodes wholesale — `matches` holds only what the current query
// selects, capped, and GraphView builds nodes from that.
Singleton {
    id: root

    // [{ glyph, keywords }]
    property var entries: []
    property bool loaded

    property string query
    property var matches: []

    readonly property int maxMatches: 40

    function ensureLoaded(): void {
        if (!root.loaded && !table.loading)
            table.reload();
    }

    function search(q: string): void {
        root.query = q;
        root.ensureLoaded();
        root.rescore();
    }

    function rescore(): void {
        const q = (root.query ?? "").trim().toLowerCase();
        if (!root.loaded) {
            root.matches = [];
            return;
        }
        if (!q) {
            root.matches = root.entries.slice(0, root.maxMatches);
            return;
        }

        // Word-prefix hits first, then any substring: typing "cat" should reach
        // the cat before "certificate".
        const prefix = [];
        const rest = [];
        for (const e of root.entries) {
            const i = e.keywords.indexOf(q);
            if (i < 0)
                continue;
            if (i === 0 || e.keywords[i - 1] === " ")
                prefix.push(e);
            else
                rest.push(e);
            if (prefix.length >= root.maxMatches)
                break;
        }
        root.matches = prefix.concat(rest).slice(0, root.maxMatches);
    }

    function copy(glyph: string): void {
        if (glyph)
            Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "sh", glyph]);
    }

    FileView {
        id: table

        path: Quickshell.shellPath("assets/data/emojis.txt")
        printErrors: false

        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const sp = line.indexOf(" ");
                if (sp <= 0)
                    continue;
                out.push({
                    glyph: line.slice(0, sp),
                    keywords: line.slice(sp + 1).toLowerCase()
                });
            }
            root.entries = out;
            root.loaded = true;
            root.rescore();
        }
        onLoadFailed: {
            root.entries = [];
            root.loaded = true;
        }
    }
}
