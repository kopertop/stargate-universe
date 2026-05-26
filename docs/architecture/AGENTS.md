# docs/architecture/

Architecture Decision Records and codebase structure docs.

## Contents

- `adr-001-engine-choice.md` — Why Godot 4.6 (after browser-stack pivot).
- `adr-002-physics-engine.md` — Built-in Godot physics (post-pivot — was
  Crashcat on the browser stack).
- `adr-003-renderer.md` — Forward+ renderer choice.
- `adr-004-vrm-models.md` — VRM character pipeline (stale: now Kenney mini-
  characters; see CLAUDE.md "What was dropped").
- `codebase-dependency-graph.md` — Visual / textual map of which scripts
  depend on which autoloads. Helpful for refactors.

## Conventions

- ADRs are immutable history. To change a decision, write a new ADR that
  supersedes the old one — don't edit the old one in place.
- Format: Title, Status (Accepted/Superseded), Context, Decision, Consequences,
  Alternatives.
- Drop the next ADR number into the sequence (adr-005, adr-006, …) — no gaps.

## Cross-references

- Project rules: `../../CLAUDE.md`
- Doc index: `../AGENTS.md`
- CLAUDE.md "Tech debt" section flags `docs/architecture/architecture.md` and
  `docs/architecture/control-manifest.md` as MISSING — write them when the
  time is right.
