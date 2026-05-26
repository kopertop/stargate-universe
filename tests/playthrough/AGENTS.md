# tests/playthrough/

End-to-end test that drives an actual gameplay scene with autoloads. Catches
issues smoke tests can't (real SceneRouter transitions, signal wiring,
interactable spawning).

## Contents

- `playthrough.tscn` — Boot scene. Has its own Player + minimal HUD so the
  full GameState lifecycle runs. Entry point for `tests/run.sh playthrough`.
- `bootstrap.gd` — Script attached to the boot scene. Calls into
  `scripts/playthrough_runner.gd` which drives the E1 mission step-by-step
  via `Interactable.interact()` calls.

## Conventions

- Run via `tests/run.sh playthrough` — uses `--quit-after 100000` because
  the runner self-imposes its own timeout (`TIMEOUT_SEC` in
  `scripts/playthrough_runner.gd`).
- The runner uses duck-typing for scene-resolved nodes (e.g.
  `GateConsole`) rather than `class_name` — fresh `class_name` registrations
  can fail on the first headless run. See memory
  `[[feedback_godot_class_name_headless]]`.
- When a step depends on a new interactable, extend `playthrough_runner.gd`
  to wait for the matching node by `name`/`script.resource_path` (don't
  hard-code paths into the scene).

## Cross-references

- Project rules: `../../CLAUDE.md`
- Runner: `../../scripts/playthrough_runner.gd`
- Test runner: `../run.sh`
- Smoke alternatives (faster, narrower): `../smoke/AGENTS.md`
