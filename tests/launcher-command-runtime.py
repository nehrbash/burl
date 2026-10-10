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
wrapper = (package / 'bin/burl-shell').read_text()
for key in ('QML_IMPORT_PATH', 'QT_PLUGIN_PATH'):
    env[key] = re.search(r'export ' + key + r'="([^"$]+)', wrapper).group(1)
env['QML2_IMPORT_PATH'] = env['QML_IMPORT_PATH']
with tempfile.TemporaryDirectory(prefix='burl-command-runtime-') as directory:
    root = Path(directory)
    for name in ('config/burl', 'data', 'state', 'cache'):
        (root / name).mkdir(parents=True)
    capture = root / 'argv.json'
    program = 'import json,sys; from pathlib import Path; Path(' + repr(str(capture)) + ').write_text(json.dumps(sys.argv[1:]))'
    actions = [
        {'name': 'Capture', 'keyword': 'capture', 'description': 'Record arbitrary argument words',
         'command': [sys.executable, '-c', program, 'fixed'], 'acceptArgs': True},
        {'name': 'Closed', 'keyword': 'closed', 'command': ['/missing-not-executed'], 'acceptArgs': False},
        {'name': 'Danger', 'keyword': 'poweroff', 'command': ['/missing-not-executed'], 'dangerous': True},
        {'name': 'Calculator', 'command': ['autocomplete', 'calc']},
    ]
    (root / 'config/burl/shell.json').write_text(json.dumps({'launcher': {'actions': actions, 'enableDangerousActions': False}}))
    env.update(XDG_CONFIG_HOME=str(root / 'config'), XDG_DATA_HOME=str(root / 'data'),
               XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'),
               BURL_DEFAULTS_FILE='', BURL_EMACS_INTEGRATION='0')
    probe = root / 'source'
    probe.mkdir()
    for entry in source.iterdir():
        (probe / entry.name).symlink_to(entry)
    fixture = '''import QtQuick
import Quickshell
import qs.modules.launcher.services
Item {
    id: root
    property var field: ({text: ""})
    property var visibility: ({launcher: true, dashboard: false})
    function require(value, label) { if (!value) throw new Error(label); }
    Timer {
        interval: 600; running: true
        onTriggered: {
            require(Actions.query(">poweroff").length === 0, "dangerous action is visible");
            require(Actions.query(">arbitrary")[0]?.keyword === "capture", "description lookup failed");
            const action = Actions.query(">capture")[0];
            require(action, "capture command not found");
            root.field.text = '>capture "unfinished';
            action.activate(root.field, root.visibility);
            require(root.visibility.launcher, "invalid args closed launcher");
            root.field.text = '>closed ignored';
            Actions.query(root.field.text)[0].activate(root.field, root.visibility);
            require(root.visibility.launcher, "disabled args closed launcher");
            root.field.text = '>calculator';
            Actions.query(root.field.text)[0].activate(root.field, root.visibility);
            require(root.field.text === '>calc ', "built-in autocomplete failed");
            root.field.text = QUERY;
            action.activate(root.field, root.visibility);
            require(!root.visibility.launcher, "command did not close launcher");
            console.log("COMMAND-RUNTIME-PASS");
        }
    }
}
'''
    query = '>capture "two words" "" "$HOME" "$(literal)" --flag'
    (probe / 'RuntimeProbe.qml').write_text(fixture.replace('QUERY', json.dumps(query)))
    log = root / 'native.log'
    subprocess.run(['bash', 'scripts/qs-shot.sh', '--root', str(probe), '--size', '800x600',
                    '--settle', '2200', '--log', str(log), 'RuntimeProbe.qml', str(root / 'native.png')],
                   cwd=source, env=env, check=True, timeout=30)
    assert 'COMMAND-RUNTIME-PASS' in log.read_text(), log.read_text()
    assert json.loads(capture.read_text()) == ['fixed', 'two words', '', '$HOME', '$(literal)', '--flag']
    print('PASS: native command lookup, error handling, built-ins and literal argument execution')
