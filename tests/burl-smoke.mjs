import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("smoke checks reject failed processes, bindings, and invalid geometry", () => {
    const directory = mkdtempSync(join(tmpdir(), "burl-smoke-test-"));
    try {
        const root = join(directory, "source");
        mkdirSync(root);
        writeFileSync(join(root, "Fixture.qml"), "import QtQuick\nItem {}\n");
        writeFileSync(join(directory, "quickshell"),
            '#!/bin/sh\nprintf "%s\\n" "$FIXTURE_LOG"\nexit "$FIXTURE_EXIT"\n', { mode: 0o755 });
        const run = (log, status = 0) => spawnSync("bash", [
            "scripts/qs-smoke.sh", "--root", root, "Fixture.qml"
        ], { env: { ...process.env, PATH: `${directory}:${process.env.PATH}`,
            FIXTURE_LOG: log, FIXTURE_EXIT: String(status) }, encoding: "utf8" });
        const good = "QSSMOKE-GEOM 640x480\nQSSMOKE-OK";
        assert.equal(run(good).status, 0);
        assert.equal(run("QSSMOKE-GEOM 10.5x20.25\nQSSMOKE-OK").status, 0);
        for (const [log, status] of [[good, 42], [good + "\nTypeError: bad binding", 0],
            ["QSSMOKE-GEOM 0x480\nQSSMOKE-OK", 0], ["QSSMOKE-OK", 0],
            [good + "\nReferenceError: missingName is not defined", 0],
            ["QSSMOKE-GEOM 0.0x10.5\nQSSMOKE-OK", 0],
            [good + "\nQSSMOKE-URLFAIL", 0], ["", 0]]) {
            assert.notEqual(run(log, status).status, 0, `${status}: ${log}`);
        }
    } finally {
        rmSync(directory, { recursive: true });
    }
});

test("make check-burl propagates a component failure", () => {
    const result = spawnSync("make", ["check-burl", "FILES=missing-fixture.qml"], { encoding: "utf8" });
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /no such component/);
});
