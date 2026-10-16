import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("actual QML owner survives reload, process failure and deadline", { skip: process.env.RUN_QML_EFFECTS !== "1" }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-effects-"));
    try {
        const root = join(dir, "quickshell", "qs");
        const services = join(root, "services");
        mkdirSync(services, { recursive: true });
        mkdirSync(join(dir, "bin"));
        for (const name of ["CompositorEffects.qml", "CompositorEffectPolicy.js", "FocusMode.qml"])
            copyFileSync(new URL(`../services/${name}`, import.meta.url), join(services, name));
        writeFileSync(join(services, "Hypr.qml"), `pragma Singleton
import QtQuick
QtObject {
    signal configReloaded()
    property var batches: []
    property QtObject extras: QtObject {
        function batchMessage(messages) { Hypr.batches = Hypr.batches.concat([messages]); }
    }
}
`);
        for (const [name, method] of [["ShellState", "function setBarAll(value) {}"], ["Toaster", "function toast(title, text, icon) {}"]])
            writeFileSync(join(services, `${name}.qml`), `pragma Singleton\nimport QtQuick\nQtObject { ${method} }\n`);
        writeFileSync(join(dir, "bin", "hyprctl"), `#!/bin/sh
count=0
[ ! -f "$EFFECTS_TEST_COUNT" ] || read -r count < "$EFFECTS_TEST_COUNT"
count=$((count + 1))
printf '%s\\n' "$count" > "$EFFECTS_TEST_COUNT"
case $count in
  2) exit 1 ;;
  3) exec sleep 10 ;;
esac
exit 0
`, { mode: 0o755 });
        writeFileSync(join(root, "test.qml"), `import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    settings.watchFiles: false
    property var mode: FocusMode
    property int step: 0
    property int ticks: 0
    PersistentProperties {
        id: progress
        reloadableId: "effects-test"
        property bool reloaded: false
    }
    function check(value, text) { if (!value) throw new Error(text); }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            try {
                if (!CompositorEffects.ready) return;
                root.ticks++;
                if (root.ticks > 240) throw new Error("fixture timed out");
                const state = CompositorEffects.state;
                if (root.step === 0) {
                    if (!progress.reloaded) {
                        FocusMode.enabled = true;
                        CompositorEffects.setMode("performance", true);
                        check(Object.keys(CompositorEffects.state.applied).length === 10, "both active");
                        progress.reloaded = true;
                        Quickshell.reload(false);
                        root.step = -1;
                    } else {
                        check(FocusMode.enabled && state.focus && state.performance, "scalar mode restore");
                        check(Object.keys(state.applied).length === 10, "applied restore");
                        check(Hypr.batches.some(batch => batch.length === 10), "startup reapplies union");
                        CompositorEffects.setMode("performance", false);
                        root.step = 1;
                    }
                } else if (root.step === 1 && !state.pending) {
                    check(Object.keys(state.applied).length === 6, "process completion recomposes focus");
                    Hypr.configReloaded();
                    check(Hypr.batches[Hypr.batches.length - 1].length === 6, "external reload recomposes focus");
                    FocusMode.enabled = false;
                    root.step = 2;
                } else if (root.step === 2 && !state.pending) {
                    check(Object.keys(state.applied).length === 6, "failure keeps restoration debt");
                    CompositorEffects.setMode("focus", false);
                    root.step = 3;
                } else if (root.step === 3 && !state.pending) {
                    check(CompositorEffects.timedOut, "deadline released pending");
                    CompositorEffects.setMode("focus", false);
                    root.step = 4;
                } else if (root.step === 4 && !state.pending) {
                    check(Object.keys(state.applied).length === 0, "retry restores config");
                    console.log("EFFECTS-RUNTIME-PASS");
                    Qt.quit();
                }
            } catch (error) {
                console.error("EFFECTS-RUNTIME-FAIL", error.message);
                Qt.quit();
            }
        }
    }
}
`);
        const run = spawnSync("quickshell", ["--no-color", "-p", join(root, "test.qml")], {
            encoding: "utf8", timeout: 20000,
            env: { ...process.env, PATH: `${join(dir, "bin")}:${process.env.PATH}`,
                EFFECTS_TEST_COUNT: join(dir, "count"), QT_QPA_PLATFORM: "offscreen", QS_NO_RELOAD_POPUP: "1",
                QML_IMPORT_PATH: process.env.QML_IMPORT_PATH || `${process.env.HOME}/.guix-home/profile/lib/qt6/qml` }
        });
        const output = run.stdout + run.stderr;
        assert.equal(run.status, 0, output);
        assert.match(output, /EFFECTS-RUNTIME-PASS/);
        assert.doesNotMatch(output, /EFFECTS-RUNTIME-FAIL|TypeError|ReferenceError|Unable to assign|JSValue can't be reassigned/);
        assert.equal(readFileSync(join(dir, "count"), "utf8").trim(), "4");
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
