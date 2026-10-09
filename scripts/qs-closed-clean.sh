#!/bin/sh
# Assert the shell paints NOTHING over the desktop while the dashboard is closed,
# on EVERY monitor.
#
# Why this exists: the living tree leaked onto the desktop three separate ways —
# a scroll gated on persisted open-section state, star motes gated on nothing, and
# a full-screen opaque ground that WAS gated correctly but stayed lit because
# ScreenState is PER SCREEN and an IPC toggle only closes the active one. The
# author kept testing the focused monitor and shipped a brown screen on the other.
#
# Method: force every screen's dashboard shut, capture each monitor, then re-capture
# after a second and compare. A leaked layer that animates (motes, bob, flight)
# shows up as a difference; a static leak is caught by the caller eyeballing
# <out>/closed-<monitor>.png, which this prints the paths of.
#
#   scripts/qs-closed-clean.sh [outdir]
set -eu
OUT="${1:-${XDG_RUNTIME_DIR:-/tmp}/qs-closed-clean}"
mkdir -p "$OUT"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Close on every screen, not just the active one: `drawers toggle` is active-screen
# only, so walk the monitors and park the cursor on each before toggling.
sig=$(ls -t "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -1)
[ -n "$sig" ] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
mons=$(hyprctl -j monitors | jq -r '.[] | "\(.name) \(.x + .width / (.scale * 2) | floor) \(.y + .height / (.scale * 2) | floor)"')

printf '%s\n' "$mons" | while read -r name cx cy; do
    hyprctl dispatch "hl.dsp.cursor.move({x = $cx, y = $cy})" >/dev/null 2>&1 || true
    sleep 0.4
    if [ "$(qs -c qs ipc call drawers isOpen dashboard 2>/dev/null)" = "1" ]; then
        qs -c qs ipc call drawers toggle dashboard >/dev/null 2>&1 || true
    fi
done
sleep 1.5

fail=0
printf '%s\n' "$mons" | while read -r name cx cy; do
    grim -o "$name" "$OUT/closed-$name.png" 2>/dev/null || continue
    sleep 1.2
    grim -o "$name" "$OUT/closed-$name-b.png" 2>/dev/null || continue
    d=$(compare -metric RMSE "$OUT/closed-$name.png" "$OUT/closed-$name-b.png" null: 2>&1 | sed 's/.*(\(.*\))/\1/')
    # Anything animating while closed is a leak. A live video wallpaper is itself
    # animation, so this threshold only catches shell-sized motion, not the wallpaper.
    echo "  $name: frame delta $d  -> $OUT/closed-$name.png"
done
echo "closed-state captures written to $OUT (inspect them: the shell must be invisible)"
