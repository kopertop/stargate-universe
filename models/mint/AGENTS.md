# models/mint/

Mint-native character + asset pipeline. **All new characters and (going
forward) game assets are generated via Mint MCP**, downloaded here, and
registered in `../../data/mint/characters.json`.

## Layout

```
models/mint/<slug>/
  <slug>.glb              # original Mint mesh (often unrigged)
  <slug>_animated.glb     # rigged body (may have one placeholder clip)
  <slug>_preview.webp     # Mint preview image
  mint.json               # provenance (model id, chat url, batch id)
  clips/
    Idle.glb              # each file = full rig + ONE animation
    Casual_Walk_inplace.glb
    …

models/mint/props/
  sidearm.glb / rifle.glb / repair_tool.glb / stun_baton.glb / kino.glb
  mint.json               # Destiny Character Props pack provenance
```

## Runtime

- `scripts/mint_character.gd` — loads registry entry, merges clip GLBs into one
  `AnimationPlayer` + AnimationTree (loco gait, jump/fire/draw oneshots, aim).
- `scripts/mint_held_weapon.gd` — holster↔hand weapon mesh + grip.
- `scripts/mint_hand_grip.gd` — finger bones or procedural finger proxies.
- `data/mint/weapons.json` — studio weapon library.
- `scenes/mint_character_lab.tscn` — Animation Studio for stick/aim/fire tests.
- Skill: `.claude/skills/add-character/` — Mint generate → download → register → lab.

## Clip merge normalization (required)

Mint clips disagree on Hips **scale** and **height**. Blending them raw looks
like the character grows/shrinks. On merge, `MintCharacter` always:

1. Strips all `TYPE_SCALE_3D` tracks.
2. Makes Hips XZ in-place (subtract frame-0 XZ).
3. Offsets Hips Y so frame-0 matches Idle’s baseline.
4. For jump clips: removes Hips **position** entirely (code hop owns vertical).

## Equipment mounts

Studio weapons live in `../../data/mint/weapons.json` (sidearm, rifle, repair
tool, stun baton, kino). Each entry prefers `mint_glb` when present on disk,
else Quaternius `glb` fallback. Character registry may still carry a `sidearm`
block for mount overrides.

Runtime: `MintCharacter.equip_weapon(id)` → `MintHeldWeapon` mounts.
Animation Studio: weapon dropdown + `[` `]` / D-pad / keys `1-5` to swap
seamlessly (re-equips + re-draws if aiming).

State machine: `HOLSTERED → DRAWING → AIMED → FIRING → AIMED → HOLSTERING → HOLSTERED`.
Gun reparents mid-draw (~40% of draw clip). Clip roles (draw/aim/fire) swap
with the selected weapon.

## Finger bones

Mint’s Meshy animation catalog emits a **24-bone body rig** (hands are leaves).
`tools/mint_add_finger_bones.py` can insert Godot humanoid finger chains, but
a bad bind (over-weighted verts / wrong bone rests) will spaghetti the mesh —
so **Idle currently ships without that post-process**.

`MintHandGrip` uses skinned finger bones only when the bind passes a sanity
check; otherwise it falls back to subtle hand-leaf bias (no capsule proxies —
those read as junk on Mint mittens). Never drive finger bones that fail the
bind check. Idle currently ships as the clean 24-bone Meshy host.

## Do not

- Add new Quaternius / Kenney mini-character profiles for crew.
- Runtime-load Mint CDN URLs — always download into this tree.
- Bake weapons into clip GLBs — keep one mesh + two mounts.

## Cross-references

- Mint MCP: https://mcp.mint.gg/
- Docs: https://docs.mint.gg/integrations/mcp
- Project rules: `../../CLAUDE.md`
