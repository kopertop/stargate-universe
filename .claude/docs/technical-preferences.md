# Technical Preferences

## Engine & Language

- **Engine**: ggez (Three.js game framework)
- **Language**: TypeScript (strict mode, ESM)
- **Rendering**: WebGPU via `three/webgpu` (WebGL fallback)
- **Physics**: Crashcat (`@ggez/runtime-physics-crashcat`)
- **3D Runtime**: Three.js 0.181 + `@ggez/three-runtime`

## Naming Conventions

- **Classes**: PascalCase (`StarterPlayerController`)
- **Variables**: camelCase (`activeScene`)
- **Events**: camelCase with past tense (`sceneLoaded`, `playerDied`)
- **Files**: kebab-case (`runtime-physics.ts`)
- **Scenes**: kebab-case directory (`src/scenes/gate-room/`)
- **Constants**: UPPER_SNAKE_CASE (`FIXED_STEP_SECONDS`)

## Performance Budgets

- **Target Framerate**: 60 FPS
- **Frame Budget**: 16.6ms
- **Draw Calls**: < 200 per frame
- **Memory Ceiling**: 512MB

## Testing

- **Framework**: Vitest
- **Test Files**: `*.spec.ts` alongside source
- **Minimum Coverage**: Core gameplay systems must have tests
- **Required Tests**: Balance formulas, gameplay systems, scene loading

## Forbidden Patterns

- No `require()` — ESM only
- No `.then()` chains — use async/await
- No `var` — use `const` / `let`
- No hardcoded gameplay values — data-driven config

## Allowed Libraries / Addons

- `@ggez/*` — ggez framework packages
- `three` — 3D rendering
- `zustand` — State management (if needed)
- `zod` — Runtime validation
- `vitest` — Testing

## Architecture Decisions Log

- [ADR-001] Use ggez + vanilla Three.js (not React Three Fiber) for direct scene control
- [ADR-002] Use Crashcat physics (ggez built-in) — no Rapier
- [ADR-003] WebGPU renderer with WebGL fallback for modern performance
