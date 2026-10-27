#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-monitor-focus.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
QS_DISABLE_CRASH_HANDLER=1 "$REPO/scripts/qs-shot.sh" \
    --size 100x120 --log "$WORK/runtime.log" \
    tests/MonitorFocus.qml "$WORK/focus.png"
cat "$WORK/runtime.log"
if grep -qE 'Error:|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop' "$WORK/runtime.log"; then
    exit 1
fi
grep -q MONITOR-FOCUS-PASS "$WORK/runtime.log"
