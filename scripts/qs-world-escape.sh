#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=${QS_ROOT:-$REPO}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-world-escape.XXXXXX")
probe_pid=""
cleanup() {
    if [[ -n $probe_pid ]]; then
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
    cat "$WORK/runtime.log" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/quickshell/qs" "$WORK/config" "$WORK/cache" "$WORK/state"
for entry in "$ROOT"/*; do ln -s "$entry" "$WORK/quickshell/qs/"; done
cp "$REPO/tests/burl-world-escape.qml" "$WORK/quickshell/qs/_escape.qml"
printf '%s\n' '{}' > "$WORK/defaults.json"
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$HOME/.guix-home/profile/lib/qt6/qml}
export QML2_IMPORT_PATH=${QML2_IMPORT_PATH:-$QML_IMPORT_PATH}
XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
BURL_DEFAULTS_FILE="$WORK/defaults.json" QT_QPA_PLATFORM=wayland \
    quickshell --no-color -p "$WORK/quickshell/qs/_escape.qml" > "$WORK/runtime.log" 2>&1 &
probe_pid=$!

wait_marker() {
    for ((attempt = 0; attempt < 150; attempt++)); do
        if grep -q "$1" "$WORK/runtime.log"; then return; fi
        if ! kill -0 "$probe_pid" 2>/dev/null; then return 1; fi
        sleep 0.05
    done
    echo "Missing marker: $1" >&2
    return 1
}

send_escape() {
    if [[ $(hyprctl -j activewindow | jq -r .pid) != "$probe_pid" ]]; then
        echo 'Probe is not focused; refusing keyboard injection' >&2
        return 1
    fi
    wtype -k Escape
}

wait_marker WORLD-ESCAPE-READY
[[ $(quickshell ipc --pid "$probe_pid" call worldEscape armCold) == armed ]]
send_escape
wait_marker WORLD-ESCAPE-COLD-PASS
quickshell ipc --pid "$probe_pid" call worldEscape armEditor
ready=false
for ((attempt = 0; attempt < 150; attempt++)); do
    if [[ $(quickshell ipc --pid "$probe_pid" call worldEscape editorReady) == true ]]; then
        ready=true
        break
    fi
    sleep 0.05
done
[[ $ready == true ]]
[[ $(quickshell ipc --pid "$probe_pid" call worldEscape focusEditor) == true ]]
send_escape
wait_marker WORLD-ESCAPE-EDITOR-PASS
quickshell ipc --pid "$probe_pid" call worldEscape armPlaylist
ready=false
for ((attempt = 0; attempt < 150; attempt++)); do
    if [[ $(quickshell ipc --pid "$probe_pid" call worldEscape playlistReady) == true ]]; then
        ready=true
        break
    fi
    sleep 0.05
done
[[ $ready == true ]]
[[ $(quickshell ipc --pid "$probe_pid" call worldEscape openPlaylist) == true ]]
send_escape
[[ $(quickshell ipc --pid "$probe_pid" call worldEscape playlistReturned) == true ]]
send_escape
[[ $(quickshell ipc --pid "$probe_pid" call worldEscape worldClosed) == true ]]
if grep -qE 'WORLD-ESCAPE-FAIL|TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop' "$WORK/runtime.log"; then
    exit 1
fi
echo 'PASS: Escape before readiness, in a child editor, and returning from a playlist'
