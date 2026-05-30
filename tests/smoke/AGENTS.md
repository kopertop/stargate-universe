# tests/smoke/

Headless `SceneTree`-extending tests. Several files, one concern each.

## Contents

- `scene_boot.gd` — Every gameplay scene loads without parse errors / missing
  nodes / broken signal connections. Iterates `data/ship_layout.json` so new
  rooms are picked up automatically. Also runs a connection-graph reachability
  check that backstops the BFS in `scripts/ship_layout.gd`.
- `e1_flow.gd` — `GameState` mutators, save round-trip, autoload registry,
  full E1 quest-step progression up through episode completion.
- `quest_waypoint.gd` — BFS path correctness, quest-target anchors via the
  `QuestLog`-backed `quest_target(step_id)` shim, `current_room_changed`
  signal, Kino-remote route-resolution rule (custom override beats quest
  target; same-room collapses to "").
- `quest_log.gd` — Data-driven QuestLog runtime: predicate-advance walks
  the full 16-flag golden sequence, complete_step event channel,
  serialize/deserialize round-trip, old-format save migration.
- `kino_autopilot.gd` — Multi-drone coordination + avoid-radius + sweep.

## Conventions

- Naming: `<scope>.gd` — descriptive, no `test_` prefix in filename.
- Each test prints a `=== <name> ===` banner, `PASS  <label>` / `FAIL <label>`
  per assertion, then `=== summary ===` with totals, then `quit(0|1)`.
- Scripts that exercise quest / world-state behaviour use the live
  autoloads (`GameState` + `QuestLog`) via `root.get_node("Name")` —
  autoloads ARE attached to root in `-s` mode but their `_ready()` is
  deferred until a frame ticks (QuestLog handles this with lazy init).
  Constructing same-named test duplicates clashes with the autoload
  and leaves the predicate evaluator reading from the wrong instance.
- Run individually: `tests/run.sh scene|flow|quest|questlog|autopilot`.
  Run all: `tests/run.sh`.

## Cross-references

- Project rules: `../../CLAUDE.md`
- Test runner: `../run.sh`
- Test suite index: `../AGENTS.md`
- E2E (real autoloads): `../playthrough/AGENTS.md`
