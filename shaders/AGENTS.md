# shaders/

Hand-written `.gdshader` files + the `ShaderMaterial` `.tres` variants that bind
them. These give the game's hero props their look beyond flat `StandardMaterial3D`.

## Contents

- `ancient_metal.gdshader` — the shared **Ancient-metal** look: procedural
  beveled panel grid, recessed seams, edge wear, and a triplanar-sampled fine
  detail set (normal + roughness). Glowing seams (`seam_emission`) drive the
  gate's amber/orange chevron light.
- `ancient_metal_ring.tres` / `_band.tres` / `_chevron.tres` — per-part tinted
  variants wired into `objects/stargate.gd` (outer ring / glyph band / chevrons).
- `event_horizon.gdshader` + `event_horizon.tres` — animated cyan "puddle" for
  the active gate (scrolling noise + Fresnel rim + radial pulse). Additive,
  unshaded. The `OmniLight3D` spill is still driven from `stargate.gd`.

## Conventions

- **Triplanar / world-space.** The hero meshes are procedural primitives with
  engine-generated UVs that can't tile a panel texture. Everything is sampled in
  WORLD space and blended by world-normal weights, so one material drops onto any
  prop and `panel_scale` (world units) stays consistent regardless of mesh scale.
  Tune once on the ring, reuse everywhere.
- **Detail set lives in `../textures/ancient-metal/`** as seamless
  `NoiseTexture2D` `.tres` (no `.png.import` sidecar problem; swappable for a
  hand-authored PNG later — the shader just takes `sampler2D`).
- **Tint per-part via the `.tres` variants**, not `duplicate()` in code.
- Shader compile errors surface as stderr on scene boot — `tests/run.sh scene`
  (which loads `scenes/gate_room.tscn`) validates the shaders parse.

## Cross-references

- Project rules: `../CLAUDE.md`
- Concept reference: `../design/concept-art/materials/ancient-metal-pbr-sheet.png`
- Detail textures: `../textures/ancient-metal/`
- Stargate prop: `../objects/stargate.gd`
