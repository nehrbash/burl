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
        if (EmacsSources.stateDb !== "" || EmacsSources.roamDb !== "") throw new Error("personal databases enabled by default");
    }
}
''')
    env.update(XDG_CONFIG_HOME=directory, BURL_DEFAULTS_FILE=str(defaults),
               BURL_EMACS_STATE_DB="", BURL_ORG_ROAM_DB="")
    subprocess.run(["bash", "scripts/qs-smoke.sh", "--root", directory, "Fixture.qml"],
                   cwd=Path(__file__).resolve().parent.parent, env=env,
                   check=True, timeout=30)
    assert before == settings.read_bytes(), "loading defaults changed user settings"
