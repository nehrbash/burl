import json
import os
from pathlib import Path
import re
import shlex
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

with tempfile.TemporaryDirectory(prefix="burl-theme-test-") as directory:
    root = Path(directory)
    config = root / "config/burl"
    config.mkdir(parents=True)
    keys = re.findall(r'check\("([^"]+)"\)', (source / "cli/burl/utils/theme.py").read_text())
    (config / "cli.json").write_text(json.dumps({"theme": dict.fromkeys(keys, False)}))
    (root / "bin").mkdir()
    cli = root / "bin/burl"
    cli.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + ' -m burl "$@"\n')
    cli.chmod(0o755)
    notification = root / "bin/notify-send"
    notification.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" > " + shlex.quote(str(root / "notification")) + "\n")
    notification.chmod(0o755)
    env.update(XDG_CONFIG_HOME=str(root / "config"), XDG_STATE_HOME=str(root / "state"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_DATA_HOME=str(root / "data"),
               PYTHONPATH=str(source / "cli"), PATH=str(root / "bin") + ":" + env["PATH"])
    subprocess.run([sys.executable, "-c",
                    "from burl.utils.scheme import get_scheme; get_scheme().select('gruvbox', 'medium', 'dark')"],
                   env=env, check=True)
    probe = root / "probe"
    probe.mkdir()
    for path in source.iterdir():
        (probe / path.name).symlink_to(path)
    (probe / "ThemeProbe.qml").write_text('''import QtQuick
import qs.components
import qs.services
import qs.modules.nexus.pages.wallandstyle
Item {
    property int phase: -1
    Loader {
        id: page
        anchors.fill: parent
        active: false
        sourceComponent: ColourSelect { nState: null }
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (parent.phase === -1) {
                if (Colours.scheme === "gruvbox") { Colours.setMode("light"); parent.phase = 0; }
                return;
            }
            if (Schemes.busy || Schemes.entries.length === 0) return;
            if (Schemes.error && parent.phase < 3) throw new Error(Schemes.error);
            if (parent.phase === 0) {
                if (!Colours.light) return;
                console.log("THEME-MODE-PASS");
                page.active = true;
                Schemes.select("catppuccin", "latte"); parent.phase++;
            } else if (parent.phase === 1 && Colours.scheme === "catppuccin" && Colours.light) {
                if (Woodland.ivory !== Colours.palette.m3onSurface) throw new Error("text ignored light palette");
                if (Woodland.velvet !== Colours.palette.m3surfaceContainer) throw new Error("surface ignored light palette");
                console.log("THEME-LIGHT-PASS");
                Schemes.select("nocturne", "default"); parent.phase++;
            } else if (parent.phase === 2 && Colours.scheme === "nocturne" && !Colours.light) {
                if (Woodland.brass !== Colours.palette.m3primary) throw new Error("accent ignored dark palette");
                if (Colours.palette.m3surface.toString() !== "#111319") throw new Error("wrong dark surface");
                console.log("THEME-DARK-PASS");
                Schemes.setMode("light");
                parent.phase++;
            } else if (parent.phase === 3 && Schemes.error) {
                if (Colours.scheme !== "nocturne" || Colours.light) throw new Error("failed mode changed palette");
                console.log("THEME-FAILURE-PASS");
                parent.phase++;
            }
        }
    }
}
''')
    log = root / "probe.log"
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", str(probe), "--size", "850x950",
                    "--settle", "6000", "--log", str(log), "ThemeProbe.qml", str(root / "result.png")],
                   cwd=source, env=env, check=True, timeout=30)
    output = log.read_text()
    assert all(marker in output for marker in ("THEME-MODE-PASS", "THEME-LIGHT-PASS", "THEME-DARK-PASS", "THEME-FAILURE-PASS")), output
    assert "Error:" not in output, output
    saved = json.loads((root / "state/burl/scheme.json").read_text())
    assert "has no light appearance" in (root / "notification").read_text()
    assert saved["name"] == "nocturne" and saved["mode"] == "dark", saved
    print("PASS: settings command → atomic save → file watcher → light/dark palette bindings")
