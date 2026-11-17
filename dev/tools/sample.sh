#!/usr/bin/env bash
# usage: sample.sh <lua file> <count> [interval_s]  -> runs the snippet repeatedly, prints one JSON line per sample
T="$APPDATA/UnrealVRMod/Scorn-Win64-Shipping/data"
code=$(cat "$1")
n="${2:-10}"
iv="${3:-0.6}"
python -I - "$T" "$code" "$n" "$iv" <<'PY'
import json, sys, time, os
T, code, n, iv = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
dbg, st = os.path.join(T, "scorn_vr_debug.json"), os.path.join(T, "scorn_vr_status.json")
last = None
for i in range(n):
    open(dbg, "w").write(json.dumps({"eval": code, "eval_id": time.time()}))
    time.sleep(iv)
    try:
        v = (json.load(open(st)).get("m") or {}).get("eval")
    except Exception as e:
        v = "read error %s" % e
    s = json.dumps(v, separators=(",", ":"))
    if s != last:
        print(s, flush=True)
        last = s
PY
