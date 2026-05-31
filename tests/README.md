# Stargate Universe — Smoke Tests

Headless Godot tests that validate the Episode 1 vertical slice.

## What's tested

| File | Scope |
|---|---|
| `smoke/scene_boot.gd` | Each of the 5 gameplay scenes loads, instantiates, and resolves its critical node paths (Player, Camera, Doors, Interactables). |
| `smoke/e1_flow.gd` | GameState autoload mutators (damage/heal/oxygen/discover_room/acquire_kino/mark_quarters_found/seal_breach) work, and the `episode_completed` signal fires only when all three E1 prerequisites are met. |
| `smoke/kino_doors.gd` | Piloted-Kino door traversal (issue #49): `_is_pilotable_door` classification, `_find_interact_target` aim cone, `_route_kino_through_door` sets the `kino_pilot_arrival_spawn` baton + `next_room_id` + marks the door traversed + keeps `kino_pilot_mode`, gate-room refusal, and the cross-room recall scene-reload path. |
| `save/save_store_test.gd` | Isolated unit tests for `SaveStore` (slot→path mapping, atomic write + 3-deep backup rotation, corrupt-primary fallback, meta sidecar, `list_slots`/`most_recent_slot`/`wipe_slot`, legacy single-save migration, dot-path edits) against a throwaway temp root. Includes the loss regression: a headless session writing a sandbox root must leave player slots byte-for-byte untouched. |
| `save/slot_resume.tscn` | Slot-aware resume integration: write a deep save to `manual_2`, edit a field via `SaveStore`, then `load_and_resume("manual_2")` and assert the resumed scene/room/quest-step/player-pos match — proving the edit→Continue loop and that resume targets the requested slot (not just the most-recent). |

## How to run

```bash
tests/run.sh            # all
tests/run.sh scene      # scene-boot only
tests/run.sh flow       # e1-flow only
tests/run.sh save       # save-slot unit + slot-resume only
```

Override the Godot binary with `GODOT_BIN=/path/to/godot tests/run.sh`.

## Save slots + debug CLI

The save system stores one directory per slot under `user://saves/`
(`autosave`, `quicksave`, `manual_1..N`), each with `save.json`, three
rotating backups, and a lightweight `meta.json` sidecar read on its own for
menu listing. `SaveManager` auto-selects its root: real (windowed) play uses
`user://saves/`; **headless** runs (or an explicit `--save-root=<path>` user
arg / `SGU_SAVE_ROOT` env var) redirect to a sandbox so no screenshot/test/tool
run can ever clobber the player's slots.

`tests/tools/save.sh` wraps a headless inspector + editor (both instantiate
`SaveStore` directly, no autoloads). Operates on the live player root by
default; set `SGU_SAVE_ROOT` to target a sandbox:

```bash
tests/tools/save.sh list                                   # table of slots + metadata
tests/tools/save.sh dump manual_1                          # pretty-print full save.json
tests/tools/save.sh validate all                           # parse + version + key check
tests/tools/save.sh set autosave scene_path=res://scenes/control_room.tscn
tests/tools/save.sh set autosave systems.game_state.quest_step=find_scrubber
tests/tools/save.sh set autosave player.pos=1.5,0.3,-4.0   # "x,y,z" → array
tests/tools/save.sh clone manual_1 manual_2                # copy a slot
tests/tools/save.sh scenario manual_1 mid-air-crisis       # apply a named preset
```

Workflow: stage a slot, launch the game, hit **Continue** → land in that exact
scene/room/quest step.

Exit code 0 = all PASS. Non-zero = at least one FAIL.

## Policy lints (`tests/lint/`, run in the `lint` subset + pre-commit)

Fast, editor-free `bash`/`awk` checks that guard architectural invariants:

| Lint | Enforces |
|---|---|
| `check_save_registration.sh` | Every `project.godot` autoload either calls `SaveManager.register_system(...)` or carries a `# @no-save:` marker, so no stateful system ships unpersisted. |
| `check_collection_forks.sh` | No top-level bool field in `scripts/*.gd` uses acquisition vocabulary (`*_found`, `*_acquired`, `has_*`, `got_*`, …). A set of like things (items, discovered rooms, unlocks) must live in ONE registry behind ONE add/enumerate API — not scattered per-instance bools that consumers must special-case (the looted-fuse bug #41; quest fork #36). Object-state participles (`looted`/`opened`) and `has_<world-state-verb>` (`has_seen`) are NOT flagged. Opt out genuinely-distinct state with `# @collection-ok: <reason>`. See the `homogeneous-collection-single-model` skill. |

Both run on `--staged` in `.githooks/pre-commit` (install once: `git config core.hooksPath .githooks`).

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
