# Stargate Universe — Smoke Tests

Headless Godot tests that validate the Episode 1 vertical slice.

## What's tested

| File | Scope |
|---|---|
| `smoke/scene_boot.gd` | Each of the 5 gameplay scenes loads, instantiates, and resolves its critical node paths (Player, Camera, Doors, Interactables). |
| `smoke/e1_flow.gd` | GameState autoload mutators (damage/heal/oxygen/discover_room/acquire_kino/mark_quarters_found/seal_breach) work, and the `episode_completed` signal fires only when all three E1 prerequisites are met. |

## How to run

```bash
tests/run.sh            # all
tests/run.sh scene      # scene-boot only
tests/run.sh flow       # e1-flow only
```

Override the Godot binary with `GODOT_BIN=/path/to/godot tests/run.sh`.

Exit code 0 = all PASS. Non-zero = at least one FAIL.

## Why not GDUnit4?

For a small vertical-slice game the value of a full unit-test framework is low.
`SceneTree`-extending scripts give us the same capabilities — load scenes, drive
state, assert outcomes, exit with a code — with zero addons to vendor and zero
test runner config.

If/when the game grows beyond the slice, swap in GDUnit4 by following the CCGS
`smoke-check` skill in `.claude/skills/smoke-check/SKILL.md`.

## Known limitations

- Scene-boot does not exercise player input or door transitions — it only
  verifies the static node graph. Door transitions are exercised indirectly:
  `e1_flow.gd` drives GameState through the win condition that doors trigger.
- No real input simulation. If you need to test the actual keypress→action
  pipeline, write a scene-level integration script that uses
  `Input.parse_input_event(...)` on a `InputEventAction`.
