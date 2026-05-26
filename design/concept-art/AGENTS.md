# design/concept-art/

Visual reference imagery. Informs lighting, props, and HUD layout — NOT
shipped as runtime assets.

## Contents

- `destiny-ship/` — Exterior + interior corridors, FTL drop reference.
- `gate-room/` — Hero space reference: lighting, dais, console layout,
  mezzanine. Drives `scripts/gate_room.gd` proportions.
- `ui/` — HUD layouts. `destiny-restored-hud-layout.png` is the canonical
  reference for the objective panel, edge arrow, and quest diamond style.

## Conventions

- Images are reference-only — do NOT load them at runtime. Runtime UI
  artwork lives in `../../sprites/ui/`.
- Reference filenames should hint at intent (`destiny-restored-hud-layout`,
  `gate-room-arrival-shot`). Avoid `final-v3-COPY`-style names.
- When a concept image drives a code decision, link to it from the relevant
  GDD or in a code comment so the connection is discoverable.

## Cross-references

- Project rules: `../../CLAUDE.md`
- GDD index: `../gdd/AGENTS.md`
- HUD implementation: `../../scripts/hud.gd`, `../../objects/hud.tscn`
- Gate-room layout: `../../scripts/gate_room.gd`
