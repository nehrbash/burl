import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parent.parent
package = Path(sys.argv[1])
env = os.environ.copy()
wrapper = (package / "bin/burl-shell").read_text()
for key in ("QML_IMPORT_PATH", "QT_PLUGIN_PATH"):
    env[key] = re.search(r'export ' + key + r'="([^"$]+)', wrapper).group(1)
env["QML2_IMPORT_PATH"] = env["QML_IMPORT_PATH"]

with tempfile.TemporaryDirectory(prefix="burl-settings-test-") as directory:
    root = Path(directory)
    config = root / "config"
    (config / "burl").mkdir(parents=True)
    settings = config / "burl/shell.json"
    settings.write_text(json.dumps({"services": {"defaultPlayer": "Old preference"}}))
    data = root / "data"
    (data / "applications").mkdir(parents=True)
    (data / "applications/burl-test-file-manager.desktop").write_text(
        '[Desktop Entry]\nType=Application\nName=Burl test file manager\n'
        'Exec=sh --new-window %U\nCategories=FileManager;\n')
    probe = root / "source"
    probe.mkdir()
    for entry in source.iterdir():
        (probe / entry.name).symlink_to(entry)
    (probe / "Fixture.qml").write_text('''import QtQuick
import Quickshell
import Burl.Config
import qs.modules.nexus
import qs.modules.nexus.pages

Item {
    width: 800; height: 900
    readonly property var availableApps: DesktopEntries.applications.values
    function findRow(item, label) {
        if (item.label === label)
            return item;
        for (const child of item.children) {
            const found = findRow(child, label);
            if (found)
                return found;
        }
        return null;
    }
    NexusState { id: navigation }
    ServicesPage { id: services; nState: navigation; anchors.fill: parent }
    AppsPage { id: apps; nState: navigation; anchors.fill: parent; visible: false }
    Timer {
        interval: 300; running: true
        onTriggered: {
            const playerRow = findRow(services, "Default player");
            if (!playerRow) throw new Error("Default player row missing");
            const automatic = playerRow.menuItems.find(item => item.modelData === "");
            if (!automatic || automatic.text !== "Auto") throw new Error("Auto option missing");
            playerRow.selected(automatic);
            if (GlobalConfig.services.defaultPlayer !== "") throw new Error("Preference not cleared");
            const entry = availableApps.find(app => app.id === "burl-test-file-manager");
            if (!entry) throw new Error("Test desktop entry unavailable: " + DesktopEntries.applications.values.map(app => app.id).join(","));
            const explorerRow = findRow(apps, "File manager");
            if (!explorerRow) throw new Error("File manager row missing");
            explorerRow.selected(entry);
            if (GlobalConfig.general.apps.explorerDesktop !== "burl-test-file-manager" || GlobalConfig.general.apps.explorer.length !== 0)
                throw new Error("Desktop identity not preserved");
            explorerRow.selected(null);
            if (GlobalConfig.general.apps.explorerDesktop !== "" || GlobalConfig.general.apps.explorer.length !== 0)
                throw new Error("Desktop default did not clear the override");
            explorerRow.selected(entry);
            console.log("SETTINGS-PASS");
        }
    }
}
''')
    env.update(XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data), XDG_DATA_DIRS=str(data), BURL_DEFAULTS_FILE="")
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", str(probe), "--size", "800x900",
                    "--settle", "1800", "--log", str(root / "probe.log"),
                    "Fixture.qml", str(root / "probe.png")], cwd=source, env=env,
                   check=True, timeout=30)
    log = (root / "probe.log").read_text()
    assert "SETTINGS-PASS" in log, log
    saved = json.loads(settings.read_text())
    assert saved["services"]["defaultPlayer"] == "", "cleared preference was not saved"
    assert saved["general"]["apps"]["explorerDesktop"] == "burl-test-file-manager", "file manager was not saved"
    print("PASS: settings selections persist")
