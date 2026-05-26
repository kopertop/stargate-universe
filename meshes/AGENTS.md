# meshes/

Godot `.res` mesh resources — pre-baked mesh data for hot-path props, kept
separate from `.glb` model sources so they can be tuned independently.

## Contents

- `brick.res` — Brick prop mesh (Kenney starter-kit carry-over).
- `dust.res` — Dust particle mesh.

## Conventions

- `.res` resources are binary; do not edit by hand.
- New procedural geometry should live in script (see `scripts/room_builder.gd`)
  unless it's reused enough to justify a baked resource.
- When importing a new `.glb`, prefer keeping it under `../models/` and
  loading the model directly; only bake to `.res` if profiling shows
  per-frame cost of the import path.

## Cross-references

- Project rules: `../CLAUDE.md`
- Models source: `../models/AGENTS.md`
- Procedural geometry: `../scripts/room_builder.gd`
