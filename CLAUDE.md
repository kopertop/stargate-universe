# Stargate Universe — Game Project

A 3D exploration/adventure game set in the Stargate universe, built with ggez (Three.js game framework) and managed through Claude Code Game Studios agent architecture.

## Technology Stack

- **Engine**: ggez (Three.js game framework) + Three.js 0.181
- **Renderer**: WebGPU (via `three/webgpu`, WebGL fallback)
- **Physics**: Crashcat (ggez built-in) — always Crashcat, never Rapier
- **Language**: TypeScript (strict mode)
- **Build**: Vite + Bun
- **Package Manager**: Bun
- **Animation**: ggez animation pipeline (`@ggez/anim-*`)
- **Level Editing**: ggez World Editor (exports `.runtime.json` scenes)
- **Version Control**: Git with feature branches

## Project Structure

```text
/
├── CLAUDE.md                    # This file — master configuration
├── .claude/                     # Agent definitions, skills, hooks, rules, docs
├── src/
│   ├── main.ts                  # Entry point
│   ├── game/                    # Core game shell (app, camera, physics, player controller)
│   ├── scenes/                  # Scene modules (each scene = a level/area)
│   │   └── <scene-id>/
│   │       ├── index.ts         # Scene logic, systems, mount hook
│   │       ├── scene.runtime.json  # Exported from ggez editor
│   │       └── assets/          # Scene-local assets
│   ├── animations/              # Animation bundles from ggez animation editor
│   ├── systems/                 # Custom gameplay systems
│   └── ui/                      # HUD, menus, overlays
├── design/                      # Game design documents
│   └── gdd/                     # Per-system GDDs
├── assets/                      # Shared game assets (models, textures, audio)
├── tests/                       # Test suites
├── prototypes/                  # Throwaway prototypes
└── production/                  # Sprint plans, milestones, session state
```

## Technical Preferences

- **Naming**: Files: kebab-case. Variables/functions: camelCase. Types/classes: PascalCase. Constants: UPPER_SNAKE_CASE.
- **Indentation**: Tabs (3-space width). JSON/YAML: 2-space.
- **Modules**: ESM (import/export). No require().
- **Async**: async/await always. No `.then()` chains.
- **Validation**: Zod for runtime validation where needed.
- **Target Framerate**: 60 FPS
- **Frame Budget**: 16.6ms
- **Testing**: Vitest for unit/integration tests

## ggez Integration

- Scenes are authored in the ggez World Editor and exported as `scene.runtime.json`
- Each scene module in `src/scenes/<id>/` can define custom systems, mount hooks, and lifecycle callbacks
- The game shell (`src/game/app.ts`) handles scene loading, physics stepping, and the render loop
- Player controller is provided by ggez starter — customize in `src/game/starter-player-controller.ts`
- Use `@ggez/gameplay-runtime` for gameplay systems (event bus, entity queries)

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md
