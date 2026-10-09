#!/usr/bin/env bash
# qs-shot.sh — render ONE burl QML component offscreen and write a PNG.
#
#   qs-shot.sh modules/launcher/Sky.qml /tmp/sky.png
#   qs-shot.sh --size 1600x900 --settle 2500 modules/bar/Bar.qml /tmp/bar.png
#   qs-shot.sh --set 'panP: 1' modules/launcher/Sky.qml /tmp/sky.png
#   qs-shot.sh --bg '#241a12' components/containers/BarkCard.qml /tmp/card.png
#
# Companion to qs-smoke.sh: that one answers "does it load", this one answers
# "what does it look like". Neither touches the running shell — the probe is a
# separate quickshell instance rendering into its own window, and the grab is
# CUtils.saveItem (QQuickItem::grabToImage), not a compositor screenshot. So a
# fullscreen window on the real desktop cannot hide the subject, and the user's
# screen is never disturbed.
#
# QPA NOTE: same as qs-smoke — `offscreen` dies as soon as any transitive
# singleton declares a PanelWindow, so this runs on wayland. The probe window is
# a FloatingWindow; it does map briefly.
set -uo pipefail

QT_QML_DIR=$HOME/.guix-home/profile/lib/qt6/qml
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$QT_QML_DIR}
export QML2_IMPORT_PATH=${QML2_IMPORT_PATH:-$QT_QML_DIR}

ROOT=${QS_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
SIZE=1920x1080
SETTLE=1500
BG=transparent
SETS=()
DECL=""
LOG_OUT=""
while [[ ${1-} == --* ]]; do
    case $1 in
        --root) ROOT=$2; shift 2;;
        --size) SIZE=$2; shift 2;;
        --settle) SETTLE=$2; shift 2;;   # ms to let animations/images land
        --bg) BG=$2; shift 2;;           # flatten onto this colour
        --set) SETS+=("$2"); shift 2;;
        --decl) DECL=$(cat "$2"); shift 2;;
        --log) LOG_OUT=$2; shift 2;;
        *) echo "unknown flag $1" >&2; exit 2;;
    esac
done
TARGET=${1:?usage: qs-shot.sh [flags] <path/relative/to/burl/Type.qml> <out.png>}
OUT=${2:?usage: qs-shot.sh [flags] <path/relative/to/burl/Type.qml> <out.png>}

[[ -f $ROOT/$TARGET ]] || { echo "no such component: $ROOT/$TARGET" >&2; exit 2; }
W=${SIZE%x*}; H=${SIZE#*x}
TYPE=$(basename "$TARGET" .qml)
DIR=$(dirname "$TARGET")
MODULE="qs"
[[ $DIR != "." ]] && MODULE="qs.${DIR//\//.}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/qs-shot.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/quickshell/qs"
for f in "$ROOT"/*; do ln -s "$f" "$WORK/quickshell/qs/"; done

RAW=$WORK/raw.png
PROBE=$WORK/quickshell/qs/_probe.qml
cat > "$PROBE" <<EOF
import QtQuick
import Quickshell
import Burl
import $MODULE

ShellRoot {
    settings.watchFiles: false

    FloatingWindow {
        id: win

        width: $W
        height: $H
        color: "transparent"
        visible: true

        Item {
            id: host

            anchors.fill: parent
$DECL
            $TYPE {
                id: subject

                anchors.fill: parent
$(printf '                %s\n' "${SETS[@]+"${SETS[@]}"}")
            }
        }

        Timer {
            running: true
            interval: $SETTLE
            onTriggered: CUtils.saveItem(host, Qt.resolvedUrl("file://$RAW"), function () {
                console.log("QSSHOT-OK");
                Qt.callLater(Qt.quit);
            }, function () {
                console.log("QSSHOT-FAIL");
                Qt.callLater(Qt.quit);
            })
        }
    }
}
EOF

LOG=$WORK/out.txt
probe_status=0
QT_QPA_PLATFORM=${QS_SHOT_QPA:-wayland} timeout 120 quickshell --no-color -p "$PROBE" >"$LOG" 2>&1 || probe_status=$?
if [[ -n $LOG_OUT ]]; then
    cp "$LOG" "$LOG_OUT"
fi
if ((probe_status != 0)); then
    cat "$LOG"
    exit "$probe_status"
fi

if ! grep -q QSSHOT-OK "$LOG" || [[ ! -s $RAW ]]; then
    echo "FAIL($TARGET): no image written"
    grep -vE '^ *INFO' "$LOG" | head -30
    exit 1
fi

if [[ $BG == transparent ]]; then
    cp "$RAW" "$OUT"
else
    convert "$RAW" -background "$BG" -flatten "$OUT"
fi
echo "SHOT($TARGET) -> $OUT"
