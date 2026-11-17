---
name: uevr-profile
description: Build, fix or extend UEVR (Unreal Engine VR injector by praydog) game profiles. Covers 6DOF motion controls, Lua scripting for UEVR, UObjectHook attachments, visible full body with IK arms on the motion controllers, weapon-in-hand, snap turn, live in-game debugging with screenshots, offline Lua tests and packaging/publishing a profile. Use whenever the user mentions UEVR, an UnrealVRMod profile, making a flat UE4/UE5 game playable in VR, or motion controls / hands / body for a UE game.
---

# UEVR profile development

A UEVR profile is the folder `%APPDATA%\UnrealVRMod\<Exe-Name>\`. It contains `config.txt` (UEVR settings), `cameras.txt`, `cvars_*.txt`, `uobjecthook/*.json` (persistent attach/hide states), `scripts/*.lua` (auto-run Lua) and `data/` (files the Lua side can read and write). Users install it with UEVRInjector → **Import Config** (a zip with forward-slash paths and these files at the root).

Read these before writing code:
- `reference/lua-api-facts.md`: verified API behaviour (the docs are wrong in places).
- `reference/body-ik-architecture.md`: the proven full-body + IK design and the failure table.
- `reference/live-debugging.md`: how to debug a running game yourself.

Templates (copy them into the profile):
- `templates/loader.lua` → `scripts/`. It hot-reloads `data/mod_core.lua`; no "Reset scripts" needed after the first install.
- `templates/core_skeleton.lua` → `data/mod_core.lua`. Includes config, a log file, the debug channel with eval/status/debug camera, controller helper components, render-only edits with restore, snap turn and the UI panel.
- `templates/uemath.lua` → `data/`. UE-convention quaternions/rotators, two-bone IK, swing-twist, axis frames. Tested: `templates/test_uemath.lua`.
- `templates/mock_uevr.lua` + `tools/run_smoke.py`: offline tests (`pip install lupa`).

## Workflow

1. **Recon (read only).**
   - Unpack any existing profiles into a scratch folder. Read their `config.txt`, the `uobjecthook/*.json` (what is attached or hidden) and their scripts.
   - `log.txt` shows the engine version (`Found version 4.27`).
   - `Binaries/Win64/*.pdb` or `strings` on the exe reveal native class and function names.
   - Install the loader + skeleton core, then dump the pawn: its components (class, attach parent, socket, mesh asset, AnimClass), the full bone list with parents (`GetParentBone`), and the weapon. Write it all to `data/*.json` with `json.dump_file`.
   - Build the bone tree offline and find the hand, twist, camera, weapon and side-chain bones.
2. **Decide the approach** (see the architecture reference).
   - Arms-only rig: pinning the mesh by the hand bone can be enough.
   - Full-body rig: use a PoseableMesh copy with IK.
   - Always: aim switching (`vr.set_aim_method`), snap turn, attach lerp off, block stick pitch.
3. **Implement in the core.**
   - Do render-only work in `post_calculate_stereo_view_offset` (first eye) and restore in `pre_engine_tick`.
   - Use engine `dt`, never `os.clock()`.
   - Wrap every engine call in `pcall` and log once per distinct error.
4. **Test offline.** Run math tests and a mock scenario: reach, orientation, bone lengths, independence from animation, reload/cleanup. Then deploy by copying the core into `data/`.
5. **Debug live yourself** (the user does not need to wear the headset).
   - The HMD session must be active: check `hmd_active` in the status file.
   - Use the debug camera, simulated controllers, `hide_parts` bisection, `eval` measurements and screenshots, then compare against native with `show_game_mesh`.
   - Ask the user only for things a human has to do (pressing in-game buttons, judging feel in the headset), and tell them exactly what you are about to capture.
6. **Hand over.** Clear the debug JSON (`{}`), restore `slomo 1`, and tell the user what you verified versus what only the headset can tell.
7. **Package/publish.**
   - Repo layout: `profile/<Exe>/`, `dev/tests`, `dev/tools`, `tools/build_release.py`, README (installation, controls, settings, troubleshooting with the log/dump files, credits), CHANGELOG, LICENSE.
   - Keep third-party profiles and scratch out of git (`.gitignore`). Force LF for `.sh`/`.lua` via `.gitattributes`.
   - Scan for personal data before pushing, and ask the user which commit identity to use for a public repo.

## Must-know pitfalls
- In stereo callbacks `rotation` is a `Vector3f`: yaw is `rotation.y`, not `.yaw`. UE4 view indices are 1 and 2.
- Under controller aim, UEVR rewrites `ControlRotation`, so the **game camera follows the controller**. Never use it as a reference frame for the body or hands.
- First-person animations are authored for the flat camera (Scorn holds both arms over the head). Expect the native pose to look wrong from outside.
- Double-moving things: followers using master pose already follow the IK pose, so don't also carry them.
- Side chains rooted at the skeleton root (parasite arms, hoses, held props) don't follow arm IK. Handle them by proximity.
- **Never trigger gameplay functions from Lua to test** (they can soft-lock the character). Synthetic keyboard/XInput input does not reach the game.
- Quest headsets stop the OpenXR session when idle. Then no stereo callbacks run, so your code looks "dead".
- In the Bash tool, large heredocs with mixed quotes break. Write files with the Write tool instead.

Case study with full source, tests and tools: https://github.com/pau1is/uevr_scorn_6DOF
