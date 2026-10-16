# Lead Programmer — Agent Memory

> ## ⚠️ Partially stale — harness notes from the multi-engine Claude era
>
> The Godot/Unity/Unreal harness was removed by `abfb5ed` ("chore: remove godot, kenney kit,
> vite/ggez and mixamo tooling; move the three.js game to the repo root"). The Skill Authoring
> Conventions below are still valid for the current Three.js codebase (`src/`, `index.html`,
> `build.sh`). The Cross-cutting Engine Conventions section has been cleaned of Godot-era content.

## Skill Authoring Conventions

### Frontmatter
- Fields: `name`, `description`, `argument-hint`, `user-invocable`, `allowed-tools`
- Read-only analysis skills that run in isolation also carry `context: fork` and `agent:`
- Interactive skills (write files, ask questions) do NOT use `context: fork`
- `AskUserQuestion` is a usage pattern described in skill body text — it is NOT listed
  in `allowed-tools` frontmatter (no existing skill does this)

### File Layout
- Skills live in `.claude/skills/<name>/SKILL.md` (subdirectory per skill, never flat .md)
- Section headers use `##` for phases, `###` for sub-sections
- Phase names follow "Phase N: Verb Noun" pattern (e.g., "Phase 1: Find the Story")
- Output format templates go in fenced code blocks

### Known Canonical Paths (verify before referencing in new skills)
- Tech debt register: `docs/tech-debt-register.md` (NOT `production/tech-debt.md`)
- Sprint files: `production/sprints/`
- Systems index: `design/gdd/systems-index.md`
- ~~Control manifest: `docs/architecture/control-manifest.md`~~ — removed in web-era pivot
- ~~Session state: `production/session-state/active.md`~~ — removed in web-era pivot
- ~~Engine reference: `docs/engine-reference/[engine]/VERSION.md`~~ — removed in web-era pivot
- ~~Epic story files: `production/epics/[epic-slug]/story-[NNN]-[slug].md`~~ — removed in web-era pivot

### Skills Completed
- `story-done` — end-of-story completion handshake (Phase 1-8, writes story file)

## Cross-cutting Engine Conventions (Watch For)

> **Removed Godot-era conventions** — floor-y conventions, `Interactable._ready()` collision layer notes,
> and references to `.gd`/`.tscn` files were deleted when the repo pivoted to Three.js (2026-09-08).
> Rebuild engine conventions from the Three.js codebase (`src/`, `index.html`, `build.sh`) as needed.
