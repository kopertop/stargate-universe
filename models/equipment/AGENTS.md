# models/equipment/

First-pass equippable gear GLBs for the player/NPC equipment slots (#73,
parent #32). Mounted on the Kenney mini-character rig by
`scripts/equipment_mount.gd` (#72) and registered in `data/items.json` (#71).

## Contents

| GLB | Slot | Item id | Bone (Kenney rig fallback) |
|---|---|---|---|
| `marine_helmet.glb` | `head` | `marine_helmet` | `head` |
| `recon_cap.glb` | `head` | `recon_cap` | `head` |
| `tac_vest.glb` | `torso` | `tac_vest` | `torso` |
| `field_backpack.glb` | `back` | `field_backpack` | `torso` (Spine fallback) |
| `combat_boots.glb` | `legs` | `combat_boots` | `root` (Hips fallback) |

Matching inventory icons live in `../../sprites/ui/items/` (`<id>.png`).

## Status: PLACEHOLDER ART — flag for an art pass

The Kenney All-in-1 kit ships **no modular character gear** sized for the
mini-character rig (only full astronaut models + unrelated hard-hat props), so
these are **simple procedural meshes** built to fit the rig and make each slot
testable. They read correctly in silhouette and palette but are not final art.
Replace with proper Kenney/commissioned gear in a later pass.

## How they were built

- `../../tools/build_equipment_gear.py` — Blender headless script that emits all
  five GLBs. Authored in **bone-local space** on the ~0.37u-tall rig (head bone
  y=0.343, torso y=0.176, root y=0; probed from `scott.glb`). Re-run with:
  `blender --background --python tools/build_equipment_gear.py`
- `../../tools/build_equipment_icons.py` — PIL script that emits the 256² icons.
- Each mesh carries a single flat UV landing on a palette swatch of
  `../characters/Textures/colormap.png`, because the mount overrides every gear
  material with that colormap (so GLB gear that loses its baseColorTexture on
  import isn't white). Helmet=olive, cap/backpack=tan, vest/boots=charcoal.

## Conventions

- **Scale**: gear must fit within ~0.6u on every axis (asserted by the
  `equip-assets` smoke suite) so it doesn't dwarf the mini-char.
- **Orientation**: built Z-up in Blender, exported `export_yup=True`; the
  backpack geometry is baked BEHIND the spine (-Z) so `attach_offset` stays ~0.
- **Import sidecar**: after (re)building a GLB, run
  `godot --headless --import` so the `.import` sidecar exists, or `load()`
  fails silently. See memory `[[feedback_sgu_import_sidecar_after_asset_copy]]`.
- **Blender 5.x export**: do NOT pass the removed `export_colors` kwarg — see
  skill `blender5-gltf-export-api-changes`.

## Cross-references

- Mount renderer: `../../scripts/equipment_mount.gd`
- Data model: `../../data/items.json`, `../../data/AGENTS.md`
- Tests: `../../tests/smoke/equipment_assets.gd` (asset validation),
  `../../tests/smoke/equipment_mount.gd` (mount behaviour)
- Project rules: `../../CLAUDE.md`
