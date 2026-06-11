# docs/

Reference + architectural documentation. Lives outside `design/` because
these docs are written for engineers, not designers.

## Contents

- `architecture/` — Architecture Decision Records (ADRs), dependency graph,
  and the codebase architecture reference.
- `engine-reference/` — Engine API notes (Godot 4.6 specific tricks,
  gotchas, version migration notes).
- `audio-inventory.md` — Catalogue of all SFX + music, by category, with
  source attribution.
- `deployment-targets.md` — Planned platforms / build configurations.
- `tts-dialogue.md` — Dynamic runtime voiced dialogue: the `TTSClient` node, the
  LuxTTS sidecar, available character voices, and how to speak lines in-engine.
  See also the `/speak` and `/tts` skills.

## Conventions

- ADRs follow the pattern: context → decision → consequences → alternatives
  considered. Number them sequentially.
- When you make a non-trivial technical decision, add or update an ADR
  rather than just commenting the code.
- Engine-specific gotchas that recur belong in a Claude Code skill (`/skill-
  improve`), not buried here.

## Cross-references

- Project rules: `../CLAUDE.md`
- Architecture: `architecture/AGENTS.md`
- Memory hints: `feedback_godot_scenetree_script_gotchas`,
  `feedback_godot_change_scene_async`,
  `feedback_godot_quit_after_frames` (in MEMORY.md)
