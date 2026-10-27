#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-popout-resize.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
QS_DISABLE_CRASH_HANDLER=1 "$REPO/scripts/qs-shot.sh" \
    --size 500x900 --settle 2500 --log "$WORK/runtime.log" \
    tests/PopoutResize.qml "$WORK/resize.png"
cat "$WORK/runtime.log"
if grep -qE 'Error:|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop' "$WORK/runtime.log"; then
    exit 1
fi
grep -q POPOUT-RESIZE-PASS "$WORK/runtime.log"
