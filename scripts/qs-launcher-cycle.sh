#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=${QS_ROOT:-$REPO}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-launcher-cycle.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

ARGS=(--root "$ROOT" --size 1280x720 --settle 12500
      --decl "$REPO/tests/burl-launcher-reopen.qmlfrag"
      --set 'screen: Quickshell.screens[0]'
      --set 'visibilities: host.cycleState'
      --set 'panels: ({})'
      modules/launcher/Wrapper.qml)

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" "${ARGS[@]}" "$WORK/normal.png"
BURL_NO_AMBIENT=1 "$REPO/scripts/qs-shot.sh" "${ARGS[@]}" "$WORK/reduced.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 6000 \
    --decl "$REPO/tests/burl-launcher-search.qmlfrag" \
    --set 'screen: Quickshell.screens[0]' \
    --set 'visibilities: host.cycleState' --set 'panels: ({})' \
    modules/launcher/Wrapper.qml "$WORK/search.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 41000 \
    --decl "$REPO/tests/burl-graph-idle.qmlfrag" \
    --set 'visibilities: host.cycleState' --set 'panels: ({})' \
    modules/launcher/Content.qml "$WORK/idle.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 41000 \
    --decl "$REPO/tests/burl-graph-interaction.qmlfrag" \
    --set 'visibilities: host.cycleState' \
    modules/launcher/GraphView.qml "$WORK/interaction.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 12000 \
    --decl "$REPO/tests/burl-graph-deferred.qmlfrag" \
    --set 'screen: Quickshell.screens[0]' \
    --set 'visibilities: host.cycleState' --set 'panels: ({})' \
    modules/launcher/Wrapper.qml "$WORK/deferred.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 41000 \
    --decl "$REPO/tests/burl-graph-resize.qmlfrag" \
    --set 'visibilities: host.cycleState' \
    modules/launcher/GraphView.qml "$WORK/resize.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1280x720 --settle 17000 \
    --log "$WORK/sky-controls.log" \
    --decl "$REPO/tests/burl-sky-controls.qmlfrag" \
    --set 'visibilities: host.cycleState' --set 'panels: ({})' \
    modules/launcher/Content.qml "$WORK/sky-controls.png"
if ! grep -q SKY-CONTROLS-COMPLETE "$WORK/sky-controls.log" || grep -q SKY-CONTROLS-FAIL "$WORK/sky-controls.log"; then
    cat "$WORK/sky-controls.log"
    exit 1
fi

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 9400 \
    --decl "$REPO/tests/burl-graph-drag.qmlfrag" \
    --set 'visibilities: host.cycleState' \
    modules/launcher/GraphView.qml "$WORK/drag.png"

BURL_NO_AMBIENT=0 "$REPO/scripts/qs-shot.sh" \
    --root "$ROOT" --size 1600x1000 --settle 26000 \
    --log "$WORK/rapid.log" \
    --decl "$REPO/tests/burl-launcher-rapid.qmlfrag" \
    --set 'screen: Quickshell.screens[0]' \
    --set 'visibilities: host.cycleState' --set 'panels: ({})' \
    modules/launcher/Wrapper.qml "$WORK/rapid.png"
if ! grep -q RAPID-PASS "$WORK/rapid.log" || grep -q RAPID-FAIL "$WORK/rapid.log"; then
    cat "$WORK/rapid.log"
    exit 1
fi
