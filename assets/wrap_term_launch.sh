#!/usr/bin/env sh

cat ~/.local/state/burl/sequences.txt 2>/dev/null

exec "$@"
