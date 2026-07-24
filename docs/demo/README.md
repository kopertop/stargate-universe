# Mixamo ship combat demo

Recorded gameplay (loco → RMB aim → LMB fire) boots `gate_room` with
`MixamoCombatAvatar`.

## Artifacts (local / gitignored binaries)

| File | Notes |
|---|---|
| `screenshots/result/mixamo_combat_demo.mp4` | Primary 1280×720 @ 30fps Movie Maker capture (~12.5s) |
| `docs/demo/mixamo_combat_demo.mp4` | Optional copy (gitignored) |
| `docs/demo/mixamo_combat_demo_idle.jpg` | Holster idle beat (committed) |
| `docs/demo/mixamo_combat_demo_fire.jpg` | Aim/fire beat with crosshair (committed) |

## Re-record

```bash
# Preferred (Adobe Mixamo Swat + Shooter Pack in incoming/):
blender -b -P tools/blender_mixamo_rifle_combat.py

# Cloud / no-incoming fallback (Mixamo-rigged proxy mannequin from vrm/anim_src):
blender -b -P tools/blender_mixamo_proxy_combat.py

godot --headless --path . --import
tools/record_mixamo_combat_demo.sh
```

Combat rules: `docs/animation/mixamo-rifle-combat-showcase.md`.
