# Lead Programmer — Agent Memory

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
- Epic story files: `production/epics/[epic-slug]/story-[NNN]-[slug].md`
- Control manifest: `docs/architecture/control-manifest.md`
- Session state: `production/session-state/active.md`
- Systems index: `design/gdd/systems-index.md`
- Engine reference: `docs/engine-reference/[engine]/VERSION.md`

### Skills Completed
- `story-done` — end-of-story completion handshake (Phase 1-8, writes story file)

## Cross-cutting Engine Conventions (Watch For)

- **Two floor-y conventions coexist** — `scripts/gate_room.gd` uses a `BoxMesh` floor
  with visible top at y=0; `scripts/kenney_room.gd` uses Kenney `floor.glb` tiles with
  visible top at y=0.3. Any utility, NPC spawn, or prop-placement helper that crosses
  rooms must branch on the host scene's convention or be parameterized by floor-top-y.
  Full details: `.claude/agent-memory/godot-gdscript-specialist/MEMORY.md`.
- **`Interactable._ready()` overwrites `collision_layer = 4`** unconditionally —
  subclasses needing extra bits must reassign AFTER `super()._ready()`, not in the
  `.tscn`. If you're reviewing a PR that adds a new `Interactable` subclass needing
  walk-blocker (1) or camera-occluder (2) bits, this is the first thing to check.
