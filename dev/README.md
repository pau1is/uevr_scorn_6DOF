# Development notes

## Layout

```
profile/Scorn-Win64-Shipping/      the UEVR profile (what users install)
  config.txt                       UEVR settings (aim = right controller, UObjectHook lerp off, ...)
  scripts/scorn_vr.lua             loader: runs data/scorn_vr_core.lua and hot-reloads it on change
  data/scorn_vr_core.lua           the mod itself
  uobjecthook/*.json               hides the "Spine" scene component
dev/tests/                         offline tests (UEVR API mocked, runs in Lua 5.4 via lupa)
dev/tools/                         live-debugging helpers (screenshots, eval, debug camera)
tools/build_release.py             builds dist/Scorn-Win64-Shipping.zip
```

## How it works

1. **Body copy.** A `PoseableMeshComponent` is added to the pawn and attached to `CharacterMesh0`. Every frame it gets `CopyPoseFromSkeletalComponent`. The game mesh keeps animating but is not rendered in the main pass. Followers with the same skeleton (the weapon mesh, parasite corruption, apparatus) get `SetMasterPoseComponent(copy)`, so they follow the modified pose.
2. **Timing.** UObjectHook moves its motion-controller components in `pre_calculate_stereo_view_offset` for the first eye. The mod runs right after it, in `post_calculate_stereo_view_offset`, so it sees the current controller pose. Everything moved for rendering is restored in `pre_engine_tick`, which leaves game logic (camera bone, traces) on the original pose.
3. **Body yaw.** `CharacterMesh0` is rotated around the camera bone to the HMD yaw. The rotation is render-only and restored every tick.
4. **Arms.** Two-bone IK puts the wrists on two scene components that UObjectHook attaches to the controllers.
   - **Wrist rotation** comes from a hand frame built from the finger bones: forward = middle knuckle, up = index side. The barrel therefore follows the controller.
   - **Shoulder and elbow orientation** is deterministic: cached local bone axes + the elbow hinge normal. The elbow hint is body-relative, so the walk and look animations cannot twist the arm.
   - **Wrist roll** is spread 25/50/75 % over `mc_forearm_twist_0x`.
5. **Parasite and hose.** The `p_*` arm chains grow from the root. They keep the animated pose and IK to the nearest player hand only when the animation brings them closer than 15–30 cm. The ammo apparatus `app_root` is held by `p_hand_snap_SH_l_jnt`. The stun gun hose is smoothstep-blended towards the wrist.
6. **Input.** The right stick X becomes a snap turn (via `SetControlRotation`). The right stick Y is swallowed.

### Scorn facts that matter

- Bones are named `mc_*_SH_*_jnt`. The weapon bones hang under `mc_weapon_snap_SH_r_jnt`, and the weapon is a separate mesh with the same skeleton.
- The native first-person pose holds **both arms above the head**: it is authored for the flat camera.
- `PlayerCamera` sits on bone `camera_rot_x_SH_jnt`. With UEVR controller aim, the game camera follows the *controller*, so it is not a usable reference frame.
- The game drives the pawn yaw itself.

## Tests

```
pip install lupa
python dev/tests/run_tests.py
```

`test_v21.py` loads the real loader + core against `mock2.lua`, a fake UEVR API with a hierarchical skeleton, and runs `scenario_v2.lua`. The scenario covers: IK reach, hand orientation, bone lengths, arm independence from animated roll, body yaw, restore, follower remastering, snap turn, hot reload and cleanup.

## Live debugging (game running)

The core reads `%APPDATA%\UnrealVRMod\Scorn-Win64-Shipping\data\scorn_vr_debug.json` twice per second. While that file is non-empty, `scorn_vr_status.json` (measurements) is written. Keys:

| key | effect |
|---|---|
| `cam: {abs, fwd, right, up, turn, pitch}` | debug camera. With `abs` it is relative to the game camera and pawn yaw, independent of the HMD |
| `sim_ctrl`, `sim_ctrl_l` `[fwd,right,up]`, `sim_rot`, `sim_rot_l` | simulated controllers (cm, body frame) |
| `force_ik` | IK on even without a weapon or active controllers |
| `sim_head_yaw` | fixed body yaw offset (deg) |
| `hide_parts: [names]` | hide pawn components |
| `show_game_mesh`, `hide_copy` | compare the game mesh with the copy |
| `no_twist`, `no_pchain`, `no_hose`, `no_left`, `legacy_arm` | switch features off |
| `record`, `record_bones` | per-frame bone recording → `scorn_vr_record.json` |
| `eval` (+ `eval_id`) | runs a Lua snippet in the game, result in `status.m.eval` |

Helpers in `dev/tools`: `shot.ps1` (window screenshot via `PrintWindow`), `dbg.sh <name> '<json>'` (set debug + screenshot), `eval.sh <file.lua>`, `batch.sh` (waits for an active HMD, then captures a set of views). The `e_*.lua` files are example eval snippets.

> Do **not** call gameplay functions (`SetAiming`, `TryReload`, ...) through `eval`. They can leave the character in a stuck state that only a game restart fixes. Let a human press the buttons.

**The HMD must stay awake.** When the OpenXR session stops, there are no stereo callbacks, so the mod doesn't run and the debug camera does nothing.

## Release

```
python tools/build_release.py
```

Upload `dist/Scorn-Win64-Shipping.zip` to a GitHub Release.
