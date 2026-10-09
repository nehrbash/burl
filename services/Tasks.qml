pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var pomodoro: _snapshot.pomodoro ?? _defaultPomo
    readonly property var tasks: _snapshot.tasks ?? []
    readonly property string filter: _snapshot.filter ?? "work"
    readonly property int totalCount: _snapshot.counts?.total ?? 0
    readonly property int visibleCount: _snapshot.counts?.visible ?? 0

    readonly property bool clockedIn: pomodoro.clocked_in ?? pomodoro["clocked-in"] ?? false
    readonly property bool onBreak: pomodoro.on_break ?? pomodoro["on-break"] ?? false

    // Toggle preferences (persisted Emacs-side, mirrored in the snapshot).
    readonly property var _prefs: _snapshot.prefs ?? ({})
    readonly property bool pomodoroOnClockIn: _prefs["pomodoro-on-clock-in"] ?? true
    readonly property bool clockInReminders: _prefs["clock-in-reminders"] ?? true

    // Live countdown — Emacs only pushes on transitions, so we
    // decrement locally each second from the last snapshot's
    // remaining-seconds so the overlay ticks smoothly.
    property real _snapshotTakenAt: 0
    property int _liveTick: 0
    // Incremented/decremented by the views that render the countdown, exactly
    // like SwayClock.subscribers. Only TaskNudge does today.
    property int countdownWatchers: 0
    readonly property bool _countdownRunning: (pomodoro.enabled ?? false) && (clockedIn || onBreak) && (pomodoro["remaining-seconds"] ?? pomodoro.remaining_seconds ?? 0) > 0
    readonly property int liveRemainingSeconds: {
        void _liveTick;
        const base = pomodoro["remaining-seconds"] ?? pomodoro.remaining_seconds ?? 0;
        if (!_snapshotTakenAt)
            return base;
        const elapsed = (Date.now() - _snapshotTakenAt) / 1000;
        return Math.max(0, Math.floor(base - elapsed));
    }
    readonly property string liveTime: {
        const r = liveRemainingSeconds;
        const m = Math.floor(r / 60);
        const s = r % 60;
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0");
    }
    readonly property real livePercent: {
        const total = pomodoro["total-seconds"] ?? pomodoro.total_seconds ?? 0;
        if (!total)
            return pomodoro.percent ?? 0;
        if (onBreak)
            return 100 * (1 - liveRemainingSeconds / total);
        return 100 * (1 - liveRemainingSeconds / total);
    }

    property string dailyReport
    property string weeklyReport

    signal snapshotUpdated
    signal reportUpdated(string period, string body)

    property var _snapshot: ({})
    readonly property var _defaultPomo: ({
            enabled: false,
            "clocked-in": false,
            "on-break": false,
            percent: 0,
            time: "00:00",
            task: "No Active Task",
            summary: "No Active Task 00:00",
            keystrokes: 0,
            "keystrokes-target": 0
        })

    function refresh(): void {
        // Force Emacs to rewrite the state file even when nothing changed.
        runSideEffect("(progn (setq sn-tasks--last-state-json nil) (sn-tasks/write-state))");
    }

    function setFilter(tag: string): void {
        const escaped = tag.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        runSideEffect(`(sn-tasks/set-filter "${escaped}")`);
    }

    function clockIn(title: string): void {
        const escaped = title.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        runSideEffect(`(sn-tasks/clock-in-by-title "${escaped}")`);
    }

    // THE clock-in entry point — dashboard and TaskNudge must both call
    // through here rather than keep their own copy, so behaviour can't drift
    // between the two surfaces.
    //
    // Returns whether the clock-in was issued, so a caller can decide what to do
    // with itself (the nudge dismisses; the tab does not).
    function clockInTask(task: var): bool {
        if (!task?.title)
            return false;
        const s = task.state ?? "";
        if (s === "DONE" || s === "HOLD" || s === "CANCELLED")
            return false;
        root.clockIn(task.title);
        return true;
    }

    function clockOut(): void {
        runSideEffect("(sn-tasks/clock-out)");
    }

    function markDone(): void {
        runSideEffect("(sn-tasks/mark-done)");
    }

    function setState(title: string, state: string): void {
        const t = title.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        const s = state.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        runSideEffect(`(sn-tasks/set-state-by-title "${t}" "${s}")`);
    }

    function archive(title: string): void {
        const t = title.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        runSideEffect(`(sn-tasks/archive-by-title "${t}")`);
    }

    function addProject(title: string): void {
        const t = title.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        runSideEffect(`(sn-tasks/add-project "${t}")`);
    }

    function addTask(project: string, title: string): void {
        const p = project.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        const t = title.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        runSideEffect(`(sn-tasks/add-task "${p}" "${t}")`);
    }

    function toggleTypeBreak(): void {
        runSideEffect("(sn-tasks/type-break-toggle)");
    }

    function startBreak(): void {
        runSideEffect("(sn-tasks/start-break)");
    }

    function endBreak(): void {
        runSideEffect("(sn-tasks/end-break)");
    }

    function stopPomodoro(): void {
        runSideEffect("(sn-tasks/stop-pomodoro)");
    }

    function togglePomodoroOnClockIn(): void {
        runSideEffect("(sn-tasks/toggle-pomodoro-on-clock-in)");
    }

    function toggleClockInReminders(): void {
        runSideEffect("(sn-tasks/toggle-clock-in-reminders)");
    }

    function runSideEffect(sexp: string): void {
        // Fire-and-forget: reusing a single Process and toggling running aborts
        // any in-flight emacsclient, which the daemon logs as "connection broken
        // by remote peer". Detached invocations avoid the cancellation race.
        Quickshell.execDetached(["timeout", "5", "emacsclient", "-e", sexp]);
    }

    function fetchReport(period: string): void {
        if (period === "today") {
            if (dailyProc.running)
                return;
            dailyProc.running = true;
        } else {
            if (weeklyProc.running)
                return;
            weeklyProc.running = true;
        }
    }

    function _parseSnapshot(raw: string): void {
        const unquoted = _unquoteElisp(raw);
        if (!unquoted)
            return;
        try {
            _snapshot = JSON.parse(unquoted);
            _snapshotTakenAt = Date.now();
            snapshotUpdated();
        } catch (e) {
            console.warn("Tasks: failed to parse snapshot:", e, unquoted.slice(0, 200));
        }
    }

    function _unquoteElisp(raw: string): string {
        // emacsclient returns lisp-quoted string: "\"{...}\"" — strip wrapping and unescape.
        let s = (raw ?? "").trim();
        if (!s)
            return "";
        if (s.startsWith("\"") && s.endsWith("\""))
            s = s.slice(1, -1);
        return s.replace(/\\"/g, "\"").replace(/\\\\/g, "\\").replace(/\\n/g, "\n");
    }

    // State is pushed by Emacs (sn-tasks/write-state) on every transition:
    // org-clock in/out, type-break mode toggle, entering/leaving rest,
    // filter changes.  We just watch the file — no periodic polling, no
    // emacsclient round-trips for reads.
    FileView {
        id: stateView

        path: `${Quickshell.env("HOME")}/.cache/sn-tasks-state.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._parseSnapshot(text())
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                bootstrapProc.running = true;
        }
    }

    // One-shot bootstrap: if the state file doesn't exist yet (fresh
    // Emacs daemon, file purged, etc.) ask Emacs to write it.  FileView
    // picks up the new file on its own.
    Process {
        id: bootstrapProc

        command: ["timeout", "5", "emacsclient", "-e", "(sn-tasks/write-state)"]
    }

    Process {
        id: dailyProc

        command: ["timeout", "10", "emacsclient", "-e", "(sn-tasks/report \"today\")"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.dailyReport = root._unquoteElisp(text);
                root.reportUpdated("today", root.dailyReport);
            }
        }
    }

    Process {
        id: weeklyProc

        command: ["timeout", "10", "emacsclient", "-e", "(sn-tasks/report \"thisweek\")"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.weeklyReport = root._unquoteElisp(text);
                root.reportUpdated("thisweek", root.weeklyReport);
            }
        }
    }

    // 1Hz tick driving the live countdown between Emacs pushes. Gated on
    // countdownWatchers so it doesn't re-evaluate liveTime/livePercent when
    // nothing on screen is reading them.
    Timer {
        interval: 1000
        running: root.countdownWatchers > 0 && root._countdownRunning
        repeat: true
        onTriggered: root._liveTick++
    }
}
