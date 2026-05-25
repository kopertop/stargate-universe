# tests/smoke/

Headless `SceneTree`-extending tests. Three files, three concerns.

## Contents

- `scene_boot.gd` — Every gameplay scene loads without parse errors / missing
  nodes / broken signal connections. Iterates `data/ship_layout.json` so new
  rooms are picked up automatically. Also runs a connection-graph reachability
  check that backstops the BFS in `scripts/ship_layout.gd`.
- `e1_flow.gd` — `GameState` mutators, save round-trip, autoload registry,
  full E1 quest-step progression up through episode completion.
- `quest_waypoint.gd` — BFS path correctness, `GameState.QUEST_TARGETS`
  table, `current_room_changed` signal, Kino-remote route-resolution rule
  (custom override beats quest target; same-room collapses to "").

## Conventions

- Naming: `<scope>.gd` — descriptive, no `test_` prefix in filename.
- Each test prints a `=== <name> ===` banner, `PASS  <label>` / `FAIL <label>`
  per assertion, then `=== summary ===` with totals, then `quit(0|1)`.
- Scripts instantiate the units under test rather than relying on autoloads
  (which don't `_ready` in `-s` mode).
- Run individually: `tests/run.sh scene|flow|quest`. Run all: `tests/run.sh`.

## Cross-references

- Project rules: `../../CLAUDE.md`
- Test runner: `../run.sh`
- Test suite index: `../AGENTS.md`
- E2E (real autoloads): `../playthrough/AGENTS.md`
