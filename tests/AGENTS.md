# tests/

Headless test suite. Four levels (per `run.sh`): scene_boot, e1_flow,
quest_waypoint, e1_playthrough.

## Contents

- `run.sh` — Entry point. Modes: `scene`, `flow`, `quest`, `playthrough`,
  `all` (default).
- `smoke/` — `SceneTree`-extending GDScript tests. Boot a scene or
  instantiate scripts directly, run assertions, `quit(0|1)`.
- `playthrough/` — Real scene with autoloads (`playthrough.tscn`) that
  drives an end-to-end E1 run.
- `baseline_screenshots/` — Reference images for visual regression
  (currently unused but reserved).
- `capture_baselines.sh` — Helper that regenerates baseline screenshots.
- `README.md` — Test suite overview (read this first if onboarding).

## Conventions

- Smoke tests `extends SceneTree`, write to stdout, exit with `quit(0)` /
  `quit(1)`. No GDUnit4 dependency.
- `--quit-after` is a FRAME-COUNT CEILING, not a target. Tests call quit
  explicitly; truncated runs silently look like PASS. See memory
  `[[feedback_godot_quit_after_frames]]`.
- Headless `-s` mode: autoloads ARE present on `/root` (reach them via
  `root.get_node_or_null("Name")`, NOT the bare global), but
  `await get_tree().process_frame` deadlocks inside `_initialize` — defer real
  work with `call_deferred("_run")` and only `await` from there. Use idempotent
  `_load()` helpers and manual `root.add_child(node)` for scripts under test.
  See memory `[[feedback_godot_scenetree_script_gotchas]]`.
- New scenes must extend `smoke/scene_boot.gd::STATIC_SCENES` or
  `non-gate room booting`. Adding a new room only? Add an entry to
  `data/ship_layout.json` and the test picks it up automatically.
- **Save isolation is MANDATORY for EVERY test (no exceptions).** Autoloads
  run in `-s` mode (they're on `/root`), so `SaveManager` autosaves on
  `GameState.objective_changed` / `current_room_changed`. Any test that boots a
  gameplay scene or mutates `GameState` will otherwise **overwrite the player's
  real `user://save.json`** (issue #44; autoloads-on-`/root` under `-s`:
  `[[feedback_godot_scenetree_script_gotchas]]`; skill
  `godot-autoload-autosave-clobbers-real-save`). Before driving ANY state,
  redirect saves to a per-test sandbox stem:

  ```gdscript
  # -s SceneTree tests / capture harnesses — duck-typed via /root:
  var save_mgr: Node = root.get_node_or_null("SaveManager")
  if save_mgr != null:
      save_mgr.call("configure_test_paths", "my_test")   # unique stem per test

  # Node-based runners in the tree (playthrough/probe) call it directly:
  SaveManager.configure_test_paths("my_test")
  ```

  This is not optional even for "read-only" or logic-only tests — if it touches
  `GameState` at all, isolate first. Pure-logic tests that never set
  `current_scene_path`/`current_room_id` and spawn no `"player"`-group node are
  technically safe (`_can_autosave()` returns false), but isolate anyway so the
  test stays safe if it later grows a scene boot. Reference isolators:
  `playthrough/`, `smoke/`… and `shots/*_shot.gd`.

## Cross-references

- Project rules: `../CLAUDE.md`
- Test smoke index: `smoke/AGENTS.md`
- Playthrough harness: `playthrough/AGENTS.md`
- Skills: `/test-setup`, `/test-helpers`, `/smoke-check`,
  `/regression-suite`, `/playtest-report`
