#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-world-lifecycle.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/config" "$WORK/cache" "$WORK/state"
printf '%s\n' '{}' > "$WORK/defaults.json"
XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
BURL_DEFAULTS_FILE="$WORK/defaults.json" BURL_NO_AMBIENT=0 \
    "$REPO/scripts/qs-shot.sh" --root "${QS_ROOT:-$REPO}" --size 1280x720 --settle 26000 \
    --log "$WORK/runtime.log" --decl "$REPO/tests/burl-world-lifecycle.qmlfrag" \
    --set 'screen: Quickshell.screens[0]' --set 'visibilities: host.cycleState' \
    --set 'panels: ({})' modules/launcher/Wrapper.qml "$WORK/world.png"
cat "$WORK/runtime.log"
if grep -qE 'WORLD-LIFECYCLE-FAIL|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop' "$WORK/runtime.log"; then
    exit 1
fi
grep -q WORLD-LIFECYCLE-PASS "$WORK/runtime.log"
XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
BURL_DEFAULTS_FILE="$WORK/defaults.json" BURL_NO_AMBIENT=0 \
    "$REPO/scripts/qs-shot.sh" --root "${QS_ROOT:-$REPO}" --size 1280x720 --settle 5500 \
    --log "$WORK/geometry.log" --decl "$REPO/tests/burl-world-geometry.qmlfrag" \
    --set 'screenState: host.cycleState' --set 'facePicker: null' \
    modules/dashboard/Content.qml "$WORK/geometry.png"
cat "$WORK/geometry.log"
if grep -qE 'WORLD-GEOMETRY-FAIL|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop' "$WORK/geometry.log"; then
    exit 1
fi
grep -q WORLD-GEOMETRY-PASS "$WORK/geometry.log"
echo 'PASS: cold close, room continuity, closing reversal and final cleanup'
