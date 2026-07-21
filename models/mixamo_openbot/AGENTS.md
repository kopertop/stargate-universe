# models/mixamo_openbot/

CC0 **OpenBot** (Mixamo-compatible humanoid with finger bones) from
[jwelchgames/Godot4-MixamoLibraries](https://github.com/jwelchgames/Godot4-MixamoLibraries).

## Read this first

1. **Rifle aim process:** [`docs/animation/rifle-aim-host-pipeline.md`](../../docs/animation/rifle-aim-host-pipeline.md)
2. **Combat showcase replication (signed off 2026-07-21):**  
   [`docs/animation/mixamo-rifle-combat-showcase.md`](../../docs/animation/mixamo-rifle-combat-showcase.md)

Do **not** invent shouldered aim with analytic IK on this glTF. Start from
Mixamo clips, mount the gun, then drive Godot with camera-forward aim.

## Why it's here

Mint Meshy Eli is a **24-bone** host (hands are leaves). Industry rifle mounts
attach to `RightHand` / finger bones. OpenBot / Mixamo Swat prove the mount +
clip path before Eli catches up.

## Drop Mixamo downloads here

```
incoming/          # gitignored — Mixamo ToS, do not redistribute
  Swat.fbx
  Unarmed Idle 01.fbx / Breathing Idle.fbx
  Running.fbx / Walking.fbx / Strafe*.fbx
  Shoot Rifle.fbx / Firing Rifle.fbx / Fire Rifle While Crouched.fbx
  …
```

### Idle proof (2026-07-19)

- Builder: `tools/blender_mixamo_rifle_idle.py`
- Output: `Swat_rifle_idle.glb` + `.blend` (local — Mixamo ToS, gitignored)

### Combat showcase (2026-07-21) — look signed off

- Builder: `tools/blender_mixamo_rifle_combat.py` → `Swat_rifle_combat.glb` (local)
- Prop: procedural Mixamo-span M4 (`mixamo_virtual_rifle.glb`, grip span ≈ 32.2cm)
- Dual meshes in GLB: `rifle` (RightHand) + `rifle_holster` (Spine2)
- Playable: `scenes/rifle_combat_showcase.tscn`
- Controls: WASD · Shift sprint · Space jump · mouse look · RMB aim · LMB fire
- Holstered loco: slowed `Running` (not Shooter-Pack `Walking`)
- Aim+move: `Shoot_Rifle`; aim+strafe: `Strafe*`; aim stand: auto-crouch set
- Critical: strip hip location on shoot/loco; idle-only `IDLE_EXTRA_LIFT`; camera aim

```bash
Godot --path . --headless --import
Godot --path . res://scenes/rifle_combat_showcase.tscn
```

## License

Creative Commons (OpenBot). Mixamo animations remain Mixamo ToS if you add them
separately (download from mixamo.com — not redistributed here). `Swat_*` outputs
are gitignored for that reason.

## Failed approach (do not resume)

`tools/blender_openbot_rifle_aim.py` + world-matrix IK — see pipeline failure log.
