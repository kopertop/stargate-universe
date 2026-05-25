# production/sprints/

Sprint-by-sprint task tables. One file per sprint. Active sprint sits at the
top level; archived sprints live in `archive-browser-stack/`.

## Contents

- `sprint-005.md` — **Active** (first Godot-era sprint). Goal: make E1
  Mission 1 actually playable.
- `archive-browser-stack/` — Sprints 1–4 from the pre-pivot Three.js stack.
  Conceptual notes have been folded into design GDDs + memory; the files are
  preserved for history but **do not resume**.

## File format

Each sprint file begins with:

```
# Sprint NNN — <one-line goal>

Started: 2026-MM-DD
Target end: 2026-MM-DD
Status: Active | Closed
```

Followed by a `| Task | Owner | Status | Notes |` table covering the sprint's
committed work. New tasks land at the bottom; status flips to `Done` (not
deleted) when complete.

## Conventions

- Task IDs use the sprint number as a prefix (e.g. `S005-12`). They stay
  stable across edits so commits + PR titles can reference them.
- Closed sprints are immutable. If something slips, write a follow-up task
  in the current sprint instead of reopening the old one.
- The first ~3 lines should be enough to answer "what is this sprint about"
  in a glance.

## Cross-references

- Project rules: `../../CLAUDE.md`
- Production index: `../AGENTS.md`
- Design backlog source: `../../design/gdd/AGENTS.md`
- Sprint-plan skill: `/sprint-plan`
