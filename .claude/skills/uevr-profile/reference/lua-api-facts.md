# UEVR Lua API — verified facts

Verified against the UEVR source (`lua-api/lib/src/ScriptContext.cpp`, `ScriptUtility.cpp`, `src/mods/UObjectHook.cpp`) and in a live UE 4.27 game (Scorn, UEVR nightly 2026-05, revision 38c73f3). Where the docs (docs.uevr.io) disagree, the source is right.

## Values and calls
- `FVector` **and** `FRotator` return values/properties come back as `Vector3f` (UE5: `Vector3d`). Fields `x,y,z` also have the aliases `X,Y,Z` and `Pitch,Yaw,Roll` (Pitch = x, Yaw = y, Roll = z). Other structs come back as `StructObject`.
- Struct **arguments** can be Lua tables keyed by property name: `{X=..,Y=..,Z=..}`, `{Pitch=..,Yaw=..,Roll=..}`. Nested tables work too.
- **Out params**: pass `{}` to ignore one, e.g. `K2_SetWorldLocationAndRotation(loc, rot, false, {}, true)`. A filled table gets `t.result`.
- `FName` params accept Lua strings. `FName` return values are objects; use `:to_string()`.
- Property reads on live objects return **pointers** (writes go through) for Vector/Rotator. Copy the numbers if you need a snapshot (`{X=v.X,...}`).
- `obj:get_address()` is the reliable identity check. `UEVR_UObjectHook.exists(obj)` tells you whether an object is still alive.
- `api:add_component_by_class(actor, class)` adds and registers a component; it is attached to the root.
- Calling static functions: `api:find_uobject("Class /Script/Engine.GameplayStatics"):get_class_default_object():Fn(...)`.
- Walking reflection: `obj:get_class()`, `c:get_children()` (fields; `:get_next()`), `c:get_super_struct()`. This is how you discover functions like `TryReload`.

## Callbacks
- `on_pre_engine_tick(engine, dt)`, `on_post_engine_tick`: `dt` is engine delta time. **Don't use `os.clock()`**: it counts process CPU time over all threads.
- `on_pre/post_calculate_stereo_view_offset(device, view_index, world_to_meters, position, rotation, is_double)`:
  - On UE4, `position`/`rotation` are **`Vector3f` pointers**, not `UEVR_Rotatorf`. Read yaw as `rotation.y` / `rotation.Yaw`; `rotation.yaw` is **nil**. Writing to them moves the eye (debug camera).
  - UE4 view indices are **1 and 2**. UObjectHook moves its attached components in **pre** for `(view_index + 1) % 2 == 0`, i.e. view 1. Run your own per-frame pose work in **post** for `view_index % 2 == 1`: you see this frame's controller pose, and rendering still picks your changes up.
  - These callbacks only fire while the **HMD session is active**. When a Quest goes to sleep (OpenXR `XR_SESSION_STATE_STOPPING` in log.txt), none of the render code runs.
- `on_xinput_get_state(retval, user_index, state)`: `state.Gamepad.sThumbRX` etc. are writable. Filter with `vr.get_lowest_xinput_index()`. It only fires while UEVR feeds the virtual pad, i.e. while controllers are in use (`vr.is_using_controllers()`; the inactivity timer is `VR_MotionControlsInactivityTimer`).
- `on_draw_ui()`: imgui widgets show in the UEVR menu → Script UI. `imgui.combo` is 1-based. Getters return `changed, value`.
- `on_script_reset()`: clean up components you added, motion controller states and visibility changes.

## UObjectHook from Lua
- `UEVR_UObjectHook.get_or_add_motion_controller_state(comp)` → `state:set_hand(0 left | 1 right | 2 HMD)`, `state:set_permanent(true)`. The docs spell it `set_permanant`; try both. `set_location_offset(UEVR_Vector3f)`, `set_rotation_offset(UEVR_Quaternionf)` (set `.x .y .z .w` by name). `UEVR_UObjectHook.remove_motion_controller_state(comp)`.
- How offsets apply: `rot = hand_rot * inverse(rotation_offset)`, `loc = hand_pos + R(adjusted_rot) * location_offset` (glm↔UE axis conversion inside). Non-permanent states restore the component at end of tick.
- **World-space controller pose recipe:** add an empty SceneComponent to the pawn, attach it with a permanent motion controller state, then read `K2_GetComponentLocation/Rotation` in post_calc. The rotation is the controller **aim** pose; the position is the **grip**.
- UObjectHook attach lerp (`UObjectHook_AttachLerpEnabled`) smooths controller poses and adds noticeable latency. Turn it off: `vr.set_mod_value("UObjectHook_AttachLerpEnabled","false")`.

## Files
- `json.load_file(name)` / `json.dump_file(name, tbl, indent)` are relative to `UnrealVRMod/<Game>/data/`. Empty Lua tables are dumped as `null`.
- `fs.read(name)` / `fs.write(name, str)` use the same folder. `io` can reach `scripts/` through the `$scripts` token.
- `print()` does **not** reach UEVR's `log.txt` (unless `LuaLoader_LogToDisk`). Write your own log file with `fs.write`.
- Every `*.lua` in `scripts/` is auto-run. Keep library/core code in `data/` and `load(fs.read(...))` it.
- A script cannot trigger a LuaLoader reset → use the hot-reload loader (`templates/loader.lua`).

## Useful engine calls (UE 4.27)
- Skeleton: `GetNumBones`, `GetBoneName(i)`, `GetParentBone(name)`, `GetBoneIndex(name)`, `GetSocketLocation/Rotation(bone)`, `HideBoneByName(bone, 0)`.
- Poseable: `CopyPoseFromSkeletalComponent(src)` (same mesh asset), `Get/SetBone{Location,Rotation}ByName(bone, v, 0 = world)`. Setting a bone keeps the children's local transforms; reads are recomputed immediately.
- Followers: `SetMasterPoseComponent(leader, false)`. Only use it on components whose mesh shares the skeleton (`GetBoneIndex(root) >= 0`); otherwise they freeze in ref pose.
- Hide without stopping animation: `SetRenderInMainPass(false)` and `VisibilityBasedAnimTickOption = 0`.
- Time: `api:execute_command("slomo 0.2")` (reset with `slomo 1`).
- `vr.set_aim_method(1 head | 2 right controller)`, `vr.is_hmd_active()`, `vr.is_using_controllers()`, `vr.set_mod_value(key, str)`, `vr:get_mod_value(key)`.
