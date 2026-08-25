# production/

Sprint planning, milestone tracking, and production notes. Engine-agnostic;
carried over from the browser stack and updated for the Godot era.

## Contents

- `sprints/` — Per-sprint task tables. `sprint-005.md` is the active sprint
  (first Godot-era sprint). `sprints/archive-browser-stack/` holds sprints
  1–4 from the pre-pivot timeline (do not resume).
- `milestones/` — Cross-sprint milestone definitions and exit criteria.
- `notes/` — Loose production notes that don't belong in a sprint file.
- `daily-notes/` — Per-day progress logs (auto memory candidates if
  surprising).
- `session-logs/`, `session-state/` — Claude Code session capture (used by
  `/wrap-up`).
- `perf-baseline-2026-05-21.md` — Latest performance baseline reference.
- `next-development-plan.md` — Forward-looking work queue (un-tracked but
  intentional).
- `stage.txt` — Single-word current project stage (used by
  `/project-stage-detect`).

## Conventions

- Active sprint format: one markdown file `sprint-NNN.md` with a Task table
  near the top. No nested `epics/` hierarchy (deliberately flat — see
  CLAUDE.md "Sprint format").
- Sprints are immutable history once closed; bug fixes for a closed sprint
  land in the current sprint, never retro-edited.
- Convert relative dates ("Thursday") to absolute (`2026-05-29`) before
  writing — daily-notes get hard to interpret months later.

## Cross-references

- Project rules: `../CLAUDE.md`
- Active sprint: `sprints/AGENTS.md`
- Design backlog: `../design/AGENTS.md`
- Stage detection skill: `/project-stage-detect`
