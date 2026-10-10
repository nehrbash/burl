#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-files.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/files"
touch "$WORK/files/Alpha report.org" "$WORK/files/Beta report.txt" "$WORK/files/other.txt" "$WORK/files/.hidden-report.org"
cat > "$WORK/delayed" <<'SCM'
#!/usr/bin/env -S guile -s
!#
(sleep 1)
(display "{\"entries\":[{\"path\":\"/tmp/delayed\",\"label\":\"delayed\",\"queries\":[\"delayed\"]}],\"error\":\"\",\"truncated\":false}")
SCM
chmod +x "$WORK/delayed"
PATH="$REPO/bin:$PATH" GUILE_AUTO_COMPILE=0 \
BURL_FILE_SEARCH_ROOT="$WORK/files" BURL_FILE_SEARCH_SLOW_FIXTURE="$WORK/delayed" \
    "$REPO/scripts/qs-shot.sh" --root "${QS_ROOT:-$REPO}" \
    --size 1600x1000 --settle 23000 --log "$WORK/native.log" \
    --decl "$REPO/tests/burl-file-search.qmlfrag" \
    --set 'visibilities: host.cycleState' --set 'panels: ({})' \
    modules/launcher/Content.qml "$WORK/native.png"
if ! grep -q FILES-PASS "$WORK/native.log" || grep -q FILES-FAIL "$WORK/native.log"; then
    cat "$WORK/native.log"
    exit 1
fi
echo 'PASS: native file search, regex, startup failure and cancellation'
