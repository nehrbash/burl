import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import { test } from "node:test";

const script = new URL("../bin/burl-record", import.meta.url).pathname;

function fixture(t) {
    const dir = mkdtempSync(join(tmpdir(), "burl-recorder-test-"));
    const bin = join(dir, "bin");
    mkdirSync(bin);
    const env = { ...process.env, HOME: dir, XDG_STATE_HOME: join(dir, "state"), XDG_PICTURES_DIR: join(dir, "pictures"), MOCK_ROOT: dir, PATH: `${bin}:${process.env.PATH}` };
    const mock = (name, content) => writeFileSync(join(bin, name), content, { mode: 0o755 });
    mock("hyprctl", '#!/bin/sh\nprintf \'[{"name":"test","focused":true,"refreshRate":60,"x":0,"y":0,"width":100,"height":100}]\\n\'\n');
    mock("notify-send", '#!/bin/sh\necho "$*" >>"$MOCK_ROOT/notifications"\ncase " $* " in *" -p "*) echo 42;; esac\n');
    mock("gdbus", '#!/bin/sh\nexit 0\n');
    mock("slurp", `#!/usr/bin/env python3
import os,time
from pathlib import Path
p=Path(os.environ['MOCK_ROOT'])
(p/'selection-started').touch()
while not (p/'selection-release').exists():
    if (p/'selection-cancel').exists(): raise SystemExit(1)
    time.sleep(.01)
print('50x50+0+0')
`);
    mock("gpu-screen-recorder", `#!/usr/bin/env python3
import os,sys,time,signal
from pathlib import Path
p=Path(os.environ['MOCK_ROOT'])
if (p/'capture-fail').exists(): raise SystemExit(1)
out=Path(sys.argv[sys.argv.index('-o')+1]);out.write_bytes(b'mocked capture')
(p/'capture-started').touch()
signal.signal(signal.SIGUSR2,lambda *args: None)
while not (p/'capture-exit').exists(): time.sleep(.01)
`);
    const run = (...args) => {
        const result = spawnSync(script, args, { env, encoding: "utf8", timeout: 5000 });
        assert.equal(result.status, 0, result.stderr || String(result.error));
        return result.stdout;
    };
    const state = () => JSON.parse(run("--status")).state;
    const until = async predicate => {
        const deadline = Date.now() + 5000;
        while (!predicate()) {
            assert.ok(Date.now() < deadline, "recorder state transition deadline");
            await delay(20);
        }
    };
    t.after(async () => {
        run("--stop");
        await until(() => state() === "idle");
        rmSync(dir, { recursive: true, force: true });
    });
    return { dir, env, run, state, until, touch: name => writeFileSync(join(dir, name), ""), exists: name => existsSync(join(dir, name)) };
}

test("stop cancels an owned pending selection and cannot start a later capture", async t => {
    const h = fixture(t);
    h.run("--start", "-r");
    await h.until(() => h.exists("selection-started"));
    assert.equal(h.state(), "selecting");
    h.run("--stop");
    await h.until(() => h.state() === "idle");
    h.touch("selection-release");
    await delay(100);
    assert.equal(h.exists("capture-started"), false);
});

test("delayed selection stays pending then captures, pauses, and saves after stop", async t => {
    const h = fixture(t);
    h.run("--start", "-r");
    await h.until(() => h.exists("selection-started"));
    await delay(150);
    assert.equal(h.state(), "selecting");
    h.run("--start", "-r");
    assert.equal(h.state(), "selecting");
    h.touch("selection-release");
    await h.until(() => h.exists("capture-started"));
    h.run("--pause");
    await h.until(() => h.state() === "paused");
    h.run("--pause");
    await h.until(() => h.state() === "recording");
    h.run("--stop");
    await h.until(() => h.state() === "idle");
    assert.equal(readdirSync(join(h.dir, "pictures/Recordings")).length, 1);
});

test("capture exit is reaped and saved without a UI liveness timer", async t => {
    const h = fixture(t);
    h.run("--start");
    await h.until(() => h.exists("capture-started"));
    h.touch("capture-exit");
    await h.until(() => h.state() === "idle");
    const files = readdirSync(join(h.dir, "pictures/Recordings"));
    assert.equal(files.length, 1);
    assert.equal(readFileSync(join(h.dir, "pictures/Recordings", files[0]), "utf8"), "mocked capture");
});


test("Escape during selection clears state without creating a recording", async t => {
    const h = fixture(t);
    h.run("--start", "-r");
    await h.until(() => h.exists("selection-started"));
    h.touch("selection-cancel");
    await h.until(() => h.state() === "idle");
    assert.equal(h.exists("capture-started"), false);
});

test("failed recorder startup clears state and reports failure", async t => {
    const h = fixture(t);
    h.touch("capture-fail");
    h.run("--start");
    await h.until(() => h.exists("notifications") && readFileSync(join(h.dir, "notifications"), "utf8").includes("Recording failed"));
    await h.until(() => h.state() === "idle");
    assert.equal(h.exists("capture-started"), false);
});


test("fresh state directory gains a watched file and native UI observes selection cancellation", { skip: !process.env.WAYLAND_DISPLAY }, async t => {
    const h = fixture(t);
    const qmlRoot = join(h.dir, "quickshell/qs");
    mkdirSync(qmlRoot, { recursive: true });
    const sourceRoot = new URL("../", import.meta.url).pathname;
    for (const entry of readdirSync(sourceRoot)) symlinkSync(join(sourceRoot, entry), join(qmlRoot, entry));
    const probe = join(qmlRoot, "recorder-probe.qml");
    writeFileSync(probe, `import QtQuick
import Quickshell
import qs.services
ShellRoot {
    property bool selected: false
    Connections {
        target: Recorder
        function onStateChanged() {
            if (Recorder.state === "selecting") {
                selected = true;
                Recorder.stop();
            } else if (selected && Recorder.state === "idle") {
                console.log("RECORDER-WATCH-PASS");
                Qt.quit();
            }
        }
    }
    Timer { interval: 300; running: true; onTriggered: Recorder.start(["-r"]) }
    Timer { interval: 10000; running: true; onTriggered: Qt.quit() }
}`);
    const qmlPath = process.env.QML_IMPORT_PATH || `${process.env.HOME}/.guix-home/profile/lib/qt6/qml`;
    const proc = spawn("quickshell", ["--no-color", "-p", probe], {
        env: { ...h.env, PATH: `${sourceRoot}/bin:${h.env.PATH}`, QML_IMPORT_PATH: qmlPath, QML2_IMPORT_PATH: qmlPath },
        stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    proc.stdout.on("data", data => { output += data; });
    proc.stderr.on("data", data => { output += data; });
    const deadline = setTimeout(() => proc.kill("SIGKILL"), 15000);
    const result = await new Promise(resolve => proc.on("exit", resolve));
    clearTimeout(deadline);
    assert.equal(result, 0, output);
    assert.match(output, /RECORDER-WATCH-PASS/);
    assert.equal(h.state(), "idle");
});
