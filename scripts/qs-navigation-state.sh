#!/usr/bin/env bash
set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ROOT=${QS_ROOT:-$REPO}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/burl-navigation-state.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/quickshell/qs" "$WORK/config/burl" "$WORK/cache" "$WORK/state"
for entry in "$ROOT"/*; do
    if [[ $(basename "$entry") != components ]]; then
        ln -s "$entry" "$WORK/quickshell/qs/"
    fi
done
mkdir "$WORK/quickshell/qs/components"
for entry in "$ROOT/components"/*; do
    if [[ $(basename "$entry") == ScreenState.qml ]]; then
        # Inject invalid saved intent without exposing production state writers.
        sed '/^    id: root$/a\    readonly property var fixtureSavedIntent: intent' "$entry" \
            > "$WORK/quickshell/qs/components/ScreenState.qml"
    else
        ln -s "$entry" "$WORK/quickshell/qs/components/"
    fi
done
cp "$REPO/tests/burl-navigation-state.qml" "$WORK/quickshell/qs/_navigation.qml"
printf '%s\n' '{"dashboard":{"showWeather":false}}' > "$WORK/config/burl/shell.json"
printf '%s\n' '{}' > "$WORK/defaults.json"

export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$HOME/.guix-home/profile/lib/qt6/qml}
export QML2_IMPORT_PATH=${QML2_IMPORT_PATH:-$QML_IMPORT_PATH}
status=0
XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
BURL_DEFAULTS_FILE="$WORK/defaults.json" QT_QPA_PLATFORM=wayland \
    timeout 30 quickshell --no-color -p "$WORK/quickshell/qs/_navigation.qml" \
    > "$WORK/runtime.log" 2>&1 || status=$?
cat "$WORK/runtime.log"
if ((status != 0)); then
    exit "$status"
fi
if grep -qE "ERROR|CRITICAL|FATAL|NAVIGATION-FAIL|Failed to load configuration|TypeError|ReferenceError|SyntaxError|Unable to assign|Cannot assign|Binding loop|is not a type|unavailable|read-only property|JSValue can't be reassigned" "$WORK/runtime.log"; then
    exit 1
fi
grep -q 'NAVIGATION-INITIAL-PASS' "$WORK/runtime.log"
grep -q 'NAVIGATION-RELOAD-PASS' "$WORK/runtime.log"
grep -q 'NAVIGATION-RESTORE-RECONCILE-PASS' "$WORK/runtime.log"
grep -q 'NAVIGATION-MIGRATION-PASS' "$WORK/runtime.log"

cat > "$WORK/quickshell/qs/_tabs.qml" <<EOF
import QtQuick
import Quickshell
import Burl.Config
import qs.modules.dashboard

ShellRoot {
    settings.watchFiles: false
    Item {
        id: host
        width: 1000; height: 200
        Config.screen: Quickshell.screens[0].name
$(cat "$REPO/tests/burl-navigation-tabs.qmlfrag")
        onNavigationPassedChanged: if (navigationPassed) Qt.quit()
        Tabs {
            id: subject
            screenState: host.navigation
            tabs: host.navigationTabs
            nonAnimWidth: 1000
        }
    }
}
EOF
status=0
XDG_CONFIG_HOME="$WORK/config" XDG_CACHE_HOME="$WORK/cache" XDG_STATE_HOME="$WORK/state" \
BURL_DEFAULTS_FILE="$WORK/defaults.json" QT_QPA_PLATFORM=wayland \
    timeout 30 quickshell --no-color -p "$WORK/quickshell/qs/_tabs.qml" \
    > "$WORK/tabs.log" 2>&1 || status=$?
cat "$WORK/tabs.log"
if ((status != 0)); then
    exit "$status"
fi
if grep -qE 'ERROR|CRITICAL|FATAL|NAVIGATION-TABS-FAIL|Failed to load configuration|TypeError|ReferenceError|SyntaxError|Unable to assign|Cannot assign|Binding loop|is not a type|unavailable|read-only property' "$WORK/tabs.log"; then
    exit 1
fi
grep -q 'NAVIGATION-TABS-PASS' "$WORK/tabs.log"
echo 'PASS: zero-view navigation, actual QML reload, and windowless tabs'
