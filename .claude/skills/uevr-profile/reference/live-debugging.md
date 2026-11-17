# Live debugging a running UEVR game (no headset on your head)

The core reads a **debug channel** file (`data/<prefix>debug.json`) twice per second. While that file is non-empty, it writes `data/<prefix>status.json` with measurements. Tools in `tools/` drive this.

## Setup
```bash
export UEVR_PROFILE=Scorn-Win64-Shipping   # %APPDATA%/UnrealVRMod/<this>
export UEVR_PROCESS=Scorn-Win64-Shipping   # exe name without .exe
export DBG_PREFIX=scorn_vr_                # file prefix used by the core
```

## Loop
1. Make sure the **HMD session is active**: `tools/wait_hmd.sh` (status `hmd_active`). Ask the user to disable headset sleep (Quest: Oculus Debug Tool → "Bypass Proximity Sensor Check" — GUI only, or system auto-sleep off). A taped proximity sensor is **not** enough. Without an active session, no stereo callbacks run, so the debug camera and the pose code do nothing.
2. Edit `data/<core>.lua`. The hot-reload loader picks it up within 1 s; check `data/<prefix>loader.txt` for compile/run errors.
3. Look:
   - `tools/dbg.sh <name> '<json>'` writes the debug JSON and takes a screenshot of the game window (`PrintWindow`, works when the window is covered). UEVR mirrors one eye into that window.
   - Debug camera `cam:{abs:true, fwd, right, up, turn, pitch}`: relative to the game camera and pawn yaw, so it does not depend on where the headset lies. `turn:180` looks back at the player's front.
   - Simulated controllers `sim_ctrl:[fwd,right,up]`, `sim_rot:[p,y,r]` (body frame) plus `force_ik:true` and `sim_head_yaw:0`. You get reproducible poses without anyone holding the controllers.
   - `hide_parts:[component names]` lets you **bisect** which component an artifact belongs to.
   - `show_game_mesh` / `hide_copy` compare the original mesh with the modified copy.
   - `tools/grid.py out.png a.png b.png …` tiles several shots into one image.
4. Measure: `tools/eval.sh '<lua>'` runs code inside the game (env: `S`, `M`, `api`, `vr`, helpers) and prints the returned table. Use it to dump bone trees, distances, frames and reflection (function lists).
5. Record animations: `record:true, record_bones:[...]` stores per-frame bone positions in a ring buffer → `<prefix>record.json`. `api:execute_command("slomo 0.2")` slows the game so screenshots can follow an animation.
6. When done: write `{}` to the debug file. A leftover `sim_head_yaw` or `force_ik` changes the user's game.

## Hard rules
- **Never call gameplay functions to trigger actions** (`SetAiming`, `TryReload`, `OnReload*`, `Fire`, ...). In Scorn this left the character in a stuck state: no fire, reload or weapon switch until a restart. Ask the user to press the button; prepare a capture loop (slomo + record + rolling screenshots) beforehand.
- Synthetic keyboard input (SendKeys / keybd_event) and injected XInput state did **not** reach the game. Don't burn time on them.
- `print()` doesn't go to UEVR's log.txt. Use the core's own log file.
- In the Bash tool, avoid big heredocs with mixed quotes. Write files with the Write tool and run them.

## Offline tests
`tools/run_smoke.py` loads `templates/loader.lua` + a core on `templates/mock_uevr.lua`: the UEVR API, a pawn with a hierarchical skeleton, a poseable mesh, UObjectHook, json/fs/imgui. Write scenario files like `templates/smoke_skeleton.lua`. Keep the mock's bone hierarchy faithful to the real one (e.g. twist bones as siblings of the wrist). Tests built on a wrong hierarchy pass while the game breaks.
