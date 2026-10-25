#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-popout-stacking.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
for room in launcher dashboard; do
    QS_DISABLE_CRASH_HANDLER=1 "$REPO/scripts/qs-shot.sh" \
        --root "${QS_ROOT:-$REPO}" --size 1280x900 --settle 4500 \
        --set "room: \"$room\"" --set 'marker: true' --log "$WORK/$room.log" \
        tests/PopoutStacking.qml "$WORK/$room.png"
    python3 - "$WORK/$room.log" "$WORK/$room.png" <<'PY'
import re
import subprocess
import sys

log = open(sys.argv[1]).read()
assert not re.search(r'POPOUT-FAIL|TypeError|ReferenceError|SyntaxError|Binding loop|Cannot assign', log), log
match = re.search(r'POPOUT-PROBE ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) (#[\da-f]{6})', log)
assert match, log
x, y, panel_x, panel_y, width, height = map(float, match.groups()[:6])
size = subprocess.check_output(['identify', '-format', '%w %h', sys.argv[2]], text=True).split()
scale_x, scale_y = int(size[0]) / 1280, int(size[1]) / 900

def pixels(x, y, width, height):
    crop = f'{round(width * scale_x)}x{round(height * scale_y)}+{round(x * scale_x)}+{round(y * scale_y)}'
    return subprocess.check_output(['convert', sys.argv[2], '-crop', crop, '-depth', '8', 'rgb:-'])

marker = pixels(x + 2, y + 2, 46, 96)
assert marker and all(marker[i:i + 3] == bytes([255, 0, 255]) for i in range(0, len(marker), 3)), 'Bark or scenery covers the popout'
base = bytes.fromhex(match.group(7)[1:])
fill = pixels(panel_x + width / 2, panel_y + 8, 10, 4)
# The opaque surface retains a low-opacity parchment grain.
assert fill and max(abs(value - base[i % 3]) for i, value in enumerate(fill)) <= 12, 'Popout background does not cover the scene'
print('PASS: popout clears bark and paints its opaque surface')
PY
done
