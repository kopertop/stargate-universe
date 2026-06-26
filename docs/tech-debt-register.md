# Technical Debt Register

Last updated: 2026-06-26 · Sprint: sprint-005
Total open items: 5 | Estimated total effort: ~XL (one large refactor + three doc writes)

Tracks **conscious** technical-debt decisions for the Godot 4.6 Stargate Universe project.
Maintained via the `/tech-debt` skill (`.claude/skills/tech-debt/`). Run `/tech-debt scan`
at least once per sprint; items open for >3 sprints must be fixed or consciously re-accepted.

Scoring: `priority = (impact × frequency) / effort`. Effort is T-shirt (S/M/L/XL).

| ID | Category | Description | Files | Effort | Impact | Priority | Added | Sprint |
|----|----------|-------------|-------|--------|--------|----------|-------|--------|
| TD-001 | Architecture | `gate_room.gd` is a 4,603-line god object — procedural scene build + cold-open cinematic + throw mechanics in one file. Plan: extract `GateThrowKit` (mechanics) + `GatePrologueDirector` (cinematic) as `Node` helpers (no `class_name`, preload pattern). | `scripts/gate_room.gd` | L | Med | Med | 2026-06-26 | Backlog |
| TD-002 | Architecture | `room.gd` god object. **Partially resolved 2026-06-26:** extracted the standoff choreography cluster (~640 lines) to `scripts/rush_standoff_director.gd`; `room.gd` 2,657 → 2,040. `_spawn_dr_rush` + a thin `_run_standoff_cinematic` forwarder kept. Remaining: `_spawn_interactables` dispatch is still long but cohesive — leave unless it grows. | `scripts/room.gd`, `scripts/rush_standoff_director.gd` | S | Low | Low | 2026-06-26 | sprint-005 |
| TD-009 | Documentation | `codebase-dependency-graph.md` is stale — lists 8 autoloads/34 scripts; the project now has 26 autoloads/98 scripts. Regenerate after the next structural change. | `docs/architecture/codebase-dependency-graph.md` | S | Low | Low | 2026-06-26 | Backlog |
| TD-005 | Dependency | VRM addon carries 15 FIXMEs / 13 TODOs around mesh/material/spring-bone handling. **Consciously accepted:** third-party plugin we do not maintain; touching it risks breaking VRM import for marginal gain. Re-evaluate only if we upgrade the addon. | `addons/vrm/*` | L | Low | Low | 2026-06-26 | Accepted |
| TD-007 | Test | Smoke suite (`tests/smoke/`) is SceneTree-based, not GDUnit4, and centred on the E1 vertical slice. Newer systems (planet gen, biomes, equipment) have lighter coverage; no real input-event simulation. Accept for slice scope; revisit if the suite outgrows the framework. | `tests/smoke/`, `tests/README.md` | M | Low | Low | 2026-06-26 | Accepted |

## Resolved / closed

| ID | Category | Description | Resolution | Closed |
|----|----------|-------------|------------|--------|
| TD-004 | Code Quality | Scan flagged ~9 scripts (`character_factory.gd`, `planet_generator.gd`, `room_builder.gd`, `ui/hud_theme.gd`, …) as having untyped `func` signatures. | **False positive** — verified all signatures and parameters are fully typed; the finding tripped on multi-line signature wraps (`-> Type` on the continuation line). No change needed; code already conforms to the typed-GDScript convention. | 2026-06-26 |
| TD-006 | Documentation | `/sound-fetch` skill still described the browser stack (Three.js `audio-manager.ts`, R2 upload via `wrangler`, `resolveAssetUrl()`, `bun run typecheck`, mp3). | Ported Steps 4–8 + format table + path convention to Godot: `Audio` autoload, in-repo `sounds/*.ogg`, `godot --headless --import` sidecar, `tests/run.sh` verify. | 2026-06-26 |
| TD-008 | Code Quality | `scripts/crew_viewer.gd.uid` was untracked (orphaned Godot import sidecar). | Committed alongside its `.gd`. | 2026-06-26 |
| TD-003 | Documentation | Missing architecture synthesis docs flagged "not blocking" in CLAUDE.md. | Authored `docs/architecture/architecture.md`, `control-manifest.md`, and `design/accessibility-requirements.md`, grounded in the shipping codebase (26 autoloads, 4 ADRs, dependency graph). Stale-graph follow-up split out as TD-009. | 2026-06-26 |

## Notes

- Tech debt is a tool, not a failure. Every open entry records WHY it's accepted (deadline,
  third-party, slice scope) and what would trigger a re-evaluation.
- `@no-save:` / `@collection-ok:` opt-out markers (35 across `scripts/`) were audited during
  the 2026-06-26 scan and are all justified — not tracked as debt.
