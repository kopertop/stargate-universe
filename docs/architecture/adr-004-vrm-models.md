# ADR-004: Use VRM format for character models via @pixiv/three-vrm

**Status**: Accepted
**Date**: 2026-04-03
**Decision**: Use VRM 1.0 as the character model format, loaded via `@pixiv/three-vrm`

## Context

The game needs a character model format for the player (Eli Wallace) and crew
NPCs. The current player visual is a placeholder capsule mesh. The ggez animation
pipeline is fully operational (skeleton extraction, clip playback, animation
graphs) but has no character models to animate. The chosen format must support:

- Humanoid skeletal animation compatible with the ggez `RigDefinition` system
- Dynamic secondary motion (hair, cloth, accessories)
- Facial expressions for the dialogue system
- First-person head hiding for FPS camera mode
- Reasonable file sizes for web delivery
- An accessible authoring pipeline for character artists

### Options Considered

1. **Raw glTF/GLB with custom skeleton conventions** — Maximum control, but
   requires defining and enforcing a custom bone naming convention across all
   models. No built-in support for spring bones, expressions, or first-person
   annotations. Every feature must be custom-built.

2. **Ready Player Me SDK** — Cloud-based avatar platform with Three.js support.
   Provides pre-built characters but requires internet connectivity, introduces
   vendor dependency, and offers limited control over visual style. Not suitable
   for hand-crafted story characters like Rush or Young.

3. **VRM 1.0 via `@pixiv/three-vrm`** — Open standard built on glTF 2.0 with
   standardized humanoid bones, spring bone physics, blend shape expressions,
   first-person annotations, and material definitions. Active Three.js library.
   Large ecosystem of creation tools (VRoid Studio, Blender VRM addon, Unity
   VRM exporter).

4. **Custom binary format** — Maximum optimization potential but enormous
   engineering cost for tooling, export pipeline, and runtime loading. Not
   justified at this project stage.

## Decision

Use **VRM 1.0** loaded via `@pixiv/three-vrm` (npm package). This provides:

- **Standardized humanoid bone mapping**: 55 defined bones with consistent naming.
  A single static mapping table bridges VRM bones to ggez `RigDefinition` joints,
  eliminating per-model retargeting configuration.

- **Spring bone physics** (built-in): Hair, cloth, and accessory secondary motion
  defined per-model in VRM metadata. `@pixiv/three-vrm` provides the runtime
  simulation — no custom physics code required.

- **Blend shape groups** (built-in): Facial expressions (`happy`, `angry`, `sad`,
  `surprised`, `neutral`) and lip sync visemes (`aa`, `ih`, `ou`, `ee`, `oh`)
  defined per-model. Critical for the Crew Dialogue & Choice system.

- **First-person annotations** (built-in): Per-mesh visibility flags for FPS
  rendering. The VRM file itself declares which meshes to hide when the camera
  is inside the character's head — no runtime heuristics needed.

- **glTF 2.0 foundation**: Three.js `GLTFLoader` (already in use for scene assets)
  handles the base format. `@pixiv/three-vrm` extends it with VRM-specific
  parsing. No new loader infrastructure required.

- **Authoring ecosystem**: Characters can be created in VRoid Studio (free,
  beginner-friendly), Blender with the VRM addon (full artist control), or
  exported from Unity via UniVRM. Multiple pipeline options.

- **No vendor lock-in**: VRM is an open specification maintained by the VRM
  Consortium. Models are self-contained files with no cloud dependency.

## Consequences

### Positive

- All five required character features (skeleton, spring bones, expressions,
  first-person, materials) come from a single format and library
- Standardized bone naming means animation clips work across all character
  models without per-model configuration
- The `@pixiv/three-vrm` library is actively maintained and tracks Three.js
  releases closely
- VRM files are valid glTF — they can be inspected with any glTF viewer

### Negative / Trade-offs

- **New dependency**: `@pixiv/three-vrm` adds ~150KB gzipped to the bundle.
  Acceptable for the functionality gained.

- **Skeleton retargeting bridge required**: A one-time implementation to map VRM
  humanoid bone names to ggez `RigDefinition` joint names. Estimated as a small
  module (`vrm-bone-map.ts`) with a static lookup table.

- **MToon shader conversion**: VRM's default MToon toon shader is not compatible
  with the WebGPU PBR render pipeline. Materials must be converted to PBR
  approximations at load time. This is a known pattern — `@pixiv/three-vrm`
  exposes material properties for remapping.

- **File size**: VRM files are 2–5MB per character (mesh + textures + metadata),
  larger than hand-optimized GLB. Mitigated by: loading queue (max 2 concurrent),
  preloading during scene transitions, and mesh/texture sharing for cloned
  instances.

- **Main-thread spring bones**: `@pixiv/three-vrm` spring bone simulation runs
  on the main thread. Must budget carefully (< 1ms per frame). LOD system
  disables spring bones beyond 5m to stay within budget.

### Future Considerations

- If spring bone cost becomes prohibitive with many characters, investigate
  offloading to a Web Worker or replacing with a GPU-driven spring simulation
- VRM 1.0 supports `VRMC_materials_mtoon` — if the art direction shifts toward
  stylized rendering, MToon could be used natively instead of converting to PBR
- The bone mapping table should be reviewed if ggez updates its rig definition
  schema in future versions
