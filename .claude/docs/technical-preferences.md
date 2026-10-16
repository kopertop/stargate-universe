# Technical Preferences

## Engine & Language

- **Engine**: Three.js 0.180 (vanilla, via import map — no framework wrapper)
- **Language**: JavaScript (ES modules, no transpile)
- **Rendering**: `THREE.WebGLRenderer` (WebGL; no WebGPU path)
- **Physics**: Built-in colliders (Box3 / axis-aligned boxes from `src/components.js`, `src/destination.js`, `src/gate-room.js`) — no physics engine
- **3D Runtime**: Three.js 0.180 via jsdelivr import map (three.module.js + examples/jsm addons), vendored by `build.sh` for the itch.io zip

## Naming Conventions

- **Classes**: PascalCase (`THREE.Scene`, imported constructor functions)
- **Variables**: camelCase (`activeScene`, `roomColliders`)
- **Events**: camelCase with past tense (`loaded`, `interacted`, `questChanged`)
- **Files**: kebab-case (`src/gate-room.js`, `src/ship.js`)
- **Scenes**: one module per scene/world (`src/gate-room.js`, `src/destination.js`, `src/ship.js`)
- **Constants**: UPPER_SNAKE_CASE (`PLAYER`, `MODEL_URL`, `FIXED_STEP_SECONDS`)

## Performance Budgets

- **Target Framerate**: 60 FPS
- **Frame Budget**: 16.6ms
- **Draw Calls**: < 200 per frame
- **Memory Ceiling**: 512MB
- **Asset loading**: GLBs (Quaternius rigs) + audio streamed from `assets/` / `sounds/`; keep build zip lean

## Testing

- **Unit Tests**: 27 test files covering all 25 `src/*.js` modules, using Node 18+ built-in test runner (`node --test tests/*.test.js`, zero framework deps). 943 tests pass. CI runs them in the `web-game` job.
- **Approach**: unit tests for module contracts (return shapes, state transitions, edge cases) + manual playtesting for feel + `src/leveledit.js` dev recorder (`recorder.js` removed from dist by `build.sh`)
- **Test Files**: `tests/*.test.js` — one per source module, plus integration tests (`rpg-integration.test.js`, `quest-engine.test.js`)
- **Required Checks**: `npm test` (943 unit tests), `npm run lint` (ESLint 0 errors), `npm run typecheck` (tsc --noEmit, 0 errors). Game boots to first playable room (`src/main.js` → `src/gate-room.js`), interaction + quest transitions work, audio cues play, ship status rows render correctly

## Forbidden Patterns

- No bundler/transpiler requirements — keep plain ES modules working from CDN import map
- No `.then()` chains — use async/await
- No `var` — use `const` / `let`
- No hardcoded gameplay values in render logic — data-driven config (`data/items.json`, `data/ship_layout.json`, `PLAYER` consts)

## Allowed Libraries / Addons

- `three@0.180` (build + examples/jsm addons)
- `@tweenjs/tween.js` style helpers only if vendored by `build.sh`
- No React / R3F in the runtime path

## Architecture Decisions Log

- [ADR-001] Plain vanilla Three.js (no React Three Fiber) — direct scene control, zero framework indirection
- [ADR-002] Hand-rolled colliders (Box3 / axis-aligned boxes) — no physics engine; gameplay tuning lives in `src/*.js` constants
