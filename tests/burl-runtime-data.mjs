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
