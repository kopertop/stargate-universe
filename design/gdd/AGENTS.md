# design/gdd/

Per-system Game Design Documents. Each one defines the rules, behaviour, and
edge cases for a single subsystem so the implementation has a single source
of truth.

## Contents (index)

- `game-concept.md` — High-level pitch: sci-fi open-world RPG aboard Destiny.
- `player-controller.md` — Movement, jumping, look mode.
- `camera-system.md` — Third-person + WoW-style mouselook.
- `crew-dialogue-choice.md` — Choice-tree dialog flow, used by NPCs.
- `kino-remote.md` — Inventory / map / status tablet UI.
- `event-bus.md` — Cross-scene signal architecture (centred on `GameState`).
- `resource-inventory.md` — Lime / oxygen / health resources, scarcity rules.
- `save-load-interface.md` — F5/F9 save format, what persists.
- `ship-atmosphere-lighting.md` — Lighting bible per region.
- `ship-exploration.md` — Room graph, door rules, discovery flow.
- `ship-state-system.md` — Per-room state machine (power, breach, lockdown).
- `stargate-planetary-runs.md` — Off-ship missions via the Stargate.

## Conventions

- File names: kebab-case, system-noun first.
- These docs were written for the browser stack and are mostly engine-
  agnostic. Where they reference Three.js / WebGPU / ggez, treat that as
  stale: the implementation is now Godot 4.6 GDScript.
- Before writing new code, read the matching GDD and update it if your design
  drifts from it. Stale GDDs are worse than missing ones.

## Cross-references

- Project rules: `../../CLAUDE.md`
- Concept art: `../concept-art/AGENTS.md`
- Sprint backlog tying these into work: `../../production/sprints/AGENTS.md`
