import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parents[1]
package = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".guix-home/profile"
env = os.environ.copy()
wrapper = (package / "bin/burl-shell").read_text()
for key in ("QML_IMPORT_PATH", "QT_PLUGIN_PATH"):
    env[key] = re.search(r'export ' + key + r'="([^"$]+)', wrapper).group(1)
env["QML2_IMPORT_PATH"] = env["QML_IMPORT_PATH"]

with tempfile.TemporaryDirectory(prefix="burl-controls-test-") as directory:
    root = Path(directory)
    for name in ("config/burl", "data", "state", "cache", "bin"):
        (root / name).mkdir(parents=True)
    settings = root / "config/burl/shell.json"
    settings.write_text(json.dumps({"dashboard": {"navStyle": "living"},
                                   "services": {"weatherLocation": "999,999"}}))
    nmcli = root / "bin/nmcli"
    nmcli.write_text('#!/bin/sh\ncase "$*" in "radio wifi") echo disabled;; esac\n')
    nmcli.chmod(0o755)
    for name, body in {
        "guix-channel-status": "echo '{\"channels\":[]}'",
        "burl-test-action": 'exit "$1"',
        "guix": "exit 93",
    }.items():
        command = root / "bin" / name
        command.write_text("#!/bin/sh\n" + body + "\n")
        command.chmod(0o755)
    env.update(XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
               BURL_DEFAULTS_FILE="", BURL_EMACS_INTEGRATION="0", LC_ALL="C",
               PATH=str(root / "bin") + os.pathsep + env["PATH"])
    probe = root / "source"
    probe.mkdir()
    for entry in source.iterdir():
        (probe / entry.name).symlink_to(entry)
    (probe / "ControlsProbe.qml").write_text('''import QtQuick
import Quickshell
import Burl.Config
import qs.components
import qs.modules.launcher
import qs.modules.nexus
import qs.modules.nexus.pages
import qs.modules.nexus.pages.panels
import qs.services
Item {
    id: root
    property int phase: 0
    property var outcomes: []
    Connections {
        target: Guix
        function onActionFinished(id, ok, exitCode) {
            root.outcomes.push({id, ok, exitCode});
        }
    }
    function find(item, key, value) {
        if (item[key] === value) return item;
        for (const child of item.children) {
            const result = find(child, key, value);
            if (result) return result;
        }
        return null;
    }
    function require(value, message) { if (!value) throw new Error(message); }
    NexusState { id: navigation }
    DashboardPanel { id: dashboard; anchors.fill: parent; nState: navigation }
    NetworkPage { id: network; anchors.fill: parent; nState: navigation; visible: false }
    LanguageAndRegion { id: language; anchors.fill: parent; nState: navigation; visible: false }
    ScreenState { id: graphState; modelData: Quickshell.screens[0] }
    GraphView { id: graph; visibilities: graphState; width: 640; height: 480; visible: false; transitioning: true }
    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            const hover = root.find(dashboard, "text", "Show on hover");
            const threshold = root.find(dashboard, "label", "Drag threshold");
            const enabled = root.find(dashboard, "text", "Enabled");
            root.require(hover && threshold && enabled, "Dashboard controls missing");
            if (root.phase === 0) {
                GlobalConfig.launcher.maxWallpapers = 3;
                root.require(!hover.visible && !threshold.visible && enabled.last,
                             "Living dashboard exposes edge controls or broken grouping");
                root.require(!root.find(network, "text", "Add network"), "Inert network control remains");
                const clock = root.find(language, "label", "Clock format");
                root.require(clock, "Clock control missing");
                clock.selected(clock.menuItems[1]);
                root.require(GlobalConfig.services.useTwelveHourClock, "Clock selection was not applied");
                GlobalConfig.dashboard.navStyle = "classic";
                root.phase = 1;
            } else if (root.phase === 1) {
                root.require(graph.maxWallpapers === 3 && graph.rebuildPending,
                             "Wallpaper limit did not reach the graph");
                GlobalConfig.launcher.maxWallpapers = 7;
                root.require(hover.visible && threshold.visible && !enabled.last,
                             "Classic dashboard has no edge controls or broken grouping");
                hover.checked = false;
                hover.toggled();
                threshold.moved(85);
                root.require(!GlobalConfig.dashboard.showOnHover && GlobalConfig.dashboard.dragThreshold === 85,
                             "Dashboard controls did not apply preferences");
                GlobalConfig.dashboard.navStyle = "living";
                root.phase = 2;
            } else if (root.phase === 2) {
                root.require(graph.maxWallpapers === 7 && graph.rebuildPending,
                             "Wallpaper limit did not update reactively");
                root.require(!hover.visible && !threshold.visible && enabled.last,
                             "Returning to living leaves edge controls exposed");
                Guix.runAction({id: "missing", command: ["/burl-test-no-such-executable"]});
                root.phase = 3;
            } else if (root.phase >= 3 && root.phase <= 5) {
                if (Guix.runningAction) return;
                const expected = root.phase - 2;
                root.require(root.outcomes.length === expected, "Missing or duplicate action completion");
                const outcome = root.outcomes[expected - 1];
                const ids = ["missing", "success", "nonzero"];
                root.require(outcome.id === ids[expected - 1], "Wrong action completed");
                root.require(outcome.ok === (expected === 2), "Wrong action success status");
                root.require(expected !== 3 || outcome.exitCode === 7, "Exit code not preserved");
                if (expected < 3)
                    Guix.runAction({id: ids[expected], command: ["burl-test-action", expected === 1 ? "0" : "7"]});
                else {
                    console.log("CONTROLS-PASS");
                    running = false;
                }
                root.phase++;
            }
        }
    }
}
''')
    log = root / "probe.log"
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", str(probe), "--size", "850x950",
                    "--settle", "4200", "--log", str(log), "ControlsProbe.qml", str(root / "probe.png")],
                   cwd=source, env=env, check=True, timeout=35)
    output = log.read_text()
    assert "CONTROLS-PASS" in output, output
    assert not re.search(r"Error:|Unable to assign|Cannot assign|Binding loop", output), output
    saved = json.loads(settings.read_text())
    assert saved["services"]["useTwelveHourClock"] is True, saved
    assert saved["dashboard"]["showOnHover"] is False, saved
    assert saved["dashboard"]["dragThreshold"] == 85, saved
    assert saved["dashboard"].get("navStyle", "living") == "living", saved
    print("PASS: controls persist, wallpaper limits reach the graph, and Guix commands finish")
