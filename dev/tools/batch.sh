#!/usr/bin/env bash
# waits for an active HMD, then captures a batch of debug views
T="$APPDATA/UnrealVRMod/Scorn-Win64-Shipping/data"
D="$(cd "$(dirname "$0")" && pwd)/dbg.sh"
tag="${1:-b}"
for i in $(seq 1 600); do
  a=$(python -I -c "import json,sys; print(json.load(open(sys.argv[1])).get('hmd_active'))" "$T/scorn_vr_status.json" 2>/dev/null)
  [ "$a" = "True" ] && break
  sleep 1
done
echo "hmd active after ${i}s"
SIM='"sim_head_yaw":0,"force_ik":true,"sim_ctrl":[35,22,-35],"sim_ctrl_l":[30,-22,-40]'
FRONT='"cam":{"abs":true,"fwd":200,"up":-40,"turn":180,"pitch":-5}'
SIDE='"cam":{"abs":true,"fwd":40,"right":180,"up":-40,"turn":-90,"pitch":-5}'
export WAIT=1.3
$D ${tag}_front "{$FRONT,$SIM}"
$D ${tag}_side "{$SIDE,$SIM}"
$D ${tag}_side_up "{$SIDE,$SIM,\"sim_rot\":[30,0,0]}"
$D ${tag}_front_yaw "{$FRONT,$SIM,\"sim_rot\":[0,40,0]}"
$D ${tag}_left "{\"cam\":{\"abs\":true,\"fwd\":40,\"right\":-180,\"up\":-40,\"turn\":90,\"pitch\":-5},$SIM,\"sim_rot\":[0,40,0]}"
$D ${tag}_fp "{$SIM}"
python -I -c "import json,sys; d=json.load(open(sys.argv[1])); print('hmd', d.get('hmd_active'), 'm', {k: d['m'].get(k) for k in ('wrist_err','weapon_vs_copy','left_mode','ik_alpha')})" "$T/scorn_vr_status.json"
