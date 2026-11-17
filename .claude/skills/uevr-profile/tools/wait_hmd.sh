#!/usr/bin/env bash
# wait_hmd.sh [timeout_s] -> waits until status.hmd_active is true (stereo callbacks only run with an active HMD)
. "$(dirname "$0")/env.sh"
for i in $(seq 1 "${1:-600}"); do
  a=$(python -I -c "import json,sys; print(json.load(open(sys.argv[1])).get('hmd_active'))" "$UEVR_DATA/${DBG_PREFIX}status.json" 2>/dev/null)
  [ "$a" = "True" ] && { echo "hmd active after ${i}s"; exit 0; }
  sleep 1
done
echo "timeout"; exit 1
