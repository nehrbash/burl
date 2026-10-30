import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

test("plugin service applies preferences, restores paused plugins and reports failure", { skip: process.env.RUN_QML_PLUGINS !== "1" }, () => {
    const dir = mkdtempSync(join(tmpdir(), "burl-plugins-"));
    try {
        const root = join(dir, "quickshell", "qs");
        const services = join(root, "services");
        const fixture = join(root, "fixture");
        for (const path of [services, fixture, join(dir, "bin"), join(dir, ".config", "hypr")])
            mkdirSync(path, { recursive: true });
        copyFileSync(new URL("../services/HyprlandPluginPolicy.js", import.meta.url), join(services, "HyprlandPluginPolicy.js"));
        writeFileSync(join(services, "HyprlandPlugins.qml"), readFileSync(new URL("../services/HyprlandPlugins.qml", import.meta.url), "utf8")
            .replace("import Quickshell.Services.UPower", "import qs.fixture").replace("import Burl.Config", ""));
        writeFileSync(join(services, "Hypr.qml"), "pragma Singleton\nimport QtQuick\nQtObject { signal configReloaded() }\n");
        writeFileSync(join(fixture, "GlobalConfig.qml"), "pragma Singleton\nimport QtQuick\nQtObject { property var hyprlandPlugins: ({}) }\n");
        writeFileSync(join(fixture, "PowerProfile.qml"), "pragma Singleton\nimport QtQuick\nQtObject { enum Profile { Balanced, Performance } }\n");
        writeFileSync(join(fixture, "PowerProfiles.qml"), "pragma Singleton\nimport QtQuick\nQtObject { property int profile: 0 }\n");
        writeFileSync(join(dir, ".config", "hypr-plugins.lua"), 'return { "/plugins/mist.so", "/plugins/bad.so" }\n');
        writeFileSync(join(dir, "actual.json"), JSON.stringify(["mist"]));
        const python = spawnSync("which", ["python3"], { encoding: "utf8" }).stdout.trim();
        writeFileSync(join(dir, "bin", "hyprctl"), `#!${python}
import json, os, pathlib, sys
root = pathlib.Path(os.environ['PLUGIN_TEST_DIR'])
path = root / 'actual.json'
state = json.loads(path.read_text())
args = sys.argv[1:]
if args == ['-j', 'plugin', 'list']:
    print(json.dumps([dict(name=name) for name in state]))
elif args[0] == 'plugin':
    name = pathlib.Path(args[2]).stem
    desired = args[1] == 'load'
    setting = '["' + name + '"] = ' + str(desired).lower()
    assert setting in (root / '.config/hypr/plugins-generated.lua').read_text()
    if name == 'bad' and desired:
        print('fixture refused plugin')
        sys.exit(1)
    if desired and name not in state: state.append(name)
    if not desired and name in state: state.remove(name)
    path.write_text(json.dumps(state))
elif args != ['reload']:
    sys.exit(1)
`, { mode: 0o755 });
        writeFileSync(join(root, "test.qml"), `import QtQuick
import Quickshell
import qs.services
import qs.fixture
ShellRoot {
    id: root
    settings.watchFiles: false
    property var service: HyprlandPlugins
    property int step: 0
    property int ticks: 0
    function check(value, text) { if (!value) throw new Error(text); }
    Timer {
        interval: 40; repeat: true; running: true
        onTriggered: {
            try {
                if (++root.ticks > 200) throw new Error("fixture timed out: " + root.step + " " + HyprlandPlugins.operation + " " + HyprlandPlugins.busy + " " + HyprlandPlugins.ready + " " + HyprlandPlugins.error);
                if (!HyprlandPlugins.ready || HyprlandPlugins.busy) return;
                const mist = HyprlandPlugins.plugins[0];
                const bad = HyprlandPlugins.plugins[1];
                if (root.step === 0) {
                    check(mist.loaded && !bad.loaded, "initial state preserved");
                    HyprlandPlugins.setChoice(mist, "disableInPerformance", true);
                    root.step++;
                } else if (root.step === 1) {
                    check(mist.loaded, "preference alone preserves loaded state");
                    PowerProfiles.profile = PowerProfile.Performance;
                    root.step++;
                } else if (root.step === 2) {
                    check(!mist.loaded && mist.enabled && mist.paused, "performance pauses plugin");
                    PowerProfiles.profile = PowerProfile.Balanced;
                    root.step++;
                } else if (root.step === 3) {
                    check(mist.loaded && !mist.paused, "balanced restores plugin");
                    HyprlandPlugins.setChoice(mist, "enabled", false);
                    root.step++;
                } else if (root.step === 4) {
                    check(!mist.loaded && !mist.enabled, "user disables plugin");
                    Hypr.configReloaded();
                    root.step++;
                } else if (root.step === 5) {
                    check(!mist.loaded, "reload retains disabled choice");
                    HyprlandPlugins.setChoice(bad, "enabled", true);
                    root.step++;
                } else if (root.step === 6) {
                    check(!bad.loaded && HyprlandPlugins.error.length > 0, "failure reported with actual state");
                    console.log("PLUGINS-RUNTIME-PASS");
                    Qt.quit();
                }
            } catch (error) {
                console.error("PLUGINS-RUNTIME-FAIL", error.message);
                Qt.quit();
            }
        }
    }
}
`);
        const result = spawnSync("quickshell", ["--no-color", "-p", join(root, "test.qml")], {
            encoding: "utf8", timeout: 15000,
            env: { ...process.env, HOME: dir, PATH: join(dir, "bin") + ":" + process.env.PATH,
                PLUGIN_TEST_DIR: dir, QT_QPA_PLATFORM: "offscreen", QS_DISABLE_CRASH_HANDLER: "1" }
        });
        const output = result.stdout + result.stderr;
        assert.equal(result.status, 0, output);
        assert.match(output, /PLUGINS-RUNTIME-PASS/);
        assert.doesNotMatch(output, /PLUGINS-RUNTIME-FAIL|TypeError|ReferenceError/);
        assert.match(readFileSync(join(dir, ".config/hypr/plugins-generated.lua"), "utf8"), /\["mist"\] = false/);
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});
