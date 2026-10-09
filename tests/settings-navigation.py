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

with tempfile.TemporaryDirectory(prefix="burl-navigation-test-") as directory:
    root = Path(directory)
    for name in ("config", "data", "state", "cache"):
        (root / name).mkdir()
    env.update(XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
               BURL_DEFAULTS_FILE="", BURL_EMACS_INTEGRATION="0")
    probe = root / "source"
    probe.mkdir()
    for path in source.iterdir():
        (probe / path.name).symlink_to(path)
    (probe / "NavigationProbe.qml").write_text('''import QtQuick
import Quickshell
import qs.modules.nexus
Item {
    id: root
    property int phase: 0
    property int changes: 0
    property int settled: 0
    NexusState { id: navigation; screen: Quickshell.screens[0]; currentPageId: "apps" }
    Pages { id: pages; anchors.fill: parent; nState: navigation }
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            if (root.phase === 0) {
                if (!pages.currentItem || !pages.currentItem.currentItem) return;
                navigation.openSubPage(1);
                if (navigation.subPageIdxStack.length !== 1) throw new Error("Subpage history missing");
                root.phase = 1;
            } else if (root.phase === 1) {
                const ids = ["services", "panels", "apps", "language"];
                navigation.currentPageId = ids[root.changes % ids.length];
                if (navigation.subPageIdxStack.length !== 0) throw new Error("Subpage history survived selection");
                root.changes++;
                if (root.changes === 20) {
                    pages.loadPage("apps");
                    pages.loadPage("language");
                    root.phase = 2;
                }
            } else if (root.phase === 2) {
                root.settled++;
                if (root.settled < 100) return;
                const page = pages.currentItem;
                if (navigation.currentPageId !== "language") throw new Error("Wrong selected ID");
                if (!page || !page.currentItem || page.currentItem.title !== "Language & region")
                    throw new Error("Selected page did not settle");
                const container = page.parent;
                if (container.children.length !== 1 || container.children[0] !== page)
                    throw new Error("Obsolete pages retained: " + container.children.length);
                if (!page.visible || container.opacity !== 1 || container.anchors.topMargin !== 0)
                    throw new Error("Transition did not settle visibly");
                console.log("NAVIGATION-PASS");
                root.phase = 3;
                running = false;
            }
        }
    }
}
''')
    log = root / "probe.log"
    subprocess.run(["bash", "scripts/qs-shot.sh", "--root", str(probe), "--size", "850x950",
                    "--settle", "6500", "--log", str(log), "NavigationProbe.qml", str(root / "probe.png")],
                   cwd=source, env=env, check=True, timeout=35)
    output = log.read_text()
    assert "NAVIGATION-PASS" in output, output
    assert "Error:" not in output, output
    print("PASS: rapid native page changes reset subpages and retain only the final visible page")
