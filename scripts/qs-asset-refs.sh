#!/bin/sh
# Verify every image path referenced from QML actually exists on disk.
#
# A missing image is SILENT in QML — the Image element just never loads, no error,
# no log line — so neither qmllint nor the headless smoke test can see it. This is
# the only check that catches a moved or renamed asset.
#
# Handles both reference styles used in this shell:
#   Quickshell.shellPath("assets/images/foo.png")   -> resolved from 
#   source: "images/foo.png"                        -> resolved from the QML's own dir
# Dynamic paths (string interpolation like `images/sloth${n}.png`) are reported
# separately: they cannot be checked statically and must be eyeballed.
set -eu
ROOT="${1:-.}"
missing=0; dynamic=0

# --- shellPath("...") — always relative to the config root
grep -rn 'shellPath("' "$ROOT" --include='*.qml' | sed 's/.*shellPath("\([^"]*\)").*/\1|&/' | while IFS='|' read -r p line; do
    # A line whose shellPath() call does not close on the same line leaves the
    # sed above unsubstituted, so $p holds the whole line (hence the shellPath
    # case) and $line is empty — report the line we do have, not nothing.
    case "$p" in *'${'*|*'" +'*|*'"+'*|*shellPath*) echo "DYNAMIC  ${line:-$p}"; continue;; esac
    # -e, not -f: shellPath() also names directories, e.g. PamContext's
    # configDirectory: shellPath("assets/pam.d"). Testing for a plain file
    # reported those as MISSING on every run, and a checker that always cries
    # wolf is how the tomato-asset move went unnoticed.
    [ -e "$ROOT/$p" ] || echo "MISSING  $p   <- $(echo "$line" | cut -d: -f1,2)"
done

# --- source: "relative/path" — relative to the referencing file's directory
grep -rn 'source: "[^"]*\.\(png\|svg\|webp\|gif\|jpg\)"' "$ROOT" --include='*.qml' | while IFS= read -r line; do
    f=$(echo "$line" | cut -d: -f1)
    p=$(echo "$line" | sed 's/.*source: "\([^"]*\)".*/\1/')
    case "$p" in *'${'*) echo "DYNAMIC  $line"; continue;; esac
    d=$(dirname "$f")
    [ -f "$d/$p" ] || echo "MISSING  $p   <- $f"
done

echo "--- dynamic references (check by hand):"
grep -rn 'images/\${\|\${[A-Za-z_.]*}\.png\|\${[A-Za-z_.]*}\.svg' "$ROOT" --include='*.qml' | sed 's/^/  /' | head -20
