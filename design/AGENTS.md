# design/

Engine-agnostic creative + systems documentation. Authored before code; code
should reference these rather than inventing parallel rules. Carried over
intact from the pre-pivot browser stack.

## Contents

- `gdd/` — Per-system Game Design Documents (15 of them). One per gameplay
  pillar (player controller, camera, kino remote, save/load, etc.).
- `concept-art/` — Reference imagery. Subfolders for `destiny-ship/`,
  `gate-room/`, `ui/` (HUD layouts, restoration console).
- `data/` — Designer-authored JSON (`entities.json`, `lights.json`,
  `materials.json`, `rooms.json`, `ship-systems.json`). NOT loaded directly
  by Godot — these are reference tables for designers.
- `reviews/` — Design review feedback, version history.
- `voice-line-manifest.md` — VO planning for episodes.

## Conventions

- GDD files are markdown. Title is the system name. First section is
  "Purpose" / pillar fit; later sections cover rules, edge cases, open
  questions.
- Concept art is reference-only — actual assets live in `models/`, `sprites/`,
  `fonts/`. Concept art file names should hint at intended use
  (`destiny-restored-hud-layout.png`).
- Designer JSON in `design/data/` ≠ runtime JSON in `../data/`. Don't conflate
  — the runtime loader (`ShipLayout`) only reads `../data/`.

## Cross-references

- Project rules: `../CLAUDE.md`
- Per-system docs: `gdd/AGENTS.md`
- Runtime data: `../data/AGENTS.md`
- Production tracking: `../production/AGENTS.md`
