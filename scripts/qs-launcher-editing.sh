#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=${QS_ROOT:-$REPO}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-launcher-editing.XXXXXX")
probe_pid=""
cleanup() {
    if [[ -n $probe_pid ]]; then
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    fi
    cat "$WORK/runtime.log" 2>/dev/null || true
    if [[ -n ${QS_TEST_LOG:-} ]]; then cp "$WORK/runtime.log" "$QS_TEST_LOG"; fi
    rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/quickshell/qs" "$WORK/config" "$WORK/cache" "$WORK/state"
for entry in "$ROOT"/*; do ln -s "$entry" "$WORK/quickshell/qs/"; done
cp "$REPO/tests/burl-launcher-editing.qml" "$WORK/quickshell/qs/_editing.qml"
printf '%s\n' '{}' > "$WORK/defaults.json"
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$HOME/.guix-home/profile/lib/qt6/qml}
export QML2_IMPORT_PATH=${QML2_IMPORT_PATH:-$QML_IMPORT_PATH}
XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
BURL_DEFAULTS_FILE="$WORK/defaults.json" QT_QPA_PLATFORM=wayland QS_DISABLE_CRASH_HANDLER=1 \
    quickshell --no-color -p "$WORK/quickshell/qs/_editing.qml" > "$WORK/runtime.log" 2>&1 &
probe_pid=$!
ipc() { quickshell ipc --pid "$probe_pid" call launcherEditing "$@"; }
wait_for() {
    for ((attempt = 0; attempt < 200; attempt++)); do
        kill -0 "$probe_pid" 2>/dev/null || return 1
        if [[ $(ipc "$1" 2>/dev/null) == true ]]; then return; fi
        sleep 0.05
    done
    echo "Timed out: $1" >&2
    return 1
}
keys() {
    if [[ $(hyprctl -j activewindow | jq -r .pid) != "$probe_pid" ]]; then
        echo 'Probe is not focused; refusing keyboard injection' >&2
        return 1
    fi
    wtype "$@"
}
expect() {
    local actual
    actual=$(ipc state)
    if ! jq -e "$1" <<< "$actual" >/dev/null; then
        echo "Failed: $1; actual: $actual" >&2
        return 1
    fi
}
for ((attempt = 0; attempt < 200; attempt++)); do
    if grep -q LAUNCHER-EDITING-READY "$WORK/runtime.log"; then break; fi
    kill -0 "$probe_pid" 2>/dev/null || exit 1
    sleep 0.05
done
grep -q LAUNCHER-EDITING-READY "$WORK/runtime.log"
ipc open
wait_for ready
hyprctl eval "hl.dispatch(hl.dsp.focus({window = 'pid:$probe_pid'}))" >/dev/null
sleep 0.2
[[ $(ipc seed 'alpha beta gamma' 16) == true ]]
keys -M ctrl -k a -m ctrl
expect '.cursor == 0 and .text == "alpha beta gamma" and .focused'
keys -M ctrl -k k -m ctrl
expect '.text == "" and .cursor == 0 and .closed == false'
keys -M ctrl -k y -m ctrl
expect '.text == "alpha beta gamma" and .cursor == 16'
keys -M ctrl -k a -k e -m ctrl
expect '.cursor == 16'
keys -M alt -k BackSpace -m alt
expect '.text == "alpha beta " and .cursor == 11'
[[ $(ipc seed 'alpha beta gamma' 0) == true ]]
keys -M alt -k d -m alt
expect '.text == " beta gamma" and .cursor == 0'
keys -M ctrl -k y -m ctrl
expect '.text == "alpha beta gamma" and .cursor == 5'
ipc close
wait_for hidden
ipc open
wait_for ready
expect '.text == "alpha beta gamma" and .cursor == 5'
ipc playlist
sleep 0.2
expect '.playlist == "fixture" and .text == "Fixture" and .selected == "spotify:pl:fixture"'
first_scene=$(ipc state | jq .scenes)
ipc close
wait_for hidden
ipc open
wait_for ready
expect '.playlist == "fixture" and .text == "Fixture" and .selected == "spotify:pl:fixture" and .returnQuery == ">spotify original"'
ipc close
wait_for hidden
[[ $(ipc destroyScene) == true ]]
ipc recreate
wait_for ready
sleep 0.3
expect ".scenes > $first_scene and .playlist == \"fixture\" and .text == \"Fixture\" and .selected == \"spotify:pl:fixture\" and .returnQuery == \">spotify original\""
[[ $(ipc selectSecondApplication) == true ]]
selected_scene=$(ipc state | jq .scenes)
ipc close
wait_for hidden
ipc open
wait_for ready
sleep 0.3
[[ $(ipc selectionRetained) == true ]]
ipc close
wait_for hidden
[[ $(ipc destroyScene) == true ]]
ipc recreate
wait_for ready
wait_for selectionRetained
sleep 0.3
[[ $(ipc selectionRetained) == true ]]
expect ".scenes > $selected_scene and .text == \"\" and .playlist == \"\""
ipc playlist
sleep 0.2
ipc refreshPreview
wait_for previewUpdated
ipc close
wait_for hidden
[[ $(ipc destroyScene) == true ]]
[[ $(ipc queueQuery) == true ]]
ipc recreate
wait_for ready
sleep 0.3
expect '.text == "cold IPC override" and .playlist == "" and .returnQuery == ""'
if grep -qE 'TypeError|ReferenceError|SyntaxError|Cannot assign|Binding loop|Failed to load configuration' "$WORK/runtime.log"; then exit 1; fi
echo 'PASS: editing, retained query/playlist/selection, cold IPC override and same-shape preview refresh'
