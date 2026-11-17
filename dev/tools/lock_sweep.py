"""Interaction-lock eye test (game running, character at a console, HMD session active).

Sets the control yaw to pawn_yaw + offset (like a snap turn would), holds the view fixed with the
debug camera, and records the final eye position with and without the console-camera correction.

    python -I dev/tools/lock_sweep.py <shots_dir> [pawn_yaw] [pitch]
"""
import json, os, subprocess, sys, time

T = os.path.join(os.environ["APPDATA"], "UnrealVRMod", "Scorn-Win64-Shipping", "data")
DBG, ST = os.path.join(T, "scorn_vr_debug.json"), os.path.join(T, "scorn_vr_status.json")
HERE = os.path.dirname(os.path.abspath(__file__))
shots = sys.argv[1]
pawn_yaw = float(sys.argv[2]) if len(sys.argv) > 2 else 90.0
pitch = float(sys.argv[3]) if len(sys.argv) > 3 else -30.0
os.makedirs(shots, exist_ok=True)

SET = ("local pc = api:get_player_controller(0) local r = pc:GetControlRotation() "
       "pc:SetControlRotation({Pitch = r.Pitch, Yaw = %f, Roll = 0}) return 'ok'")


def write(d):
    with open(DBG, "w") as f:
        json.dump(d, f)


def status():
    for _ in range(5):
        try:
            with open(ST) as f:
                return json.load(f)
        except Exception:
            time.sleep(0.2)
    return {}


rows = []
for no_shift in (False, True):
    for off in (-40, -20, 0, 20, 40):
        d = {"cam": {"yaw": pawn_yaw, "pitch": pitch}, "eval": SET % (pawn_yaw + off), "eval_id": time.time()}
        if no_shift:
            d["no_view_shift"] = True
        write(d)
        time.sleep(2.0)
        s = status()
        m = s.get("m") or {}
        e = m.get("eye_w") or {}
        name = "%s_%+d" % ("off" if no_shift else "on", off)
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                        os.path.join(HERE, "shot.ps1"), "-out", os.path.join(shots, name + ".png")],
                       capture_output=True)
        rows.append((name, m.get("lock_cam_rel_yaw"), m.get("lock_view_shift"), e.get("x"), e.get("y"), e.get("z"),
                     s.get("locked"), s.get("hmd_active")))
        print("%-8s rel=%7s shift=%7s eye=(%s, %s, %s) locked=%s hmd=%s" % tuple(
            (round(v, 2) if isinstance(v, float) else v) for v in rows[-1]), flush=True)

# back to the start: control yaw on the pawn, no debug camera
write({"eval": SET % pawn_yaw, "eval_id": time.time()})
time.sleep(1.0)
write({})
