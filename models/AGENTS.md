# models/

3D models (`.glb`) sourced from Kenney's CC0 asset libraries plus the
project-specific starter-kit bootstrap.

## Contents

- Top-level `.glb` files — Kenney 3D Platformer starter kit (the
  `KenneyNL/Starter-Kit-3D-Platformer` bootstrap, see CLAUDE.md).
- `characters/` — Mini-character GLBs used for NPCs (Scott, Rush, Eli,
  Greer, etc.). Each character is one Kenney "Mini Characters 1" slot.
- `characters/Textures/colormap.png` — External colormap referenced by every
  mini-character GLB. **Must travel with the GLB** or meshes render white.
- `props/space_station_kit/` — Larger sci-fi prop pack (Kenney Space Station).
- `sci-fi/space-station/floor.glb` — Modular floor tile used by `gate_room.gd`.

## Conventions

- **Kenney mini-character gotcha**: GLBs reference `Textures/colormap.png` by
  RELATIVE path. Copy the colormap alongside the GLB or the model imports
  white. See memory `[[feedback_kenney_mini_chars_colormap]]`.
- **Floor tile Y origin**: Kenney `floor.glb` has its origin at the BOTTOM
  with visual top at y=0.3. Match the collider top to y=0.3 or the player
  sinks. See memory `[[feedback_kenney_floor_tile_y_convention]]`.
- **PNG sidecar**: If you add an image without the Godot editor running,
  generate the `.import` sidecar before headless code tries to `load()` it.
  See memory `[[godot-png-no-import-sidecar]]`.
- **Skinned mesh AABB**: glTF reports pre-skinning AABB → characters sink to
  belly-button if you trust it. Lift Model node, bump camera follow_height.
  See memory `[[feedback_gltf_skinned_mesh_aabb]]`.

## Cross-references

- Project rules: `../CLAUDE.md`
- Kenney catalog (cross-project): memory `[[reference_kenney_library_catalog]]`
- NPC spawn code that applies the colormap fix: `../scripts/npc.gd`
  (`apply_kenney_colormap`)
- Door + room geometry: `../scripts/room_builder.gd`
