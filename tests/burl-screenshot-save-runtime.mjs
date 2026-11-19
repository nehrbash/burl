import assert from "node:assert/strict";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("screenshot saves create the library, retain previews and report collisions", { skip: process.env.RUN_QML_SCREENSHOTS !== "1" }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-screenshot-save-"));
    try {
        const root = join(dir, "quickshell", "qs");
        const cache = join(dir, "cache", "screenshots");
        const pictures = join(dir, "pictures");
        const saved = join(pictures, "Screenshots");
        for (const subdir of [join(root, "services"), join(root, "utils"), cache, pictures])
            mkdirSync(subdir, { recursive: true });
        const name = "20261119110000";
        const source = join(cache, name);
        const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64");
        writeFileSync(source, png);
        writeFileSync(join(cache, "collision"), png);
        writeFileSync(join(root, "services", "Screenshots.qml"),
            readFileSync(new URL("../services/Screenshots.qml", import.meta.url), "utf8"));
        writeFileSync(join(root, "utils", "Paths.qml"), `pragma Singleton
import QtQuick
QtObject {
    readonly property string cache: ${JSON.stringify(join(dir, "cache"))}
    readonly property string pictures: ${JSON.stringify(pictures)}
    function shortenHome(path) { return path; }
}
`);
        writeFileSync(join(root, "test.qml"), `import QtQuick
import Quickshell
import Burl
import qs.services
ShellRoot {
    id: root
    settings.watchFiles: false
    property var shots: Screenshots
    property int stage: 0
    property int ticks: 0
    function check(value, message) { if (!value) throw new Error(message); }
    Timer {
        interval: 30; repeat: true; running: true
        onTriggered: {
            try {
                if (++root.ticks > 180) throw new Error("save state timed out: " + root.stage);
                if (root.stage === 0 && Screenshots.entries.length === 2) {
                    Screenshots.openPreview(${JSON.stringify(source)});
                    Screenshots.save(${JSON.stringify(source)}, ${JSON.stringify(name)});
                    check(Toaster.toasts.length === 0, "must wait for the move before claiming success");
                    root.stage = 1;
                } else if (root.stage === 1 && Screenshots.previewEntry?.saved) {
                    check(Screenshots.previewPath === ${JSON.stringify(join(saved, name + ".png"))}, "preview follows saved path");
                    check(Toaster.toasts.length === 1 && Toaster.toasts[0].icon === "bookmark_add", "success reported once");
                    Screenshots.openPreview(${JSON.stringify(join(cache, "collision"))});
                    Screenshots.save(${JSON.stringify(join(cache, "collision"))}, ${JSON.stringify(name)});
                    root.stage = 2;
                } else if (root.stage === 2 && Toaster.toasts.length === 2) {
                    check(Toaster.toasts[0].icon === "error", "collision reports failure");
                    check(Screenshots.previewPath === ${JSON.stringify(join(cache, "collision"))}, "failed save keeps original preview");
                    check(Screenshots.pendingSave === "", "failed save releases pending state");
                    Screenshots.save(${JSON.stringify(join(cache, "missing"))}, "missing");
                    root.stage = 3;
                } else if (root.stage === 3 && Toaster.toasts.length === 3) {
                    check(Toaster.toasts[0].icon === "error", "missing source reports failure");
                    console.log("SCREENSHOT-SAVE-PASS"); Qt.quit();
                }
            } catch (error) {
                console.log("SCREENSHOT-SAVE-FAIL", error.message); Qt.quit();
            }
        }
    }
}
`);
        const qml = join(process.env.HOME, ".guix-home/profile/lib/qt6/qml");
        const result = spawnSync("qs", ["-p", join(root, "test.qml")], {
            encoding: "utf8", timeout: 10000,
            env: { ...process.env, QS_DISABLE_CRASH_HANDLER: "1", QT_QPA_PLATFORM: "wayland", QML_IMPORT_PATH: qml, QML2_IMPORT_PATH: qml }
        });
        const output = result.stdout + result.stderr;
        assert.equal(result.status, 0, output);
        assert.match(output, /SCREENSHOT-SAVE-PASS/);
        assert.doesNotMatch(output, /SCREENSHOT-SAVE-FAIL|TypeError|ReferenceError/);
        assert.equal(existsSync(source), false);
        assert.deepEqual(readFileSync(join(saved, name + ".png")), png);
        assert.deepEqual(readFileSync(join(cache, "collision")), png);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
