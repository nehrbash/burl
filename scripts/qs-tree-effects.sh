#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-tree-effects.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
BURL_NO_AMBIENT=0 QS_DISABLE_CRASH_HANDLER=1 "$REPO/scripts/qs-shot.sh" \
    --size 120x180 --settle 3500 --log "$WORK/runtime.log" \
    tests/TreeEffects.qml "$WORK/effects.png"
cat "$WORK/runtime.log"
if grep -qE 'TREE-EFFECTS-FAIL|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop' "$WORK/runtime.log"; then
    exit 1
fi
grep -q TREE-EFFECTS-PASS "$WORK/runtime.log"
