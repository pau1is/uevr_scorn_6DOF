#!/usr/bin/env bash
# usage: eval_quiet.sh '<lua code>' '<debug json object incl. braces>' -> prints result only
T="$APPDATA/UnrealVRMod/Scorn-Win64-Shipping/data"
python -I - "$T/scorn_vr_debug.json" "$1" "$2" <<'PY'
import json, sys, time
path, code, base = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.loads(base) if base else {}
d["eval"] = code
d["eval_id"] = time.time()
open(path, "w").write(json.dumps(d))
PY
sleep 1.2
python -I -c "import json,sys; d=json.load(open(sys.argv[1])); print((d.get('m') or {}).get('eval'))" "$T/scorn_vr_status.json"
