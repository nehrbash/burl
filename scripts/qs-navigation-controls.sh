#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-tabs.XXXXXX")
probe_pid=""
cleanup() {
    if [[ -n $probe_pid ]]; then kill "$probe_pid" 2>/dev/null || true; wait "$probe_pid" 2>/dev/null || true; fi
    cat "$WORK/runtime.log" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/quickshell/qs" "$WORK/config" "$WORK/state"
for entry in "$ROOT"/*; do ln -s "$entry" "$WORK/quickshell/qs/"; done
cp "$ROOT/tests/burl-navigation-controls.qml" "$WORK/quickshell/qs/_tabs.qml"
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$HOME/.guix-home/profile/lib/qt6/qml}
XDG_CONFIG_HOME="$WORK/config" XDG_STATE_HOME="$WORK/state" BURL_DEFAULTS_FILE= \
QS_DISABLE_CRASH_HANDLER=1 quickshell --no-color -p "$WORK/quickshell/qs/_tabs.qml" > "$WORK/runtime.log" 2>&1 &
probe_pid=$!
ipc() { quickshell ipc --pid "$probe_pid" call navigationControls "$@"; }
for ((attempt = 0; attempt < 100; attempt++)); do
    kill -0 "$probe_pid" 2>/dev/null || exit 1
    if [[ $(ipc ready 2>/dev/null) == true ]]; then break; fi
    sleep 0.05
done
[[ $(ipc ready) == true ]]
hyprctl eval "hl.dispatch(hl.dsp.focus({window = 'pid:$probe_pid'}))" >/dev/null
ipc focus
keys() {
    [[ $(hyprctl -j activewindow | jq -r .pid) == "$probe_pid" ]] || { echo 'Probe lost focus'; exit 1; }
    wtype -k "$1"
}
expect() {
    for ((attempt = 0; attempt < 50; attempt++)); do
        if ipc state | jq -e ".index == $1 and .checked == 1 and .focused and .visible" >/dev/null; then return; fi
        sleep 0.05
    done
    ipc state
    exit 1
}
expect 0
keys Right; expect 1
keys End; expect 3
keys Right; expect 0
keys Left; expect 3
keys Home; expect 0
keys space; expect 0
ipc replace
ipc focus
expect 0
if grep -qE 'TypeError|ReferenceError|Binding loop|Failed to load configuration' "$WORK/runtime.log"; then exit 1; fi
echo 'PASS: arrows, Home/End, wraparound, activation, overflow and model replacement'
