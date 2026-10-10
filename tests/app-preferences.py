import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parents[1]
package = Path(sys.argv[1])
env = os.environ.copy()
wrapper = (package / "bin/burl-shell").read_text()
for key in ("QML_IMPORT_PATH", "QT_PLUGIN_PATH"):
    env[key] = re.search(r'export ' + key + r'="([^"$]+)', wrapper).group(1)
path_prefix = re.search(r'export PATH="([^"$]+)', wrapper)
if path_prefix:
    env["PATH"] = path_prefix.group(1).rstrip(os.pathsep) + os.pathsep + env["PATH"]
env["QML2_IMPORT_PATH"] = env["QML_IMPORT_PATH"]

with tempfile.TemporaryDirectory(prefix="burl-app-preferences-") as directory:
    root = Path(directory)
    for name in ("config/burl", "data/applications", "state", "cache", "bin", "source"):
        (root / name).mkdir(parents=True)
    env.update(XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_DATA_DIRS=str(root / "data"), XDG_STATE_HOME=str(root / "state"),
               XDG_CACHE_HOME=str(root / "cache"), BURL_DEFAULTS_FILE="", BURL_EMACS_INTEGRATION="0")
    for name in ("player", "alacritty"):
        executable = root / "bin" / name
        executable.write_text(f"#!{sys.executable}\nimport json,sys\nfrom pathlib import Path\n"
                              f"Path({str(root / (name + '.json'))!r}).write_text(json.dumps(sys.argv[1:]))\n")
        executable.chmod(0o755)
    (root / "data/applications/test-player.desktop").write_text(
        f'[Desktop Entry]\nType=Application\nName=Test player\nExec={root}/bin/player --before %U --after\n')
    (root / "data/applications/Alacritty.desktop").write_text(
        f'[Desktop Entry]\nType=Application\nName=Test terminal\nExec={root}/bin/alacritty\n')
    settings = root / "config/burl/shell.json"
    settings.write_text(json.dumps({"general": {"apps": {
        "terminal": ["/gnu/store/db58wmj63hfdp136q3a3xajal8620yj0-alacritty-0.17.0/bin/alacritty"]}}}))
    file = root / "file with spaces.mp4"
    file.touch()
    probe = root / "source"
    for entry in source.iterdir():
        (probe / entry.name).symlink_to(entry)
    (probe / "Fixture.qml").write_text('''import QtQuick
import Quickshell
import Burl.Config
import qs.services
Item {
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            const entries = AppPreferences.entries;
            const terminal = entries.find(entry => entry.id === "Alacritty");
            const player = entries.find(entry => entry.id === "test-player");
            if (!terminal || !player) return;
            running = false;
            AppPreferences.migrate();
            if (GlobalConfig.general.apps.terminalDesktop !== "Alacritty") throw new Error("Legacy terminal not migrated");
            AppPreferences.select("playback", player);
            AppPreferences.open("playback", FILE);
            AppPreferences.launchTerminal(["child", "argument with spaces"], "");
            console.log("APP-PREFERENCES-PASS");
        }
    }
}
'''.replace("FILE", json.dumps(str(file))))
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", str(probe), "--size", "300x200",
                    "--settle", "2500", "--log", str(root / "probe.log"),
                    "Fixture.qml", str(root / "probe.png")], cwd=source, env=env, check=True, timeout=35)
    log = (root / "probe.log").read_text()
    assert "APP-PREFERENCES-PASS" in log, "App preferences did not finish before probe deadline:\n" + log
    player_args = json.loads((root / "player.json").read_text())
    assert player_args == ["--before", str(file), "--after"], player_args
    assert json.loads((root / "alacritty.json").read_text()) == ["-e", "child", "argument with spaces"]
    saved = json.loads(settings.read_text())["general"]["apps"]
    assert saved["terminalDesktop"] == "Alacritty"
    assert saved["playbackDesktop"] == "test-player"
    assert saved.get("terminal", []) == []
    print("PASS: desktop field codes, file arguments, and migrated terminal execution")
