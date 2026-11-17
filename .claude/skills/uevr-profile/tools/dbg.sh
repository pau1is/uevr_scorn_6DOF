#!/usr/bin/env bash
# dbg.sh <name> ['<debug json>']  -> write the debug channel file, wait, screenshot the game window
. "$(dirname "$0")/env.sh"
[ -n "$2" ] && printf '%s' "$2" > "$UEVR_DATA/${DBG_PREFIX}debug.json"
sleep "${WAIT:-2}"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$SKILL_TOOLS/shot.ps1")" -out "$(cygpath -w "$SHOTS_DIR/$1.png")" -proc "$UEVR_PROCESS" > /dev/null
echo "shot: $SHOTS_DIR/$1.png"
