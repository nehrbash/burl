import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("actual MouseSettings confirms writes, persists choices and restores after reload", { skip: process.env.RUN_QML_MOUSE !== "1" }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-mouse-"));
    try {
        const root = join(dir, "quickshell", "qs");
        const services = join(root, "services");
        const fixture = join(root, "fixture");
        mkdirSync(services, { recursive: true }); mkdirSync(fixture); mkdirSync(join(dir, "bin"));
        copyFileSync(new URL("../services/MouseSettingsPolicy.js", import.meta.url), join(services, "MouseSettingsPolicy.js"));
        writeFileSync(join(services, "MouseSettings.qml"), readFileSync(new URL("../services/MouseSettings.qml", import.meta.url), "utf8").replace("import Burl.Config", "import qs.fixture"));
        writeFileSync(join(services, "Hypr.qml"), "pragma Singleton\nimport QtQuick\nQtObject { signal configReloaded() }\n");
        writeFileSync(join(fixture, "GlobalConfig.qml"), "pragma Singleton\nimport QtQuick\nQtObject { property var mouse: ({}); signal loaded() }\n");
        const python = spawnSync("which", ["python3"], { encoding: "utf8" }).stdout.trim();
        writeFileSync(join(dir, "bin", "hyprctl"), `#!${python}
import json, os, pathlib, re, sys
root = pathlib.Path(os.environ['MOUSE_TEST_DIR'])
path = root / 'actual.json'
initial = dict(accel_profile='flat', sensitivity=-0.4, natural_scroll=False, left_handed=False)
state = json.loads(path.read_text()) if path.exists() else initial.copy()
args = sys.argv[1:]
if args[0] == 'fixture-reset':
    state = initial.copy()
    for name in ['fail', 'readfail']:
        (root / name).unlink(missing_ok=True)
elif args[0] in ['fixture-fail', 'fixture-readfail']:
    (root / args[0].removeprefix('fixture-')).touch()
elif args[0] == 'eval':
    with (root / 'commands').open('a') as log: log.write(args[1] + '\\n')
    if (root / 'fail').exists():
        print('error: fixture refused settings')
        sys.exit(0)
    for key, value in re.findall(r'(accel_profile|sensitivity|natural_scroll|left_handed) = ("[^"]*"|true|false|[-.0-9]+)', args[1]):
        state[key] = json.loads(value)
elif args[0] == '-j':
    if (root / 'readfail').exists():
        print('invalid response')
        sys.exit(0)
    key = args[-1].split(':')[1]
    field = 'str' if key == 'accel_profile' else 'float' if key == 'sensitivity' else 'bool'
    print(json.dumps({field: state[key]}))
path.write_text(json.dumps(state))
`, { mode: 0o755 });
        writeFileSync(join(root, "test.qml"), `import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.fixture
ShellRoot {
    id: root
    settings.watchFiles: false
    property var mouse: MouseSettings
    property int step: 0
    property int ticks: 0
    property bool helperDone: false
    function check(value, text) { if (!value) throw new Error(text); }
    function helper(action) {
        helperDone = false;
        control.command = ["hyprctl", action];
        control.running = true;
    }
    Process { id: control; onExited: root.helperDone = true }
    Timer {
        interval: 30; repeat: true; running: true
        onTriggered: {
            try {
                if (++root.ticks > 300) throw new Error("fixture timed out");
                if (MouseSettings.busy) return;
                if (root.step === 0 && MouseSettings.ready) {
                    check(!MouseSettings.accelerationEnabled && MouseSettings.sensitivity === -0.4, "initial compositor state");
                    check(Object.keys(GlobalConfig.mouse).length === 0, "initial values not captured as overrides");
                    MouseSettings.toggleAcceleration();
                    check(!MouseSettings.accelerationEnabled, "no optimistic success");
                    root.step = 1;
                } else if (root.step === 1) {
                    check(MouseSettings.accelerationEnabled, "confirmed adaptive profile");
                    check(MouseSettings.sensitivity === -0.4, "toggle preserves sensitivity");
                    check(GlobalConfig.mouse.accel_profile === "adaptive", "choice saved after readback");
                    MouseSettings.setValue("sensitivity", 0.25);
                    root.step = 2;
                } else if (root.step === 2) {
                    check(MouseSettings.sensitivity === 0.25, "sensitivity confirmed");
                    root.helper("fixture-reset"); root.step = 3;
                } else if (root.step === 3 && root.helperDone) {
                    Hypr.configReloaded(); root.step = 4;
                } else if (root.step === 4) {
                    check(MouseSettings.accelerationEnabled && MouseSettings.sensitivity === 0.25, "reload reapplies durable choices");
                    root.helper("fixture-fail"); root.step = 5;
                } else if (root.step === 5 && root.helperDone) {
                    MouseSettings.setValue("natural_scroll", true); root.step = 6;
                } else if (root.step === 6) {
                    check(!MouseSettings.naturalScroll && MouseSettings.error.length > 0, "failed write shown accurately");
                    check(GlobalConfig.mouse.natural_scroll === undefined, "failed choice not saved");
                    root.helper("fixture-readfail"); root.step = 7;
                } else if (root.step === 7 && root.helperDone) {
                    MouseSettings.refresh(false); root.step = 8;
                } else if (root.step === 8) {
                    check(!MouseSettings.ready && MouseSettings.error.length > 0, "read failure disables editing");
                    root.helper("fixture-reset"); root.step = 9;
                } else if (root.step === 9 && root.helperDone) {
                    MouseSettings.refresh(true); root.step = 10;
                } else if (root.step === 10) {
                    check(MouseSettings.ready && !MouseSettings.error, "refresh recovers");
                    check(MouseSettings.accelerationEnabled && MouseSettings.sensitivity === 0.25, "recovery respects choices");
                    console.log("MOUSE-RUNTIME-PASS"); Qt.quit();
                }
            } catch (error) {
                console.error("MOUSE-RUNTIME-FAIL", error.message); Qt.quit();
            }
        }
    }
}
`);
        const run = spawnSync("quickshell", ["--no-color", "-p", join(root, "test.qml")], {
            encoding: "utf8", timeout: 15000,
            env: { ...process.env, PATH: `${join(dir, "bin")}:${process.env.PATH}`, MOUSE_TEST_DIR: dir,
                QT_QPA_PLATFORM: "offscreen", QS_NO_RELOAD_POPUP: "1",
                QML_IMPORT_PATH: process.env.QML_IMPORT_PATH || `${process.env.HOME}/.guix-home/profile/lib/qt6/qml` }
        });
        const output = run.stdout + run.stderr;
        assert.equal(run.status, 0, output);
        assert.match(output, /MOUSE-RUNTIME-PASS/);
        assert.doesNotMatch(output, /MOUSE-RUNTIME-FAIL|TypeError|ReferenceError|Unable to assign/);
    } finally { rmSync(dir, { recursive: true, force: true }); }
});
