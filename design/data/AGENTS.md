# design/data/

Designer-authored JSON reference tables. **Not loaded at runtime.** The
runtime equivalents live in `../../data/` and are the actual source of truth
for the game's behaviour.

## Contents

- `entities.json` — Designer catalogue of NPCs, props, pickups.
- `lights.json` — Per-region lighting recipes (intended; runtime values are
  set in scripts/scene resources).
- `materials.json` — Material palette reference.
- `rooms.json` — Designer-side room metadata. Mirrors `../../data/ship_layout.json`
  but with extra prose fields; the runtime loader ignores it.
- `ship-systems.json` — Faction/system definitions for ship lore.

## Conventions

- These files are READ BY HUMANS, not Godot. If you need a value at runtime,
  port it to the matching file under `../../data/` and load it via an
  autoload.
- Keep schemas loose — designers iterate fast here. Don't hard-couple code to
  these shapes.

## Cross-references

- Project rules: `../../CLAUDE.md`
- Runtime data: `../../data/AGENTS.md`
- Per-system GDDs: `../gdd/AGENTS.md`
