#!/usr/bin/env bash
# eval.sh '<lua code>' ['<extra debug json fields without braces>']  -> runs code in the game, prints the result
. "$(dirname "$0")/env.sh"
python -I - "$UEVR_DATA/${DBG_PREFIX}debug.json" "$1" "${2:-}" <<'PY'
import json, sys, time
path, code, extra = sys.argv[1:4]
d = json.loads("{" + extra + "}") if extra else {}
d["eval"] = code; d["eval_id"] = time.time()
open(path, "w").write(json.dumps(d))
PY
sleep "${WAIT:-1.5}"
python -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps((d.get('m') or {}).get('eval'), indent=1)[:8000])" "$UEVR_DATA/${DBG_PREFIX}status.json"
