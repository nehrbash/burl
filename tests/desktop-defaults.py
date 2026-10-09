import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

package = Path(sys.argv[1])
env = os.environ.copy()
wrapper = (package / "bin/burl-shell").read_text()
for key in ("QML_IMPORT_PATH", "QT_PLUGIN_PATH"):
    env[key] = re.search(r'export ' + key + r'="([^"$]+)', wrapper).group(1)

env["QML2_IMPORT_PATH"] = env["QML_IMPORT_PATH"]

with tempfile.TemporaryDirectory(prefix="burl-defaults-test-") as directory:
    root = Path(directory)
    (root / "burl").mkdir()
    defaults = root / "defaults.json"
    defaults.write_text(json.dumps({"general": {"apps": {
        "terminal": ["desktop-default"], "explorer": ["default-explorer"]}}}))
    settings = root / "burl/shell.json"
    settings.write_text(json.dumps({"general": {"apps": {"terminal": ["user-choice"]}}}))
    before = settings.read_bytes()
    (root / "Fixture.qml").write_text('''import QtQuick
import Burl.Config
import Burl
Item {
    width: 10; height: 10
    Component.onCompleted: {
        if (GlobalConfig.general.apps.terminal[0] !== "user-choice") throw new Error("user override lost");
        if (GlobalConfig.general.apps.explorer[0] !== "default-explorer") throw new Error("desktop defaults missing");
        if (GlobalConfig.session.commands.windows.length !== 0) throw new Error("host boot action enabled by default");
        console.log("DEFAULTS-PASS");
        if (EmacsSources.stateDb !== "" || EmacsSources.roamDb !== "") throw new Error("personal databases enabled by default");
    }
}
''')
    env.update(XDG_CONFIG_HOME=directory, BURL_DEFAULTS_FILE=str(defaults),
               BURL_EMACS_STATE_DB="", BURL_ORG_ROAM_DB="")
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", directory, "--size", "10x10",
                    "--settle", "1200", "--log", str(root / "probe.log"), "Fixture.qml", str(root / "result.png")],
                   cwd=Path(__file__).resolve().parent.parent, env=env,
                   check=True, timeout=30)
    log = (root / "probe.log").read_text()
    assert "DEFAULTS-PASS" in log and "Error:" not in log, log
    assert before == settings.read_bytes(), "loading defaults changed user settings"
    fixture = root / "Fixture.qml"
    fixture.write_text(fixture.read_text().replace("width: 10; height: 10", """width: 10; height: 10
    Timer { interval: 300; running: true; onTriggered: GlobalConfig.general.apps.terminal = ["edited-choice"] }"""))
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", directory, "--size", "10x10",
                    "--settle", "1600", "Fixture.qml", str(root / "edited.png")],
                   cwd=Path(__file__).resolve().parent.parent, env=env,
                   check=True, timeout=30)
    assert json.loads(settings.read_text())["general"]["apps"]["terminal"] == ["edited-choice"], "user edits were not saved"

    settings.unlink()
    fixture.write_text(fixture.read_text().replace('!== "user-choice"', '!== "desktop-default"'))
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", directory, "--size", "10x10",
                    "--settle", "1600", "--log", str(root / "fresh.log"),
                    "Fixture.qml", str(root / "fresh.png")],
                   cwd=Path(__file__).resolve().parent.parent, env=env,
                   check=True, timeout=30)
    log = (root / "fresh.log").read_text()
    assert "DEFAULTS-PASS" in log and "Error:" not in log, log
    apps = json.loads(settings.read_text())["general"]["apps"]
    assert apps["terminal"] == ["edited-choice"], "first edit was not saved"
    assert "explorer" not in apps, "desktop defaults became user overrides"
