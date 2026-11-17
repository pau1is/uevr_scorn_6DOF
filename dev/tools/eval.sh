#!/usr/bin/env bash
# usage: eval.sh <lua file> [extra json fields]  -> runs snippet in game, prints status.m.eval
T="$APPDATA/UnrealVRMod/Scorn-Win64-Shipping/data"
code=$(cat "$1")
extra="${2:-}"
python -I - "$T/scorn_vr_debug.json" "$code" "$extra" <<'PY'
import json, sys, time
path, code, extra = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.loads("{" + extra + "}") if extra else {}
d["eval"] = code
d["eval_id"] = time.time()
open(path, "w").write(json.dumps(d))
PY
sleep "${WAIT:-2}"
python -I - "$T/scorn_vr_status.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(json.dumps((d.get("m") or {}).get("eval"), indent=1)[:6000])
PY
