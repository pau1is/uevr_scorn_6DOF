# Full body + IK arms in UEVR (proven design)

Reference implementation: https://github.com/pau1is/uevr_scorn_6DOF (`profile/Scorn-Win64-Shipping/data/scorn_vr_core.lua`). Math: `templates/uemath.lua`.

## Why not just attach the mesh to the controller
- If the arms are part of a **full-body mesh** (common in UE4 first-person games), attaching the mesh to a controller drags the torso and legs with the hand.
- Pinning the whole mesh by the hand bone works only for arms-only rigs.
- A weapon attached to the controller with UObjectHook floats away from the hand and loses the reload/insert animations.

## Pipeline per frame
1. **pre_engine_tick**: restore everything moved for rendering last frame (relative transforms). Game logic, traces and the camera-on-a-bone stay on the native pose.
2. The game ticks; the animation updates the game mesh.
3. **post_calculate_stereo_view_offset, first eye** (after UObjectHook moved the helper components):
   1. **Body yaw**: rotate the game mesh around the camera bone so it faces the HMD yaw (render-only, restored next tick). An optional deadzone can be added.
   2. **Body copy**: `copy:CopyPoseFromSkeletalComponent(gameMesh)`. The copy is a `PoseableMeshComponent` attached to the game mesh with a zero offset, same mesh asset and materials. The game mesh gets `SetRenderInMainPass(false)` and `VisibilityBasedAnimTickOption = 0`. The weapon and other same-skeleton followers get `SetMasterPoseComponent(copy)`. Re-apply that every ~0.5 s: it is cheap, and the game re-sets it on weapon switch.
   3. **IK targets**: wrist position = controller grip + offset (in controller space). Wrist rotation = `controller_rot * hand_grip_q(fingers)`, where the hand frame comes from the bones: forward = wrist→middle knuckle, up = pinky→index. The weapon then points along the controller **without per-weapon calibration**.
   4. **Two-bone IK** (`solve_two_bone`) with a **body-relative elbow hint** (down + outward + slightly back). Never take the hint from the animated elbow: walk/look animations would flip it.
   5. **Deterministic bone orientation**: cache each arm's local bone axis and hinge normal once from a bent native pose (`arm_axes`). Then set shoulder/elbow rotations with `frame_q(local_axis, local_hinge, world_axis, world_hinge)`. Using `qbetween` from the animated pose inherits the animation's arm roll and twists the arm when the game plays look/pitch animations.
   6. **Forearm twist**: spread the wrist's twist (relative to native) over the twist bones (25/50/75 %) with swing-twist decomposition (`qtwist`, `qfrac`).
   7. **Side chains**: parasite arms, hoses, held props on separate chains from the root. Keep the native pose; blend toward the **nearest player hand** only when the animation brings them close (proximity 15→30 cm). Hoses: smoothstep weight along the chain.
4. Rendering uses the modified pose. A `PoseableMeshComponent` refreshes its bones on its own tick, so the copy renders one frame late. That is acceptable.

## Things that broke and why
| Symptom | Cause | Fix |
|---|---|---|
| The body doesn't turn with the head | the pawn yaw is driven by the game; read the HMD yaw from the stereo callback (`rotation.y`) | render-only body yaw |
| Weapon pointing sideways | used the game camera as the reference: under UEVR controller aim, the game camera follows the **controller** | build the hand frame from finger bones |
| Weapon flies out of the hand | carried the weapon manually **and** it followed by master pose (double transform) | rely on master pose only |
| Hand lags behind the laser | UObjectHook attach lerp | disable the lerp |
| "Candy wrapper" forearm | wrist roll not distributed | twist bones |
| Shoulders/elbows twist on stick look | inherited animated roll/hint | deterministic frames + body hint; block stick pitch |
| A stretched "stick" from the hand to the floor | per-bone follow of a chain that natively hangs elsewhere | proximity-based IK for side chains |
| Native pose looks crazy (arms over the head) | first-person animations are authored for the flat camera | normal; IK replaces it |

## Input
- Snap turn: swallow `sThumbRX` in `on_xinput_get_state`, then apply ±angle to `pc:GetControlRotation().Yaw` in `pre_engine_tick` (seated profiles did the same continuously).
- Swallow `sThumbRY` (stick pitch) during gameplay. In VR it only bends the body.
- Aim switching: `vr.set_aim_method(2)` while a weapon is drawn, `1` otherwise.
