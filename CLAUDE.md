# Stargate Universe

A browser-based sci-fi open-world RPG set in the Stargate Universe TV series. Players take on the
role of crew aboard the ancient ship Destiny, exploring uncharted galaxies, managing resources,
making story-defining choices, and surviving against alien threats — all running natively in the
browser with WebGPU rendering.

## Engine

Built on **`@kopertop/vibe-game-engine`** ([kopertop/vibe-game-engine](https://github.com/kopertop/vibe-game-engine))
via the `@ggez/*` package ecosystem.

- **Renderer:** Three.js r181 + WebGPU (`three/webgpu`), WebGL fallback
- **Physics:** Crashcat (`@ggez/runtime-physics-crashcat`) — always Crashcat, never Rapier
- **Animation:** `@ggez/anim-runtime` + `@ggez/anim-three` with VRM retargeting
- **Event bus:** `@ggez/gameplay-runtime` typed event bus
- **Scene system:** ggez World Editor → `scene.runtime.json` exports consumed at runtime
- **Build:** Vite + Bun + Wrangler (Cloudflare Pages deployment)

## Architecture Status

### Implemented

- Fixed-timestep game loop (ggez game-dev shell)
- VRM character system (~3,600 LOC — character loading, retargeting, LOD)
- Crashcat physics integration
- Typed event bus
- Auto-discovered scene system
- Ship state management
- Basic inventory

### Pending

- Dialogue system (`/add-dialogue`)
- NPC AI (`/add-npc`)
- Save / load (`/add-save-field`)
- HUD / player UI (`/add-hud-element`)
- Crafting system (`/add-recipe`)
- Planet generation (`/add-planet`, `/add-biome`)


## Key Paths

| Path | Contents |
|---|---|
| `src/game/` | Core game shell — app, camera, physics, player controller |
| `src/systems/` | Custom gameplay systems (ECS-style) |
| `src/scenes/` | Scene modules — each scene = one level/area |
| `src/animations/` | Animation bundles from ggez animation editor |
| `src/ui/` | HUD, menus, overlays (HTML overlay on canvas) |
| `design/gdd/` | Per-system Game Design Documents (15 GDDs authored) |
| `assets/` | Shared models, textures, audio |
| `production/` | Sprint plans, milestones, session state |

## Skills

To add content to this game, use the **vibe-game-engine Agent Skills** from
`~/.claude/skills/` (or the engine's `skills/` directory). The most relevant skills are:

| Skill | What it creates |
|---|---|
| `/add-scene` | New level or area with scene module + runtime.json stub |
| `/add-npc` | NPC with VRM model, schedule, and dialogue hooks |
| `/add-dialogue` | Branching dialogue tree (Bioware-style) |
| `/add-item` | Inventory item (collectible, tool, consumable, story artifact) |
| `/add-quest` | Quest with objectives, stages, and rewards |
| `/add-crew-member` | Named Destiny crew member with VRM config and relationship arc |
| `/add-episode` | Story episode with narrative beats, choices, and episode-end snapshot |
| `/add-planet` | Full planet definition for the planetary-runs system |
| `/add-level` | **META** — full level orchestrating scene + NPCs + quests + audio |

See [`docs/skills-roadmap.xlsx`](https://github.com/kopertop/vibe-game-engine/blob/main/docs/skills-roadmap.xlsx)
in the engine repo for the complete 47-skill inventory.

## Dev Conventions

- **Indentation:** Tabs (not spaces)
- **Style:** Functional TypeScript preferred — pure functions, no classes unless required by a library
- **Modules:** ESM only (`import`/`export`); no `require()`
- **Async:** `async`/`await` always; no `.then()` chains
- **Validation:** Zod for runtime validation at all content boundaries
- **Package manager:** Bun
- **Naming:** `kebab-case` files, `camelCase` variables/functions, `PascalCase` types, `UPPER_SNAKE_CASE` constants
- **Target:** 60 FPS, 16.6 ms frame budget

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question → Options → Decision → Draft → Approval**

- Ask before writing to any file
- Show drafts or summaries before requesting approval
- No commits without user instruction

## Extended Docs

- `@.claude/docs/coordination-rules.md` — agent coordination rules
- `@.claude/docs/coding-standards.md` — detailed coding standards
- `@.claude/docs/context-management.md` — context management across sessions
- `design/gdd/` — per-system Game Design Documents
