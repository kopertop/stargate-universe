# Ancient Metal — PBR shader + texture upgrade for hero props

## Context

We have a new concept/material-reference sheet ("STARGATE UNIVERSE — ANCIENT METAL SHADER, PBR
real-time"): a paneled, weathered, beveled dark-steel material with cyan-lit console screens,
shown on a sphere, a control table, consoles, and a stargate segment, plus thumbnail
albedo/normal/roughness/metallic/AO maps.

Today every hero prop uses flat-color `StandardMaterial3D` built in code — **no `.gdshader`
files exist anywhere in the repo**, and only simple diffuse overlays (`textures/rusted-metal.png`)
are used. The props read as untextured primitives. Goal: introduce a reusable **Ancient-metal
shader** (procedural panels/seams/wear) blended with **one fine detail set**, and prove it on the
**Stargate first** (vertical slice) before rolling the same shared material out to the control
table, consoles, and ship panels.

Decisions already made with the user:
- **Hybrid**: procedural triplanar `.gdshader` + one tiling detail set (normal + roughness).
- **Stargate vertical slice first**, then roll out.
- Reference image saved under **`design/concept-art/materials/`**.

Key technical driver: the hero meshes are **procedurally generated primitives** (`TorusMesh`,
`BoxMesh`, `CylinderMesh`) with engine-generated UVs that won't cleanly tile a panel texture.
The fix is **triplanar world-space sampling inside the shader** — no UV authoring, and the same
material drops onto any prop. The renderer is **Forward+** and the gate-room `WorldEnvironment`
already runs SSAO/SSIL/glow/ACES (`scenes/gate-room-environment.tres`), so PBR metal will read well.

---

## Step 0 — Save the reference image (first executable step)

- Copy the source to `design/concept-art/materials/ancient-metal-pbr-sheet.png`
  (create the `materials/` subfolder — matches the by-category layout: `destiny-ship/`, `gate-room/`, `ui/`).
  Source: `/Users/cmoyer/Downloads/ChatGPT Image May 26, 2026, 08_14_12 PM.png`.
- Run `godot --headless --import` so the `.png.import` sidecar is generated (same gotcha as every
  other PNG in `textures/` and `concept-art/` — without it, headless `load()` returns null).
- Per `design/concept-art/AGENTS.md`, a reference that drives code should be linked from code:
  add a header comment in `shaders/ancient_metal.gdshader` pointing to this image.

---

## Pass 1 — Stargate vertical slice

### New files

**`shaders/ancient_metal.gdshader`** — spatial shader, the shared Ancient-metal look:
- **Triplanar** world-space sampling (blend by world-normal weights) so it works on the UV-less
  torus/box meshes. Sharpness uniform for the projection blend.
- **Procedural panel grid**: worldspace cells via `fract()`; seam mask (thin recessed lines)
  darkens albedo, perturbs the normal (beveled edge highlight), and adds contact AO in the seams —
  this is the "riveted plates with inset traces" structure from the reference.
- **Detail layer**: triplanar-sample `detail_normal` + `detail_rough` (the 1-texture set) for
  fine scratches/grain the panel grid can't cheaply fake. Use Godot's standard triplanar
  normal-blend.
- **Wear**: noise-thresholded edge wear lifts roughness and lightens albedo on raised panel edges.
- Uniforms: `albedo_tint:color`, `metallic`, `roughness_base`, `panel_scale`, `seam_width`,
  `seam_depth`, `wear_amount`, `detail_scale`, `triplanar_sharpness`,
  `emission_color:color`, `emission_energy`, `seam_emission` (lets seam lines glow — drives the
  gate's amber/orange chevron lighting).
- Header comment linking `design/concept-art/materials/ancient-metal-pbr-sheet.png`.

**`textures/ancient-metal/detail_normal.tres`** + **`detail_rough.tres`** — the "1 detail set".
Implement as **`NoiseTexture2D` resources** (`FastNoiseLite`, `seamless = true`;
`as_normal_map = true` for the normal). Rationale: text-based, tiny, seamless-tiling, and **no
`.png.import` sidecar / binary-blob problem**. (If a hand-authored map is wanted later, swap the
`sampler2D` uniform to a PNG — the shader is agnostic.)

**`shaders/ancient_metal_ring.tres`, `ancient_metal_band.tres`, `ancient_metal_chevron.tres`** —
`ShaderMaterial` resources pointing at `ancient_metal.gdshader` with the noise textures bound and
per-part tints matching the current palette:
- ring → dark steel, faint amber `seam_emission`
- band → darker/rougher (glyph band)
- chevron → brighter metal, stronger orange-gold seam glow

**`shaders/event_horizon.gdshader`** (stretch, but the puddle is the gate's centerpiece) — animated
energy surface to replace the flat additive disc: scrolling/curl noise + Fresnel rim + the existing
ripple motion driven in-shader. Bound via a new `shaders/event_horizon.tres` ShaderMaterial.

**`shaders/AGENTS.md`** — one-page cheatsheet (per the project's per-directory convention): what
lives here, the triplanar/worldspace convention, link back to the concept reference and CLAUDE.md.

### Modified file

**`objects/stargate.gd`** — replace the three in-code `StandardMaterial3D` blocks with the new
ShaderMaterials (keep the geometry untouched):
- `_build_outer_ring()` lines 64–72 → `material_override = load("res://shaders/ancient_metal_ring.tres")`
- `_build_inner_glyph_band()` lines 88–95 → `ancient_metal_band.tres`
- `_build_chevrons()` lines 103–110 → `ancient_metal_chevron.tres`
- `_build_event_horizon()` lines 164–174 → swap to `event_horizon.tres` (stretch); keep the
  `OmniLight3D` spill, ripple `_process` animation, and `_set_horizon_visible()` logic as-is.

> Note: shaders are tinted per-part via the three `.tres` variants, so no per-part `duplicate()`
> needed in code. `radius_*` geometry exports are unchanged.

---

## Pass 2 — Rollout (after the user reviews the slice)

Reuse the same `ancient_metal.gdshader` with a neutral **`shaders/ancient_metal_panel.tres`**
variant (no/low seam emission), wired into `scripts/room_builder.gd`:
- **Control table/pillar** — `_accent_control_pillar()` (~lines 433–510): shaft/collar/cap use the
  panel material; keep the emissive conduit bands (`_emissive_mat`) as the lit accent.
- **Console body** — `attach_console_mesh()` (~lines 536–578): replace the recursive
  `CONSOLE_BODY_COLOR` `StandardMaterial3D` with the panel ShaderMaterial. Leave the screen plate +
  `TextMesh` readout treatment alone (separate "powered screen" look).
- Optionally retire `CONSOLE_SCREEN_OVERLAY_TEX` rusted-metal overlay in favor of the shader.
- **Kino** — lowest priority: custom `kino_remote.glb` (embedded materials) + 2D CanvasLayer UI;
  defer unless we want the metal shell tinted.

Console **screens** (cyan holographic UI in the reference) are a *separate* effort from the metal
shader — a future `console_screen.gdshader` (scanlines/glow) or SubViewport UI — out of scope here.

---

## Verification

1. `godot --headless --import` — registers the new shader/material/noise resources and the
   reference PNG sidecar.
2. `tests/run.sh` — full suite must stay green. Scene-boot (`tests/smoke/scene_boot.gd`) loads
   `gate_room.tscn`, which instances the Stargate; **shader compile errors surface as stderr on
   boot**, so a clean boot validates the shaders parse.
3. **Visual review (the actual acceptance gate)**: launch `scenes/gate_room.tscn` and capture the
   Stargate dormant + active. Use the `/run` skill (or open in the Godot editor) and screenshot.
   Compare ring/chevron paneling and event-horizon against `ancient-metal-pbr-sheet.png`; tune the
   `.tres` uniform values (`panel_scale`, `seam_*`, `wear_amount`, emission) until it matches, then
   show the user before Pass 2.

## Risks / notes

- **Triplanar normal blending** is the trickiest part (tangent-space detail normal across 3 world
  projections) — use the standard Godot whiteout/RNM technique; delegate the shader math to the
  **godot-shader-specialist** subagent.
- `panel_scale` is in **world units** (triplanar), so the same material yields consistent panel size
  across props regardless of mesh scale — tune once on the ring, reuse.
- No autoloads added → the save-registration pre-commit policy is unaffected.
- Keep `objects/stargate.gd` geometry and the `active`/horizon visibility API unchanged — this is a
  material-only swap.
