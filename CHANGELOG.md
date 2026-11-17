# Changelog

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
