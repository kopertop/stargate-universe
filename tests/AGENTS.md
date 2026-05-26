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
- Headless `-s` mode SKIPS autoload `_ready` and freezes
  `await get_tree().process_frame`. Use idempotent `_load()` helpers and
  manual `root.add_child(node)` for scripts under test. See memory
  `[[feedback_godot_scenetree_script_gotchas]]`.
- New scenes must extend `smoke/scene_boot.gd::STATIC_SCENES` or
  `non-gate room booting`. Adding a new room only? Add an entry to
  `data/ship_layout.json` and the test picks it up automatically.

## Cross-references

- Project rules: `../CLAUDE.md`
- Test smoke index: `smoke/AGENTS.md`
- Playthrough harness: `playthrough/AGENTS.md`
- Skills: `/test-setup`, `/test-helpers`, `/smoke-check`,
  `/regression-suite`, `/playtest-report`
