#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=${QS_ROOT:-$REPO}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-atmosphere-cycle.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

for reduced in 0 1; do
    BURL_NO_AMBIENT=$reduced "$REPO/scripts/qs-shot.sh" \
        --root "$ROOT" --size 700x700 --settle 2100 \
        --decl "$REPO/tests/burl-moon-motion.qmlfrag" --set 'phase: 0.4' \
        components/widgets/LunarMoon.qml "$WORK/moon-$reduced.png"
    BURL_NO_AMBIENT=$reduced "$REPO/scripts/qs-shot.sh" \
        --root "$ROOT" --size 1280x720 --settle 2100 \
        --decl "$REPO/tests/burl-glass-motion.qmlfrag" \
        components/widgets/AstralGlass.qml "$WORK/glass-$reduced.png"
    BURL_NO_AMBIENT=$reduced "$REPO/scripts/qs-shot.sh" \
        --root "$ROOT" --size 1280x720 --settle 2100 \
        --decl "$REPO/tests/burl-scene-motion.qmlfrag" \
        components/widgets/AstralScene.qml "$WORK/scene-$reduced.png"
done

for scene in dream tree sky; do
    BURL_NO_AMBIENT=0 BURL_MOTION_CAPTURE="$WORK/$scene-motion" "$REPO/scripts/qs-shot.sh" \
        --root "$ROOT" --size 1280x720 --settle 4200 \
        --decl "$REPO/tests/burl-atmosphere.qmlfrag" --set "scene: \"$scene\"" \
        components/widgets/SpectralClouds.qml "$WORK/$scene.png"
    if cmp -s "$WORK/$scene-motion-a.png" "$WORK/$scene-motion-b.png"; then
        echo "FAIL: $scene clouds did not visibly move" >&2
        exit 1
    fi
done
BURL_NO_AMBIENT=1 BURL_MOTION_CAPTURE="$WORK/reduced-motion" "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1280x720 --settle 4200 \
    --decl "$REPO/tests/burl-atmosphere.qmlfrag" \
    components/widgets/SpectralClouds.qml "$WORK/reduced.png"
cmp "$WORK/reduced-motion-a.png" "$WORK/reduced-motion-b.png"
"$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 160x210 --settle 1900 \
    --decl "$REPO/tests/burl-owl-feedback.qmlfrag" \
    modules/bar/components/OsIcon.qml "$WORK/owl.png"

"$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 390x410 --settle 700 \
    --decl "$REPO/tests/burl-focus-timer.qmlfrag" \
    components/widgets/FocusTimerPanel.qml "$WORK/focus.png"
BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1280x720 --settle 4200 \
    --decl "$REPO/tests/burl-atmosphere.qmlfrag" --set 'spilling: true' \
    components/widgets/SpectralClouds.qml "$WORK/spilling.png"

BURL_NO_AMBIENT=0 QSG_RENDER_LOOP=threaded QSG_RENDER_TIMING=1 \
    "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1280x720 --settle 4000 \
    --decl "$REPO/tests/burl-scene-rendering.qmlfrag" --log "$WORK/rendering.log" \
    components/widgets/AstralScene.qml "$WORK/rendering.png"
awk '
    /SCENE-BLOCK-BEGIN/ { blocked = 1 }
    /SCENE-BLOCK-END/ { blocked = 0 }
    blocked && /frame rendered/ { frames++ }
    END { if (frames < 10) { print "FAIL: background stalled with the UI thread"; exit 1 } }
' "$WORK/rendering.log"
