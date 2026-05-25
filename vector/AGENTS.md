# vector/

Vector source artwork. Pre-rasterised; the runtime consumes the rasters in
`../sprites/`, not these sources.

## Contents

- `sprites.fla` — Flash/Animate source for UI sprites.

## Conventions

- This directory is reference-only — Godot doesn't load `.fla` directly.
- Export from `sprites.fla` into `../sprites/ui/` as PNG with transparency,
  with NinePatch margins where applicable.
- Keep the `.fla` in sync with the rendered PNGs; if either drifts, treat
  the PNG as authoritative for runtime.

## Cross-references

- Project rules: `../CLAUDE.md`
- Rasterised consumers: `../sprites/AGENTS.md`
