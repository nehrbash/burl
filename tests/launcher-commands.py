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
env["QML2_IMPORT_PATH"] = env["QML_IMPORT_PATH"]

with tempfile.TemporaryDirectory(prefix="burl-command-editor-") as directory:
    root = Path(directory)
    for name in ("config/burl", "data", "state", "cache"):
        (root / name).mkdir(parents=True)
    settings = root / "config/burl/shell.json"
    builtin = {"name": "Wallpaper", "command": ["autocomplete", "wallpaper"], "icon": "image", "extra": "preserved"}
    settings.write_text(json.dumps({"launcher": {"actions": [builtin]}}))
    env.update(XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
               BURL_DEFAULTS_FILE="", BURL_EMACS_INTEGRATION="0")
    probe = root / "source"
    probe.mkdir()
    for entry in source.iterdir():
        (probe / entry.name).symlink_to(entry)
    fixture = '''import QtQuick
import Quickshell
import Burl.Config
import qs.modules.nexus
import qs.modules.nexus.pages.panels
Item {
    id: root
    width: 800; height: 1000
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const result = find(child, name);
            if (result) return result;
        }
        return null;
    }
    function require(value, message) { if (!value) throw new Error(message); }
    NexusState { id: navigation }
    LauncherPanel { id: panel; nState: navigation; anchors.fill: parent }
    Timer {
        interval: 500; running: true
        onTriggered: {
            const editor = find(panel, "commandEditor");
            require(editor, "editor missing");
            const field = name => find(editor, name);
            BODY
            console.log("COMMAND-EDITOR-PASS");
        }
    }
}
'''
    edit = r'''
            editor.begin(0);
            require(!field("commandAcceptArgs").enabled, "internal operation accepts extra args");
            field("commandDescription").text = "Pick a wallpaper";
            require(editor.save(), editor.error);
            require(GlobalConfig.launcher.actions[0].extra === "preserved", "unknown field dropped");
            require(GlobalConfig.launcher.actions[0].command.join("|") === "autocomplete|wallpaper", "internal argv changed");
            editor.begin(-1);
            field("commandName").text = "Print note";
            field("commandExecutable").text = "printf";
            field("commandKeyword").text = "file";
            require(!editor.save(), "reserved keyword accepted");
            field("commandKeyword").text = "Wallpaper";
            require(!editor.save(), "duplicate keyword accepted");
            field("commandKeyword").text = "print-note";
            field("commandArguments").text = '"unfinished';
            require(!editor.save(), "invalid quoting accepted");
            field("commandArguments").text = '"a b" "" "$HOME"';
            field("commandDescription").text = "Print a note without a shell";
            field("commandAcceptArgs").checked = true;
            require(editor.save(), editor.error);
            require(GlobalConfig.launcher.actions.length === 2, "add failed");
            const action = GlobalConfig.launcher.actions[1];
            require(JSON.stringify(action.command) === JSON.stringify(["printf", "a b", "", "$HOME"]), "argv changed");
            editor.begin(1);
            field("commandName").text = "Cancelled edit";
            editor.editing = false;
            require(GlobalConfig.launcher.actions[1].name === "Print note", "cancel changed config");
            editor.begin(-1);
            field("commandName").text = "Temporary";
            field("commandKeyword").text = "temporary";
            field("commandExecutable").text = "printf";
            require(editor.save(), editor.error);
            editor.begin(2);
            require(editor.remove(), "delete failed");
            require(GlobalConfig.launcher.actions.length === 2, "delete count");
    '''
    reload = '''
            require(GlobalConfig.launcher.actions.length === 2, "actions not restored");
            editor.begin(1);
            require(field("commandName").text === "Print note", "name not restored");
            require(field("commandKeyword").text === "print-note", "keyword not restored");
            require(field("commandAcceptArgs").checked, "extra-args preference not restored");
            require(editor.save(), editor.error);
            require(GlobalConfig.launcher.actions[1].command[3] === "$HOME", "argv roundtrip expanded a variable");
    '''
    for phase, body in [("edit", edit), ("reload", reload)]:
        (probe / "CommandProbe.qml").write_text(fixture.replace("BODY", body))
        logfile = root / (phase + ".log")
        subprocess.run(["bash", "scripts/qs-shot.sh", "--root", str(probe), "--size", "800x1000",
                        "--settle", "2200", "--log", str(logfile),
                        "CommandProbe.qml", str(root / (phase + ".png"))],
                       cwd=source, env=env, check=True, timeout=35)
        log = logfile.read_text()
        assert "COMMAND-EDITOR-PASS" in log, log
        assert not re.search(r"(?:ReferenceError|TypeError|SyntaxError):", log), log
    saved = json.loads(settings.read_text())["launcher"]["actions"]
    assert saved[0]["extra"] == "preserved"
    assert saved[1]["command"] == ["printf", "a b", "", "$HOME"]
    print("PASS: command editor add/edit/delete, validation, cancellation and restart persistence")
