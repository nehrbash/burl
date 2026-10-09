pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Burl.Config

// Guix state for the Guix settings page (modules/nexus/pages/GuixPage.qml).
//
// Deliberately no backend daemon: `guix describe -f json' is 0.05s and the
// full channel+upstream check (scripts/guix-channel-status) is 5.1s — faster
// than an earlier resident-Guile-over-socket version, which existed only to
// reuse guix-daemon's worker protocol; Quickshell's Process already gives
// merged output and exit codes for free.
//
// The daemon socket genuinely cannot answer most of this anyway: it knows store
// paths, builds and GC, and nothing about channels, packages or profiles.
Singleton {
    id: root

    // --- channels ---------------------------------------------------------
    // Rows: { name, url, branch, local, upstream, behind, current }.
    // `upstream'/`behind'/`current' are null until an upstream check has run,
    // which is why the page can say "not checked" rather than implying current.
    property var channels: []
    property bool channelsLoading: false
    property bool upstreamKnown: false
    readonly property int behindTotal: root.channels.reduce((n, c) => n + (c.behind ?? 0), 0)

    // --- running an action ------------------------------------------------
    // The guix.actions entry in flight, or null. One at a time: they all
    // mutate the same profiles.
    property var runningAction: null
    property string phase: ""
    property var logLines: []
    property int lastExitCode: 0
    signal actionFinished(string id, bool ok, int exitCode)

    // --- gc ---------------------------------------------------------------
    property bool gcBusy: false
    property var gcInfo: null // { bytes } freed by the last collect, or null

    // --- package index ----------------------------------------------------
    // Parsed once from `guix package -A' (32.7k entries, ~1.3s) and cached
    // here; filtering that in JS per keystroke is milliseconds, so there is
    // nothing for a resident process to keep warm.
    property var allPackages: []
    property bool packagesLoading: false
    property var installedHome: ({}) // name -> version, declarative profile
    property var installedUser: ({}) // name -> version, `guix install'

    readonly property int _logCap: 2000
    // Unbound: nothing binds to it, so pushing costs nothing in the scene graph.
    property var _logBuf: []
    // `guix gc' names every path it deletes; counting is the useful signal.
    property int gcDeleted: 0

    function refreshChannels(checkUpstream: bool): void {
        if (root.channelsLoading)
            return;
        root.channelsLoading = true;
        channelProc.command = checkUpstream ? ["guix-channel-status"] : ["guix-channel-status", "--local-only"];
        channelProc.running = true;
    }

    // Process executes argv directly, without shell expansion.
    function _expand(arg: string): string {
        let out = arg;
        if (out.startsWith("~/"))
            out = Quickshell.env("HOME") + out.slice(1);
        return out.replace(/\$\{(\w+)\}|\$(\w+)/g, (m, braced, bare) => Quickshell.env(braced ?? bare) ?? "");
    }

    function runAction(action: var): void {
        if (root.runningAction || !action?.command?.length)
            return;
        root.runningAction = action;
        root.phase = "";
        root._resetLog();
        actionProc.command = action.command.map(a => root._expand(a));
        actionProc.running = true;
    }

    function cancelAction(): void {
        if (actionProc.running)
            actionProc.running = false;
    }

    function collectGarbage(): void {
        if (root.gcBusy)
            return;
        root.gcBusy = true;
        root.gcDeleted = 0;
        root._resetLog();
        root.phase = qsTr("collecting garbage");
        gcProc.running = true;
    }

    function refreshPackages(): void {
        if (root.packagesLoading || root.allPackages.length > 0)
            return;
        root.packagesLoading = true;
        availProc.running = true;
        installedProc.running = true;
    }

    // Substring match over the cached index. `limit' keeps the delegate count
    // sane — 32k rows is not a list anyone scrolls.
    function search(query: string, limit: int): var {
        const q = query.trim().toLowerCase();
        if (q.length === 0)
            return [];
        const out = [];
        for (let i = 0; i < root.allPackages.length && out.length < limit; i++) {
            const p = root.allPackages[i];
            if (p.name.includes(q))
                out.push(p);
        }
        return out;
    }

    function sourceOf(name: string): string {
        if (root.installedHome[name] !== undefined)
            return "home";
        if (root.installedUser[name] !== undefined)
            return "user";
        return "";
    }

    function formatBytes(n: real): string {
        if (!n || n <= 0)
            return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let i = 0;
        let v = n;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
    }

    // Append WITHOUT touching the bound property: `logLines' is read by the
    // log pane, which re-joins it, so assigning per line made this O(n^2) in
    // lines and froze the shell outright on `guix gc' — that prints one line
    // per deleted store item, so tens of thousands of them, and RSS climbed
    // 785MB -> 1.0GB before the UI stopped repainting. Lines land in an unbound
    // buffer and the property is published on a timer instead.
    function _appendLog(line: string): void {
        // Progress output uses \r, so a chatty command can otherwise build one
        // unbounded "line" until the next newline arrives.
        const clean = line.replace(/\r/g, "");
        if (clean.length === 0)
            return;
        root._logBuf.push(clean);
        if (root._logBuf.length > root._logCap)
            root._logBuf.splice(0, root._logBuf.length - root._logCap);
        logFlush.start();
    }

    function _resetLog(): void {
        root._logBuf = [];
        root.logLines = [];
        logFlush.stop();
    }

    // Guix emits no machine-readable progress, so the bar stays indeterminate
    // and only this label changes. A parsed percentage would be a fiction.
    function _phaseOf(line: string): string {
        if (line.includes("Computing Guix derivation"))
            return qsTr("computing derivation");
        if (line.includes("Updating channel"))
            return qsTr("updating channels");
        if (line.includes("building /gnu/store"))
            return qsTr("building");
        if (line.startsWith("downloading ") || line.includes(" downloading "))
            return qsTr("downloading");
        if (line.includes("grafting"))
            return qsTr("grafting");
        return "";
    }

    function _parseAvailable(text: string): void {
        const rows = [];
        const lines = text.split("\n");
        for (const line of lines) {
            if (line.length === 0)
                continue;
            const f = line.split("\t");
            if (f.length < 2)
                continue;
            rows.push({
                name: f[0].trim(),
                version: f[1].trim(),
                outputs: (f[2] ?? "").trim(),
                location: (f[3] ?? "").trim()
            });
        }
        root.allPackages = rows;
    }

    function _parseInstalled(text: string): var {
        const map = {};
        for (const line of text.split("\n")) {
            if (line.length === 0)
                continue;
            const f = line.split("\t");
            if (f.length >= 2)
                map[f[0].trim()] = f[1].trim();
        }
        return map;
    }

    // Publish at 5Hz. Collapses thousands of line events into a handful of
    // property assignments, which is what makes a chatty build survivable.
    Timer {
        id: logFlush

        interval: 200
        repeat: false
        onTriggered: root.logLines = root._logBuf.slice()
    }

    Process {
        id: channelProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.channels = data.channels;
                    if (data.channels.some(c => c.upstream !== null))
                        root.upstreamKnown = true;
                } catch (e) {
                    console.warn("Guix: could not parse guix-channel-status:", e);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0)
                console.warn("Guix: channel-status:", text.trim())
        }

        onExited: root.channelsLoading = false // qmllint disable signal-handler-parameters
    }

    Process {
        id: actionProc

        // Both streams into the log: guix says most of what matters on stderr.
        stdout: SplitParser {
            onRead: data => {
                root._appendLog(data);
                const ph = root._phaseOf(data);
                if (ph.length > 0)
                    root.phase = ph;
            }
        }

        stderr: SplitParser {
            onRead: data => {
                root._appendLog(data);
                const ph = root._phaseOf(data);
                if (ph.length > 0)
                    root.phase = ph;
            }
        }

        onExited: (code, status) => {
            const action = root.runningAction;
            root.lastExitCode = code;
            root.phase = "";
            root.runningAction = null;
            if (action)
                root.actionFinished(action.id, code === 0, code);
            // A pull moves the channel commits; a rebuild can change the
            // profile, so the package index is stale too.
            root.refreshChannels(false);
            root.allPackages = [];
            root.installedHome = ({});
            root.installedUser = ({});
        }
    }

    Process {
        id: gcProc

        command: ["guix", "gc"]

        stdout: SplitParser {
            onRead: data => {
                // The bulk of gc output is one "deleting /gnu/store/..." per
                // item. Logging each is what froze the shell; count instead.
                if (data.startsWith("deleting ") || data.includes("/gnu/store/"))
                    root.gcDeleted++;
                else
                    root._appendLog(data);
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.startsWith("deleting ") || data.includes("/gnu/store/")) {
                    root.gcDeleted++;
                    return;
                }
                root._appendLog(data);
                // `guix gc' reports the total on stderr, e.g.
                // "freeing 4231 MiB" / "currently ... store".
                const m = data.match(/freeing ([0-9.]+) ?([KMGT]?i?B)/i);
                if (m)
                    root.gcInfo = { text: `${m[1]} ${m[2]}` };
            }
        }

        onExited: code => {
            root.gcBusy = false;
            root.phase = "";
            if (code !== 0)
                root._appendLog(qsTr("guix gc exited with %1").arg(code));
        }
    }

    Process {
        id: availProc

        command: ["guix", "package", "-A"]

        stdout: StdioCollector {
            onStreamFinished: {
                root._parseAvailable(text);
                root.packagesLoading = false;
            }
        }
    }

    Process {
        id: installedProc

        // Both profiles in one pass: the declarative home profile and the
        // imperative user one, which is the profile-vs-ad-hoc distinction the
        // page shows as a badge.
        command: ["sh", "-c", "guix package -p \"$HOME/.guix-home/profile\" -I; echo '---'; guix package -p \"$HOME/.guix-profile\" -I"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---\n");
                root.installedHome = root._parseInstalled(parts[0] ?? "");
                root.installedUser = root._parseInstalled(parts[1] ?? "");
            }
        }
    }
}
