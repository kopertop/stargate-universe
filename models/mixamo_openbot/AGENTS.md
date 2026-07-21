# models/mixamo_openbot/

CC0 **OpenBot** (Mixamo-compatible humanoid with finger bones) from
[jwelchgames/Godot4-MixamoLibraries](https://github.com/jwelchgames/Godot4-MixamoLibraries).

## Read this first

**Rifle aim process is documented here:**
[`docs/animation/rifle-aim-host-pipeline.md`](../../docs/animation/rifle-aim-host-pipeline.md)

Do **not** invent shouldered aim with analytic IK on this glTF. Start from
Mixamo **Y-Bot + Rifle Idle**, mount the gun with Child Of, then retarget.

## Why it's here

Mint Meshy Eli is a **24-bone** host (hands are leaves). Industry rifle mounts
attach to `RightHand` / finger bones. OpenBot has ~237 bones including finger
chains — useful as a **retarget target** once we have real Mixamo clips, not as
an IK sandbox.

## Drop Mixamo downloads here

```
incoming/          # gitignored — Mixamo ToS, do not redistribute
  Swat.fbx / X Bot.fbx / Remy.fbx
  Rifle Idle.fbx
  Firing Rifle.fbx
  Walk With Rifle.fbx
  …
```

### Current proof (2026-07-19)

- Builder: `tools/blender_mixamo_rifle_idle.py`
- Output: `Swat_rifle_idle.glb` + `.blend`
- Shots: `screenshots/result/mint_rifle_aim/swat_rifle_idle*.png`
- Godot capture: `tests/capture/openbot_rifle_aim_proof.gd`

## License

Creative Commons (OpenBot). Mixamo animations remain Mixamo ToS if you add them
separately (download from mixamo.com — not redistributed here).

## Failed approach (do not resume)

`tools/blender_openbot_rifle_aim.py` + world-matrix IK on this Rigify-style
export tore the mesh and never produced a shippable shouldered hold. Details in
the pipeline doc failure log.

## NVIDIA ARDY

Realtime text/constraint motion gen ([project](https://research.nvidia.com/labs/sil/projects/ardy/),
[code](https://github.com/nv-tlabs/ardy)). Useful later for generating variants;
**not** the E1 rifle-aim path. See pipeline doc § ARDY.

## Why Mint Eli alone is stuck

Meshy Eli's hand bones are leaves (no finger chains). TwoBoneIK3D on this rig
flips arms behind the back (wrong bone axes vs Mixamo). Current gameplay path:
Idle feet + Meshy shoot-clip arm overlay + rifle seated between the hands.
Upgrade the **host + clip** before chasing realistic grip on Eli.
