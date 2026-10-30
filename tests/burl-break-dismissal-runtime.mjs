import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readdirSync, symlinkSync, copyFileSync, rmSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("break dismissal survives unavailable Emacs and stale snapshots", {
    skip: process.env.RUN_QML_TASKS !== "1"
}, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-break-"));
    try {
        const repo = fileURLToPath(new URL("../", import.meta.url));
        const root = join(dir, "quickshell", "qs");
        mkdirSync(root, { recursive: true });
        for (const name of readdirSync(repo))
            symlinkSync(join(repo, name), join(root, name));
        const probe = join(root, "_break.qml");
        copyFileSync(new URL("./burl-break-dismissal.qml", import.meta.url), probe);
        const result = spawnSync("quickshell", ["--no-color", "-p", probe], {
            encoding: "utf8", timeout: 15000,
            env: { ...process.env,
                BURL_EMACS_INTEGRATION: "0", QS_DISABLE_CRASH_HANDLER: "1",
                QML_IMPORT_PATH: process.env.QML_IMPORT_PATH || join(homedir(), ".guix-home/profile/lib/qt6/qml"),
                XDG_CONFIG_HOME: join(dir, "config"), XDG_CACHE_HOME: join(dir, "cache"),
                XDG_STATE_HOME: join(dir, "state")
            }
        });
        const output = result.stdout + result.stderr;
        assert.equal(result.status, 0, output);
        assert.match(output, /BREAK-DISMISS-PASS/);
        assert.doesNotMatch(output, /BREAK-DISMISS-FAIL/);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
