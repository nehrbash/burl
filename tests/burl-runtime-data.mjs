import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

function source(path) {
    return readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
}

function qmlFunction(path, name, context) {
    const match = source(path).match(new RegExp(`^    function ${name}\\(([^)]*)\\): \\w+ \\{([\\s\\S]*?)\\n    \\}`, "m"));
    assert.ok(match, `${name} exists`);
    const args = match[1].replace(/:\s*\w+(?:<\w+>)?/g, "");
    return runInNewContext(`(function(${args}) {${match[2]}\n})`, context);
}

test("task file snapshots preserve JSON escapes and reject malformed updates", () => {
    let updates = 0;
    const context = {
        _snapshot: {}, _snapshotTakenAt: 0,
        snapshotUpdated: () => updates++,
        console: { warn() {} },
    };
    const parse = qmlFunction("services/Tasks.qml", "_parseSnapshot", context);
    const expected = { tasks: [{ title: 'Fix "quoted" task\\path\nnext line' }], pomodoro: { task: "Write λ" } };
    parse(JSON.stringify(expected));
    assert.equal(JSON.stringify(context._snapshot), JSON.stringify(expected));
    assert.equal(updates, 1);
    assert.ok(context._snapshotTakenAt > 0);
    parse('{"tasks":');
    parse("");
    assert.equal(updates, 1);
    assert.equal(JSON.stringify(context._snapshot), JSON.stringify(expected));
});

test("network command completion releases every dynamically owned process", () => {
    const activeProcesses = [];
    const live = new Set();
    const root = {};
    const pending = [];
    const context = {
        activeProcesses, root,
        Qt: { callLater: fn => pending.push(fn) },
        commandProc: { createObject(parent) {
            assert.equal(parent, root);
            const proc = {
                processFinished: { connect(fn) { proc.finish = fn; } },
                exec(args) { assert.equal(args[0], "nmcli"); },
                destroy() { assert.ok(live.delete(proc)); },
            };
            live.add(proc);
            return proc;
        } },
    };
    const execute = qmlFunction("services/Nmcli.qml", "executeCommand", context);
    for (let i = 0; i < 100; i++) execute(["device", "status"], () => {});
    pending.forEach(fn => fn());
    assert.equal(live.size, 100);
    for (const proc of [...live].reverse()) proc.finish();
    assert.equal(activeProcesses.length, 0);
    assert.equal(live.size, 0);
});

test("recording dates retain month-end and leap-day timestamps", () => {
    const match = source("modules/utilities/cards/RecordingList.qml").match(/text: \{\s*(const time = recording.baseName;[\s\S]*?)\n                \}/);
    assert.ok(match);
    for (const [stamp, year, month, day] of [
        ["20260131", 2026, 0, 31], ["20240229", 2024, 1, 29],
        ["20260831", 2026, 7, 31], ["20261231", 2026, 11, 31],
    ]) {
        const date = runInNewContext(`(function() {${match[1]}})()`, {
            recording: { baseName: `recording_${stamp}_12-34-56` },
            qsTr: () => ({ arg: value => value }),
            Qt: { formatDateTime: date => date, locale() {} },
        });
        assert.equal(date.getFullYear(), year);
        assert.equal(date.getMonth(), month);
        assert.equal(date.getDate(), day);
        assert.equal(date.getHours(), 12);
    }
});

test("worklog report decoding preserves escaped titles and Unicode", () => {
    const decode = qmlFunction("services/Tasks.qml", "_unquoteElisp", {});
    const report = {rows: [{title: 'Write "quotes" and \\paths\nλ', seconds: 600}]};
    assert.deepEqual(JSON.parse(decode(JSON.stringify(JSON.stringify(report)))), report);
});

test("failed worklog reports retain data and expose an error", () => {
    const previous = {rows: [{title: "Existing", seconds: 600}]};
    const context = {dailyData: previous, dailyError: "", _unquoteElisp: raw => raw};
    const parse = qmlFunction("services/Tasks.qml", "_parseReport", context);
    parse("", "today", 124);
    assert.equal(context.dailyData, previous);
    assert.match(context.dailyError, /failed/);
    parse('{"rows":[]}', "today", 0);
    assert.equal(context.dailyError, "");
    assert.equal(context.dailyData.rows.length, 0);
});

test("stopping clock-in nudges leaves break reminders alone and never enables nudges", () => {
    let toggles = 0;
    const root = { manuallyOpen: true, deferred: false };
    const Tasks = { clockInReminders: true, toggleClockInReminders() { toggles++; } };
    const stop = qmlFunction("modules/tasknudge/TaskNudge.qml", "stopClockInReminders", { root, Tasks });
    stop();
    assert.equal(toggles, 1);
    assert.equal(root.manuallyOpen, false);
    assert.equal(root.deferred, true);
    Tasks.clockInReminders = false;
    stop();
    assert.equal(toggles, 1);
});

test("one network indicator distinguishes wired, wireless, disabled and disconnected", () => {
    const bar = source("modules/bar/components/StatusIcons.qml");
    assert.equal((bar.match(/name: "network"/g) ?? []).length, 1);
    assert.equal((bar.match(/name: "ethernet"/g) ?? []).length, 0);
    const binding = bar.match(/text: (Nmcli\.activeEthernet[\s\S]*?)\n                color:/)[1];
    const Icons = {getNetworkIcon: strength => `signal-${strength}`};
    for (const [Nmcli, expected] of [
        [{activeEthernet: {}, wifiEnabled: true, active: {strength: 80}}, "cable"],
        [{activeEthernet: {}, wifiEnabled: false}, "cable"],
        [{wifiEnabled: true, active: {strength: 80}}, "signal-80"],
        [{wifiEnabled: true}, "wifi_find"],
        [{wifiEnabled: false}, "wifi_off"],
    ]) assert.equal(runInNewContext(binding, {Nmcli, Icons}), expected);
});

test("clock-in waits for Emacs confirmation and reports errors", () => {
    let succeeded = 0;
    const context = {clockInError: "", clockInSucceeded: () => succeeded++, qsTr: text => text};
    const finish = qmlFunction("services/Tasks.qml", "finishClockIn", context);
    finish("", "Resolve the unfinished clock first", 1);
    assert.equal(succeeded, 0);
    assert.match(context.clockInError, /unfinished clock/);
    finish("", "", 124);
    assert.equal(succeeded, 0);
    assert.match(context.clockInError, /pending prompt/);
    finish("nil", "", 0);
    assert.equal(succeeded, 0);
    finish("t\n", "", 0);
    assert.equal(succeeded, 1);
    assert.equal(context.clockInError, "");
});

test("clock-in rejects unavailable integration and duplicate requests", () => {
    const context = {clockInPending: false, integrationEnabled: false, clockInError: "", clockInProc: {}, qsTr: text => text};
    const start = qmlFunction("services/Tasks.qml", "clockInTask", context);
    assert.equal(start({title: "Task"}), false);
    assert.match(context.clockInError, /unavailable/);
    context.integrationEnabled = true;
    assert.equal(start({title: 'Task "quoted" \\path'}), true);
    assert.equal(context.clockInProc.running, true);
    assert.match(context.clockInProc.command[4], /Task \\"quoted\\" \\\\path/);
    context.clockInPending = true;
    assert.equal(start({title: "Another task"}), false);
});
