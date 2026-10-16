#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export CAMERA_SOURCE_ROOT=${QS_ROOT:-$REPO}
export CAMERA_FIXTURE="$REPO/tests/burl-camera-motion.qml"
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$HOME/.guix-home/profile/lib/qt6/qml}
export QML2_IMPORT_PATH=${QML2_IMPORT_PATH:-$QML_IMPORT_PATH}
uv run --with pillow python - <<'PY'
import json, os, pathlib, re, subprocess, tempfile, time
from PIL import Image
root = pathlib.Path(os.environ['CAMERA_SOURCE_ROOT'])
artifacts = pathlib.Path(tempfile.mkdtemp(prefix='burl-camera-motion.'))
print('Camera artifacts:', artifacts, flush=True)
q = artifacts / 'quickshell/qs'
q.mkdir(parents=True)
for entry in root.iterdir(): (q / entry.name).symlink_to(entry)
(q / '_camera.qml').write_text(pathlib.Path(os.environ['CAMERA_FIXTURE']).read_text())
for directory in ['config', 'cache', 'state']: (artifacts / directory).mkdir()
env = dict(os.environ, QS_DISABLE_CRASH_HANDLER='1', QT_QPA_PLATFORM='wayland',
           QSG_RENDER_LOOP='threaded', QSG_RENDER_TIMING='1',
           QT_LOGGING_RULES='qt.scenegraph.time.renderloop=true',
           CAMERA_TEST_OUTPUT=str(artifacts), XDG_CONFIG_HOME=str(artifacts / 'config'),
           XDG_CACHE_HOME=str(artifacts / 'cache'), XDG_STATE_HOME=str(artifacts / 'state'))
def ipc(method, *args):
    return subprocess.check_output(['quickshell', 'ipc', '--pid', str(process.pid), 'call', 'cameraMotion', method, *args], text=True, timeout=4)
def capture(name):
    clients = json.loads(subprocess.check_output(['hyprctl', '-j', 'clients'], text=True))
    client = next(c for c in clients if c['pid'] == process.pid)
    x, y = client['at']; width, height = client['size']
    subprocess.run(['grim', '-g', f'{x},{y} {width}x{height}', str(artifacts / (name + '.png'))], check=True, timeout=4)
def saved(name):
    ipc('capture', name)
    until = time.monotonic() + 3
    while not (artifacts / (name + '.png')).exists():
        assert process.poll() is None and time.monotonic() < until, 'Capture failed: ' + name
        time.sleep(.01)
with (artifacts / 'runtime.log').open('w') as log_file:
    process = subprocess.Popen(['quickshell', '--no-color', '-p', str(q / '_camera.qml')], env=env,
                               stdout=log_file, stderr=subprocess.STDOUT)
    try:
        until = time.monotonic() + 4
        while 'CAMERA-READY' not in (artifacts / 'runtime.log').read_text():
            assert process.poll() is None and time.monotonic() < until, 'Probe startup failed'
            time.sleep(.02)
        time.sleep(.4)
        saved('initial')
        ipc('move')
        time.sleep(.2)
        blocker = subprocess.Popen(['quickshell', 'ipc', '--pid', str(process.pid), 'call', 'cameraMotion', 'blockGui'], stdout=subprocess.DEVNULL)
        time.sleep(.12)
        capture('during-block')
        assert blocker.wait(timeout=3) == 0
        capture('before-reversal')
        ipc('reverse')
        capture('after-reversal')
        time.sleep(.15)
        capture('after-reversal-later')
        time.sleep(8.2)
        saved('settled')
        ipc('move')
        time.sleep(.25)
        capture('before-disable')
        ipc('reduce')
        time.sleep(8.2)
        capture('disabled')
        ipc('snapReduced')
        saved('reduced')
        ipc('finish')
        code = process.wait(timeout=3)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=3)
log = (artifacts / 'runtime.log').read_text()
assert code == 0 and 'CAMERA-PASS' in log, log
assert not re.search(r'CAMERA-FAIL|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop', log), log
samples = {}
for name in ['initial', 'during-block', 'before-reversal', 'after-reversal', 'after-reversal-later', 'settled', 'before-disable', 'disabled', 'reduced']:
    im = Image.open(artifacts / (name + '.png')).convert('RGB')
    scale = im.width / 240
    points = [(x, y) for y in range(im.height) for x in range(im.width)
              if (lambda c: c[1] > 220 and c[0] < 20 and c[2] < 20)(im.getpixel((x, y)))]
    assert points, name + ': marker missing'
    samples[name] = {'y': sum(y for x, y in points) / len(points) / scale,
                     'red': im.getpixel((round(172 * scale), round(32 * scale)))[0]}
print(json.dumps(samples, indent=2), flush=True)
(artifacts / 'samples.json').write_text(json.dumps(samples, indent=2))
assert abs(samples['initial']['y'] - 31.5) < 3, samples
assert 33 < samples['during-block']['y'] < 200, samples
assert samples['before-reversal']['y'] > samples['during-block']['y'], samples
assert samples['before-reversal']['y'] < 200, samples
assert abs(samples['after-reversal']['y'] - samples['before-reversal']['y']) < 20, samples
assert 33 < samples['after-reversal-later']['y'] < samples['before-reversal']['y'] + 10, samples
assert abs(samples['settled']['y'] - 31.5) < 3, samples
assert 33 < samples['before-disable']['y'] < 200, samples
assert abs(samples['disabled']['y'] - 211.5) < 3, samples
assert abs(samples['reduced']['y'] - 191.5) < 3, samples
assert 55 <= samples['settled']['red'] <= 75, samples
assert 180 <= samples['reduced']['red'] <= 200, samples
blocked = log.split('CAMERA-BLOCK-BEGIN', 1)[1].split('CAMERA-BLOCK-END', 1)[0]
frames = [line for line in blocked.splitlines() if 'frame rendered' in line]
assert len(frames) >= 3, 'No independent render frames during GUI block:\n' + blocked
print('PASS: rendered motion during GUI block, continuous reversal, completion after midflight disable and reduced motion;', len(frames), 'blocked-GUI frames')
PY
