# Stargate Universe

A sci-fi open-world RPG set in the Stargate Universe TV series. Players take on the role of crew
aboard the ancient ship Destiny, exploring uncharted galaxies, managing resources, making
story-defining choices, and surviving against alien threats.

## Current Status

_Snapshot — refresh with `/help`. Last updated: 2026-05-21._

- **Phase:** Production · **Active sprint:** sprint-005 (first Godot-era sprint) · **Branch:** `godot`
- **Sprint-005 goal:** Make E1 Mission 1 actually playable — wire rooms via doors, add Kino pickup + UI, flesh out hull breach + seal interaction, ship mission-complete trigger.
- **Done:** Concept, Systems Design (15 GDDs in `design/gdd/`), engine pivot to Godot 4.6, E1 gate-room slice + headless smoke tests
- **Sprint format:** Task tables in `production/sprints/sprint-NNN.md` (no `production/epics/` hierarchy)
- **Sprints 1–4 archived:** `production/sprints/archive-browser-stack/` — all pre-pivot Three.js work. Do not resume; conceptual notes folded into design GDDs + memory.
- **Tech debt — not blocking:** missing `docs/architecture/architecture.md`, `docs/architecture/control-manifest.md`, `design/accessibility-requirements.md` (4 ADRs exist in `docs/architecture/`)

## Engine

**Godot 4.6** (Forward+ renderer). Bootstrapped from
[KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer) — a
CC0-licensed third-person platformer kit. Kit assets live in `models/`, `meshes/`, `objects/`,
`sounds/`, `sprites/`, `fonts/`, `vector/`. The kit's `scripts/` are GDScript.

### Status

This branch (`reset-stack`) is a **complete engine pivot** away from the previous browser-based
stack (Three.js + WebGPU + ggez + Crashcat + VRM). The previous stack is preserved on `main`.

Reason for pivot: character animation and display had never worked properly on the browser stack;
character pipelines in Godot are battle-tested and the Kenney kit ships a working one.

### What carried over from the browser branch

- `design/gdd/` — 15 Game Design Documents (engine-agnostic)
- `production/` — sprint plans, milestones (mostly engine-agnostic)
- `docs/` — narrative, audio inventory, deployment notes
- `.claude/` — subagent definitions, slash commands (some need rewriting for Godot)

### What was dropped

- Three.js + WebGPU rendering
- `@kopertop/vibe-game-engine` (ggez) plugin system
- Crashcat physics
- VRM character system (~3,600 LOC)
- TypeScript + Vite + Bun + Wrangler / Cloudflare Pages deployment
- `scene.runtime.json` pipeline
- Auto-discovered scene system
- All browser tests (Vitest, Playwright)

## Key Paths

| Path | Contents |
|---|---|
| `project.godot` | Godot project config |
| `scenes/` | Godot `.tscn` scenes (main, level, ui) |
| `scripts/` | GDScript files (`audio.gd`, `hud.gd`, `main.gd`, `player.gd`, `view.gd`) |
| `models/` | Kenney `.glb` 3D models — characters, props, level pieces |
| `meshes/` | `.tres` mesh resources |
| `objects/` | Reusable `.tscn` prefabs (player, enemies, pickups) |
| `sounds/` | Kit sound effects |
| `sprites/` | UI sprites and 2D art |
| `fonts/` | Bitmap and TTF fonts |
| `design/gdd/` | Per-system Game Design Documents (carried from browser branch) |
| `production/` | Sprint plans, milestone tracking |
| `docs/` | Narrative reference, audio inventory |

## Navigation aids

Every meaningful directory has its own `AGENTS.md` cheatsheet: a one-page
summary of what lives there, project-specific conventions, and links back
to CLAUDE.md + related docs. Read the local `AGENTS.md` FIRST when entering
a new directory — it's faster than grepping ten files. CLAUDE.md remains
the project-wide source of truth; the per-directory files defer to it for
anything they don't override.

## Dev Conventions

- **Language:** GDScript (kit's idiom); C# only if a system genuinely requires it
- **Indentation:** Tabs (Godot default)
- **Scenes:** Composition over inheritance — small `.tscn` files combined via `instance`
- **Signals:** Prefer Godot signals over polling for cross-node communication
- **Static typing:** `func foo(x: int) -> void:` — enforce typed GDScript everywhere
- **Naming:** `snake_case` files, `snake_case` variables/functions, `PascalCase` nodes/classes
- **Resources:** Use `Resource` types for save data and content definitions

## Skills

The `/add-scene`, `/add-npc`, `/add-dialogue` etc. slash commands in `.claude/skills/` were written
for the browser stack and **need to be rewritten for Godot**. Treat them as stale until ported.

CCGS testing skills (`/smoke-check`, `/playtest-report`, `/qa-plan`, `/test-setup`, `/test-helpers`,
`/soak-test`, `/dev-story`, `/regression-suite`, `/skill-test`) are imported and Godot-aware.

Use the **godot-specialist** and **godot-gdscript-specialist** subagents for engine-specific work.

## Testing

Headless smoke + flow tests live in `tests/smoke/` (Godot `SceneTree`-extending scripts, no
GDUnit4 needed). Run:

```bash
tests/run.sh         # all (lint + scene + flow + quest + playthrough)
tests/run.sh scene   # scene-boot only
tests/run.sh flow    # e1-flow only
tests/run.sh lint    # save-registration policy only
```

See `tests/README.md` for details. Both tests must pass before any branch can claim the E1
vertical slice ships.

### Pre-commit hook

Per-clone install (one-time, no dependencies):

```bash
git config core.hooksPath .githooks
```

The hook runs two policy lints (both `--staged`):

1. `tests/lint/check_save_registration.sh` — the **save-registration policy**:
   every autoload in `project.godot` must either (a) call
   `SaveManager.register_system("<id>", self)` somewhere in its script, or
   (b) carry a `# @no-save: <reason>` marker declaring it stateless. Without this
   guard, a new system that holds gameplay state can ship without being captured
   by the auto-save pipeline — state would silently disappear across save/load.
2. `tests/lint/check_collection_forks.sh` — the **collection-fork policy**: no
   top-level bool field in `scripts/*.gd` may use acquisition vocabulary
   (`*_found`, `*_acquired`, `has_*`, `got_*`, …). A set of like things (items,
   discovered rooms, unlocks) must live in ONE registry behind ONE add/enumerate
   API, not scattered per-instance bools that every consumer must special-case
   (the cause of the looted-fuse inventory bug #41 and the quest fork #36). Opt
   out genuinely-distinct state with `# @collection-ok: <reason>`.

## Collaboration Protocol

User-driven, not autonomous. Every task: **Question → Options → Decision → Draft → Approval**.
Ask before writing to any file. Show drafts before approval. No commits without instruction.

## Extended Docs

- `@.claude/docs/coordination-rules.md` — agent coordination rules
- `@.claude/docs/coding-standards.md` — coding standards (browser-era; needs Godot update)
- `design/gdd/` — per-system Game Design Documents
