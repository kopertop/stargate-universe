# Mixamo rifle combat showcase (replication guide)

**Status:** working gameplay-style loop (2026-07-21). User-confirmed look.

**Companion:** [`rifle-aim-host-pipeline.md`](./rifle-aim-host-pipeline.md) — still the
law for *aim authoring*. This doc is the **combat pack + Godot controller** that
sits on top of that pipeline.

**Do not redistribute** Mixamo Swat skin / clips (`Swat_*.glb` is gitignored).
Rebuild locally. The procedural M4 proxy is ours (CC0-style project asset).

---

## What “perfect” means here

| State | Animation | Weapon mesh |
|---|---|---|
| Holster idle | `Unarmed_Idle` (fallback `Breathing_Idle`) | `rifle_holster` on Spine2 visible; hand `rifle` hidden |
| Holster walk / run | **Same** `Running` clip; walk = `speed_scale 0.55`, sprint = `1.0` | holstered |
| Aim stand (no move) | Auto-crouch: `Rifle_Crouched_Idle_Aim` / kneel set | hand `rifle` drawn |
| Aim + fire crouch | `Fire_Rifle_Crouched` | drawn |
| Aim + move forward/back | `Shoot_Rifle` (not `Walk_With_Rifle`) | drawn |
| Aim + strafe | `Strafe` / `Strafe_Alt` only while aiming | drawn |

Controls: WASD · Shift sprint · Space jump · mouse look · RMB aim · LMB fire
(only while aiming) · Esc releases mouse / quits.

Scene: `scenes/rifle_combat_showcase.tscn`  
Script: `scripts/rifle_combat_showcase.gd`  
Gameplay avatar: `scripts/mixamo_combat_avatar.gd` (mounted by `player.gd` when
`use_mixamo_avatar` and the local pack exists)  
Builder: `tools/blender_mixamo_rifle_combat.py`  
Output (local): `models/mixamo_openbot/Swat_rifle_combat.glb`

---

## Hard rules (learned the expensive way)

### 1. Pose comes from Mixamo clips — never invent holster grip with bone hacks

Hiding the hand rifle does **not** fix arms. `Rifle_Idle` still drives a ghost
grip. Holstered idle must be an **unarmed** clip.

### 2. Gameplay aim is camera-forward — never barrel-forward for the ray

If the shot ray follows animated muzzle axes, loco / low-gun clips “shoot the
floor.” Use `-camera.basis.z` while aiming. Barrel is for VFX seat only.

### 3. Strip Mixamo hip **location** on loco + shoot clips

Even “in place” Mixamo FBXs often key `mixamorig:Hips.location`. Unstripped
`Shoot_Rifle` planted feet ~1.4 m below `Running` and buried the character when
aim+move. Strip hip loc in Blender (or freeze hip POSITION tracks to key 0 in
Godot via `_lock_root_translation_tracks`). Keep hip **rotation**.

### 4. Do not re-align feet every clip change

One spawn-time foot align against the floor capsule is enough. Re-measuring on
`Shoot_Rifle` / crouch (higher ankles) shoves `_host.position.y` down under the
floor. Lock `_host_floor_y` after idle align.

### 5. Idle vs loco sole height differs — bias idle only

Ankle bones ≠ boot soles. Align with `FOOT_SOLE_CLEARANCE` (~0.13). Unarmed idle
still plants lower than `Running` — apply `IDLE_EXTRA_LIFT` (~0.045) **only**
while holstered and nearly still. Do not bake that lift into the run plant.

### 6. Holstered loco = slowed Running — not Shooter-Pack `Walking`

`Walking` from the Shooter Pack reads as gun-ready. Forward/strafe/back while
**holstered** all use `Running` at reduced `AnimationPlayer.speed_scale`.
Strafe Mixamo clips are **aim-only**.

### 7. Two rifle meshes, visibility swap — no runtime reparent

Blender authors:

- `rifle` → bone-parented `mixamorig:RightHand` (combat)
- `rifle_holster` → bone-parented `mixamorig:Spine2` (back)

Godot toggles `.visible` only. Exact name match (`rifle`, not substring) — the
packed root is named like `Swat_rifle_combat` and will false-match “rifle”.

### 8. Mixamo does not ship a rifle mesh

Build a procedural proxy with grip→support span locked to measured Rifle Idle
palm span (~32.2 cm). See `MIXAMO_HAND_SPAN` in the builder. Export
`mixamo_virtual_rifle.glb` (committable) separately from the Swat host GLB
(gitignored / ToS).

### 9. `_pick_clip` must prefer exact names

Fuzzy `find("Walking")` / first-available fallback can grab the wrong library
entry. Exact match only; empty string if missing.

### 10. CharacterBody3D: drop once, then free loco — no post-land freeze for play

