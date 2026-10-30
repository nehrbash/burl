pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool integrationEnabled: Quickshell.env("BURL_EMACS_INTEGRATION") === "1"

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

    property var dailyData: ({rows: []})
    property var weeklyData: ({rows: []})
    readonly property bool dailyLoading: dailyProc.running
    readonly property bool weeklyLoading: weeklyProc.running
    property string dailyError
    property string weeklyError

    function toggleBreakReminders(): void {
        runSideEffect("(sn-tasks/toggle-break-reminders)");
    }

    property string requestedTab: "tasks"
    signal viewRequested(string tab)
    signal pickerRequested
    signal breakDismissed
    signal clockInSucceeded
    readonly property bool clockInPending: clockInProc.running
    property string clockInError: ""

    function openTasks(tab: string): void {
        requestedTab = tab || "tasks";
        viewRequested(requestedTab);
        const screen = ShellState.forActive();
        if (!screen) return;
        screen.growDashboardSection("tasks");
        screen.openWorldRoom("dashboard", "ipc");
    }


    signal snapshotUpdated

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
        clockInTask({title});
    }

    function clockInTask(task: var): bool {
        if (clockInPending || !task?.title)
            return false;
        if (["DONE", "HOLD", "CANCELLED"].includes(task.state ?? ""))
            return false;
        clockInError = "";
        if (!integrationEnabled) {
            clockInError = qsTr("Emacs task integration is unavailable.");
            return false;
        }
        const escaped = task.title.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        clockInProc.command = ["timeout", "30", "emacsclient", "-e",
            `(if (sn-tasks/clock-in-by-title "${escaped}") (progn (sn-tasks/write-state) t) (error "Task was not found"))`];
        clockInProc.running = true;
        return true;
    }

    function finishClockIn(output: string, error: string, code: int): void {
        if (code === 0 && output.trim() === "t") {
            clockInError = "";
            clockInSucceeded();
        } else {
            clockInError = code === 124 ? qsTr("Emacs did not finish clocking in. Check Emacs for a pending prompt.")
                : error.trim() || qsTr("Emacs could not clock into the task.");
        }
    }

    function clockOut(): void {
        runSideEffect("(sn-tasks/clock-out)");
    }

    // Emacs decides after its idle threshold whether to close the clock at lock time.
    function idleStart(): void {
        runSideEffect("(when (fboundp 'sn-worklog/idle-start) (sn-worklog/idle-start))");
    }

    function idleEnd(): void {
        runSideEffect("(when (fboundp 'sn-worklog/idle-end) (sn-worklog/idle-end))");
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
        breakDismissed();
        runSideEffect("(sn-tasks/end-break)");
    }

    function stopPomodoro(): void {
        breakDismissed();
        runSideEffect("(sn-tasks/stop-pomodoro)");
    }

    function togglePomodoroOnClockIn(): void {
        runSideEffect("(sn-tasks/toggle-pomodoro-on-clock-in)");
    }

    function toggleClockInReminders(): void {
        runSideEffect("(sn-tasks/toggle-clock-in-reminders)");
    }

    function runSideEffect(sexp: string): void {
        if (!integrationEnabled) return;
        // Fire-and-forget: reusing a single Process and toggling running aborts
        // any in-flight emacsclient, which the daemon logs as "connection broken
        // by remote peer". Detached invocations avoid the cancellation race.
        Quickshell.execDetached(["timeout", "5", "emacsclient", "-e", sexp]);
    }

    function fetchReport(period: string): void {
        if (!integrationEnabled) return;
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
        const snapshot = (raw ?? "").trim();
        if (!snapshot)
            return;
        try {
            _snapshot = JSON.parse(snapshot);
            _snapshotTakenAt = _snapshot.generated_at ? _snapshot.generated_at * 1000 : Date.now();
            snapshotUpdated();
        } catch (e) {
            console.warn("Tasks: failed to parse snapshot:", e, snapshot.slice(0, 200));
        }
    }

    function _parseReport(raw: string, period: string, code: int): void {
        try {
            if (code !== 0) throw new Error("Emacs report request failed");
            const report = JSON.parse(_unquoteElisp(raw));
            if (!Array.isArray(report.rows)) throw new Error("Invalid report data");
            if (period === "today") { dailyData = report; dailyError = ""; }
            else { weeklyData = report; weeklyError = ""; }
        } catch (e) {
            if (period === "today") dailyError = String(e);
            else weeklyError = String(e);
        }
    }

    function _unquoteElisp(raw: string): string {
        // emacsclient returns lisp-quoted string: "\"{...}\"" — strip wrapping and unescape.
        let s = (raw ?? "").trim();
        if (!s)
            return "";
        if (s.startsWith("\"") && s.endsWith("\""))
            s = s.slice(1, -1);
        return s.replace(/\\([\\"nrt])/g, (_, c) => c === "n" ? "\n" : c === "r" ? "\r" : c === "t" ? "\t" : c);
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
            if (root.integrationEnabled && err === FileViewError.FileNotFound)
                bootstrapProc.running = true;
        }
    }

    // One-shot bootstrap: if the state file doesn't exist yet (fresh
    // Emacs daemon, file purged, etc.) ask Emacs to write it.  FileView
    // picks up the new file on its own.
    Process {
        id: clockInProc
        stdout: StdioCollector { id: clockInOutput }
        stderr: StdioCollector { id: clockInErrors }
        onExited: code => root.finishClockIn(clockInOutput.text, clockInErrors.text, code)
    }

    Process {
        id: bootstrapProc

        command: ["timeout", "5", "emacsclient", "-e", "(sn-tasks/write-state)"]
    }

    Process {
        id: dailyProc
        command: ["timeout", "10", "emacsclient", "-e", "(sn-worklog/report-json \"today\")"]
        stdout: StdioCollector { id: dailyOut }
        onExited: code => root._parseReport(dailyOut.text, "today", code)
    }

    Process {
        id: weeklyProc
        command: ["timeout", "10", "emacsclient", "-e", "(sn-worklog/report-json \"thisweek\")"]
        stdout: StdioCollector { id: weeklyOut }
        onExited: code => root._parseReport(weeklyOut.text, "thisweek", code)
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
