# Changelog

## 1.1.0 — 2026-11-17

- Native animations during interactions: at consoles, with items (inventory, healing) and in scripted events (grabbed, glory kill, parasite lock, ...) the game's animation owns the body and the arms. IK, body yaw from the headset and stick turning are paused and blend back in smoothly afterwards. Detected from the game's `CharacterState`. Toggle: **Body / arms → Native animation during interactions** (on by default).
- During interactions the body and hands no longer slide away from the console when you turn or move your head. UEVR roomscale movement (which drags the pawn after the headset) is paused while the animation owns the body and restored right after. A marker file restores it if the game exits mid-interaction.
- During interactions the eyes stay on the neutral point of the game's camera orbit (the camera bone swings ~17 cm around the neck with `CameraYaw`).
- The character state is shown in the menu, the log and the dump (for bug reports).
- Settings saved by 1.0.0 are kept.

## 1.0.0 — 2026-11-17

First public release.

- Full visible body (PoseableMesh copy of the game mesh) that turns with the headset.
- Two-bone IK for both arms onto the motion controllers. The hand frame is built from the finger bones, so the barrel follows the controller.
- Deterministic shoulder and elbow orientation plus forearm twist distribution: no twisting from walk/look animations, no "candy wrapper".
- Weapon and body attachments follow the IK pose via master pose, so reload / recoil / weapon insert animations work.
- Parasite arms and the ammo apparatus stay on the body and reach for the nearest hand during hand-over animations.
- Snap turn (45°, configurable) and smooth turn on the right stick; right stick pitch blocked in gameplay.
- Aim switching: head without a weapon, right controller with a weapon.
- Settings panel in the UEVR menu ("Script UI → Scorn VR").
- Hot-reloading loader (`scripts/scorn_vr.lua` → `data/scorn_vr_core.lua`).
- Legacy "weapon only" mode with the original Tensai37 offsets.