Showcase drops with gravity, plants, aligns feet, **then** allows WASD. Do not
pin XZ every physics frame after spawn (that was the old auto-demo freeze).

---

## Rebuild recipe

### A. Collect FBXs into `models/mixamo_openbot/incoming/` (gitignored)

Required / used names (Mixamo download titles → builder keys):

| Incoming file | Action name |
|---|---|
| `Swat.fbx` | host |
| `Unarmed Idle 01.fbx` | `Unarmed_Idle` |
| `Breathing Idle.fbx` | `Breathing_Idle` |
| `Walking.fbx` | `Walking` (kept in pack; **not** used for holstered loco) |
| `Running.fbx` | `Running` |
| `Strafe.fbx` / `Strafe_Alt.fbx` | `Strafe` / `Strafe_Alt` |
| `Shoot Rifle.fbx` | `Shoot_Rifle` |
| `Firing Rifle.fbx` | `Firing_Rifle` |
| `Fire Rifle While Crouched.fbx` | `Fire_Rifle_Crouched` |
| crouch / kneel rifle set | crouch aim/fire |
| optional rifle loco | `Walk_With_Rifle`, etc. (avoid for holstered) |

### B. Blender build

```bash
# Headless, or open Swat_rifle_combat.blend and extend via MCP:
blender -b -P tools/blender_mixamo_rifle_combat.py
```

Builder must:

1. Import host + clips; strip `.scale` fcurves; `inherit_scale = NONE` on bones.
2. Strip hip **location** on loco/shoot/strafe/crouch-fire clips.
3. Ground once across clips (or accept Godot sole align).
4. Build / seat proxy rifle on RightHand; **duplicate** as `rifle_holster` on
   `mixamorig:Spine2` (builder bakes the signed-off local transform).
5. Push each action to an NLA track named like the action; export GLB with
   `export_animation_mode=NLA_TRACKS` (or equivalent NLA strip export).

Incremental MCP path used in production: open existing `.blend`, import new
FBX → rename action → strip hips → NLA track → `export_scene.gltf`.

### C. Godot

```bash
Godot --path . --headless --import
Godot --path . res://scenes/rifle_combat_showcase.tscn
```

Confirm console `anims=` includes `Unarmed_Idle`, `Running`, `Shoot_Rifle`,
`Strafe`, `Strafe_Alt`, crouch set. Confirm `holster_mesh=true`.

---

## Controller state machine (Godot)

Pseudo-logic in `rifle_combat_showcase.gd`:

```
aiming = RMB
moving = WASD magnitude > epsilon
sprint = Shift

if not aiming:
  holstered = true
  clip = Idle if not moving else Running @ (sprint ? 1.0 : 0.55)
else:
  holstered = false
  if not moving: crouch aim / crouch fire
  elif |strafe| > 0.45: Strafe / Strafe_Alt
  else: Shoot_Rifle

fire only if aiming and LMB
aim ray = -camera.forward
aim UI visible only if aiming
host.y = host_floor_y + (IDLE_EXTRA_LIFT if holster idle else 0)
```

Camera: yaw on look, pitch orbits OTS; body faces look while aiming, faces
wish dir while holstered.

---

## Failure → fix cheat sheet

| Symptom | Cause | Fix |
|---|---|---|
| Ghost grip, rifle on back | Playing `Rifle_Idle` while holstered | Switch to `Unarmed_Idle` |
| Shots into floor | Barrel-based aim | Camera-forward aim |
| Falls under floor on aim+move | Hip loc on `Shoot_Rifle` and/or per-clip foot realign | Strip hip loc; align once |
| Boots in floor only when idle | Idle sole lower than run | `IDLE_EXTRA_LIFT` |
| Holstered strafe/walk looks armed | Using Shooter Pack `Walking` | Use slowed `Running` |
| Wrong mesh toggled | Substring find on “rifle” | Exact `rifle` / `rifle_holster` |
| Floor bounce / jitter | Gravity + y-snap fight after land | Plant once; free loco after spawn |

---

## Related paths

- Idle proof pipeline: `tools/blender_mixamo_rifle_idle.py`, `Swat_rifle_idle.glb`
- Combat builder: `tools/blender_mixamo_rifle_combat.py`
- Palm span measure: `tools/blender_measure_mixamo_hand_span.py`
- Folder notes: `models/mixamo_openbot/AGENTS.md`
- Claude skill (user scope): `godot-mixamo-rifle-combat-showcase`

---

## Changelog

- **2026-07-21** — Gameplay controls, unarmed holster idle, slowed Running loco,
  Shoot_Rifle + aim-only strafe, hip-loc strip, idle foot bias, camera aim,
  dual rifle visibility. User sign-off: “THIS LOOKS PERFECT.”
