#!/usr/bin/env bash
# Quickshell derives qs.* imports from the configuration directory name.
# Layer-shell dependencies require the Wayland backend even for an Item probe.
set -uo pipefail

# The shell service supplies this path; standalone probes need it too.
QT_QML_DIR=$HOME/.guix-home/profile/lib/qt6/qml
export QML_IMPORT_PATH=${QML_IMPORT_PATH:-$QT_QML_DIR}
export QML2_IMPORT_PATH=${QML2_IMPORT_PATH:-$QT_QML_DIR}

ROOT=${QS_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
GEOM=1
PLATFORM=${QS_SMOKE_QPA:-wayland}
SETS=()          # --set 'nav: navStub'   → property assignments on the subject
NATURAL=0        # --natural  → do not anchors.fill the subject; test implicit size
URLMODE=0        # --url      → mount via Loader.setSource(Qt.resolvedUrl(...)) like Content.qml does
SINGLETON=0
DECL=""          # --decl file.qmlfrag    → extra QML declared beside the subject
while [[ ${1-} == --* ]]; do
    case $1 in
        --root) ROOT=$2; shift 2;;
        --no-geom) GEOM=0; shift;;
        --qpa) PLATFORM=$2; shift 2;;
        --set) SETS+=("$2"); shift 2;;
        --natural) NATURAL=1; shift;;
        --url) URLMODE=1; shift;;
        --singleton) SINGLETON=1; GEOM=0; shift;;
        --decl) DECL=$(cat "$2"); shift 2;;
        *) echo "unknown flag $1" >&2; exit 2;;
    esac
done
TARGET=${1:?usage: qs-smoke.sh [--root DIR] [--no-geom] <path/relative/to/burl/Type.qml>}

[[ -f $ROOT/$TARGET ]] || { echo "no such component: $ROOT/$TARGET" >&2; exit 2; }

TYPE=$(basename "$TARGET" .qml)
DIR=$(dirname "$TARGET")
MODULE="qs"
[[ $DIR != "." ]] && MODULE="qs.${DIR//\//.}"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/qs-smoke.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/quickshell/qs"
for f in "$ROOT"/*; do ln -s "$f" "$WORK/quickshell/qs/"; done

PROBE=$WORK/quickshell/qs/_probe.qml
ANCHOR="anchors.fill: parent"
(( NATURAL )) && ANCHOR="// --natural: implicit sizing only"

if (( SINGLETON )); then
    SUBJECT="property var subject: $TYPE"
    IMPORTLINE="import $MODULE"
elif (( URLMODE )); then
    SUBJECT="Loader {
            id: subject
            $ANCHOR
            Component.onCompleted: setSource(Qt.resolvedUrl(\"$TARGET\"), {
$( ((${#SETS[@]})) && printf '                %s,\n' "${SETS[@]}" )
            })
            onStatusChanged: if (status === Loader.Error) console.log(\"QSSMOKE-URLFAIL\")
        }"
else
    SUBJECT="$TYPE {
            id: subject
            $ANCHOR
$(printf '            %s\n' "${SETS[@]+"${SETS[@]}"}")
        }"
    IMPORTLINE="import $MODULE"
fi

cat > "$PROBE" <<EOF
import QtQuick
import Quickshell
${IMPORTLINE-}

ShellRoot {
    Item {
        id: host
        width: 2560; height: 1440
$DECL
        $SUBJECT
        Component.onCompleted: Qt.callLater(function () {
            console.log("QSSMOKE-GEOM", subject.width + "x" + subject.height,
                        "implicit", subject.implicitWidth + "x" + subject.implicitHeight);
            console.log("QSSMOKE-OK");
            Qt.callLater(Qt.quit);
        });
    }
}
EOF

LOG=$WORK/out.txt
QT_QPA_PLATFORM=$PLATFORM timeout 60 quickshell --no-color -p "$PROBE" >"$LOG" 2>&1
RESULT=$?

fail() { echo "FAIL($TARGET): $1"; echo "--- log ---"; grep -vE '^ *INFO' "$LOG" | head -40; exit 1; }

(( RESULT == 0 )) || fail "quickshell exited with status $RESULT"

HARD='Failed to load configuration|Type [A-Za-z0-9_.]+ unavailable|is not a type|Illegal method name|cannot begin with an upper case letter|read-only property|Property value set multiple times|Cannot assign to non-existent property|Duplicate (method|signal|property) name|Invalid property name|Cyclic dependency'
grep -qE "$HARD" "$LOG" && fail "load error"
grep -q 'QSSMOKE-OK' "$LOG" || fail "component never reached onCompleted (hang, crash or silent bail)"
grep -q 'QSSMOKE-URLFAIL' "$LOG" && fail "URL-mounted component failed to load (sibling type not resolvable from a URL mount?)"

if grep -qE 'TypeError|ReferenceError|SyntaxError|Unable to assign|no signal of the target matches' "$LOG"; then
    fail "binding error (supply required properties with --set)"
fi

if (( GEOM )); then
    g=$(awk '/QSSMOKE-GEOM/ {for (i=1; i<NF; i++) if ($i == "QSSMOKE-GEOM") {print $(i+1); exit}}' "$LOG")
    [[ $g =~ ^[0-9]+([.][0-9]+)?x[0-9]+([.][0-9]+)?$ ]] || fail "missing or invalid geometry"
    awk -v size="$g" 'BEGIN {split(size, n, "x"); exit !(n[1] > 0 && n[2] > 0)}' || fail "zero-size geometry ($g)"
    echo "PASS($TARGET) geometry $g"
else
    echo "PASS($TARGET)"
fi
