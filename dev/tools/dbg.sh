#!/usr/bin/env bash
# usage: dbg.sh <name> '<debug json>'   -> writes debug json, waits, screenshots to work/shots/<name>.png
HERE="$(cd "$(dirname "$0")" && pwd)"
SHOTS="${SHOTS_DIR:-$HERE/../../shots}"; mkdir -p "$SHOTS"
T="$APPDATA/UnrealVRMod/Scorn-Win64-Shipping/data"
name="$1"
if [ -n "$2" ]; then printf '%s' "$2" > "$T/scorn_vr_debug.json"; fi
sleep "${WAIT:-2}"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/shot.ps1")" -out "$(cygpath -w "$SHOTS/$name.png")" > /dev/null
echo "shot: $SHOTS/$name.png"
