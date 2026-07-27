---
name: godot-mixamo-rifle-combat-showcase
description: |
  Replicate the working Mixamo Swat rifle combat showcase for Godot 4.6:
  holstered unarmed idle, slowed Running loco, RMB aim with Shoot_Rifle /
  crouch / aim-only strafe, camera-forward shots, dual rifle visibility, hip
  location stripping, and idle-only foot lift. Use when rebuilding
  Swat_rifle_combat.glb, wiring rifle_combat_showcase.gd, fixing boots in
  floor / ghost grip / shoot-the-floor / aim+move sink, or adding Mixamo
  combat locomotion. Canonical doc: docs/animation/mixamo-rifle-combat-showcase.md
author: Cursor / cmoyer
version: 1.0.0
date: 2026-07-21
---

# Mixamo rifle combat showcase (Godot)

Full replication guide:

`docs/animation/mixamo-rifle-combat-showcase.md`

Aim-authoring law (do not invent IK grip):

`docs/animation/rifle-aim-host-pipeline.md`

## Must-follow

1. Holster idle = `Unarmed_Idle`, never `Rifle_Idle`.
2. Holstered WASD = `Running` at `speed_scale` 0.55 (walk) / 1.0 (sprint). Not Shooter-Pack `Walking`.
3. Strafe clips only while aiming + lateral move.
4. Aim+move forward = `Shoot_Rifle` (not `Walk_With_Rifle`).
5. Strip Mixamo hip **location** on shoot/loco/strafe or the mesh sinks under the floor.
6. Align feet once at spawn; `IDLE_EXTRA_LIFT` only for standing holster idle.
7. Shot ray = camera forward while aiming.
8. Two meshes: `rifle` (RightHand) + `rifle_holster` (Spine2); visibility swap; exact names.
9. Rebuild: `tools/blender_mixamo_rifle_combat.py` → local `Swat_rifle_combat.glb` (gitignored ToS).
10. Play: `Godot --path . res://scenes/rifle_combat_showcase.tscn`

## Quick diagnosis

| Bug | Fix |
|---|---|
| Ghost arms on holster | Wrong idle clip |
| Shoot floor | Camera aim, not barrel |
| Aim+move under floor | Hip loc strip + no per-clip realign |
| Idle boots buried | `IDLE_EXTRA_LIFT` |
| Holstered walk looks armed | Slowed `Running` |
