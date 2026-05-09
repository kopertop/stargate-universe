# Stargate Universe Handoff

Last updated: 2026-05-09

This is the practical handoff for the next engineer or agent working on the
Stargate Universe game. It records the current repo state, the intended next
slice, the concept references, the Hollowlands patterns to reuse, and the run,
build, and test path that should stay green.

## Current Snapshot

- Workspace: `/Users/cmoyer/Projects/personal/stargate-universe`
- Branch: `feature/hud-and-escape-fix`
- Remote tracking: `origin/feature/hud-and-escape-fix`
- Immediate target: finish the Air Crisis episode as the first complete playable
  slice.
- Full roadmap target: Destiny Restored, a third-person exploration-survival
  game about restoring Destiny, managing resources, repairing systems, and
  completing episode-sized SGU story arcs.

Current dirty work at the time of this handoff:

```text
M  src/game/player/index.ts
M  src/game/player/vrm-player-controller.ts
M  src/systems/vrm/vrm-asset-loader.ts
M  src/systems/vrm/vrm-character-instance.ts
M  src/systems/vrm/vrm-mtoon-converter.ts
?? src/game/player/test-character-controller.ts
```

Treat those files as existing in-progress character/VRM/player work. Do not
revert them while implementing gameplay docs or Air Crisis work. If character
display fixes are required, inspect the diff first and work with the existing
changes.

## Concept References

Use these as the visual north star:

- User-provided Destiny Restored UI concept:
  `/Users/cmoyer/Downloads/ChatGPT Image May 3, 2026, 11_02_00 AM.png`
- User-provided gate room concepts:
  `/Users/cmoyer/Downloads/E2728881-0C92-4680-9138-4CC7EC6007A7.PNG`
  `/Users/cmoyer/Downloads/E2728881-0C92-4680-9138-4CC7EC6007A7 2.PNG`
  `/Users/cmoyer/Downloads/034C1E8C-3007-4048-BBEF-C91BA629C0D2.PNG`
- Checked-in HUD concept:
  `design/concept-art/ui/destiny-restored-hud-layout.png`
- Checked-in gate room concepts:
  `design/concept-art/gate-room/gate-room-dormant.png`
  `design/concept-art/gate-room/gate-room-active.png`
  `design/concept-art/gate-room/gateroom-views-sheet.png`
- Checked-in Destiny ship concepts:
  `design/concept-art/destiny-ship/destiny-overview-sheet.png`
  `design/concept-art/destiny-ship/exterior-hero-shot.png`
  `design/concept-art/destiny-ship/exterior-views-sheet.png`

Visual target for the next slice:

- Dark Ancient metal interiors with blue gate glow.
- Code-native HUD with objective checklist, resource strip, hotbar, key hints,
  and contextual prompts.
- Restoration console panels that show ship status, resource allocation, and
  repair outcomes.
- Lootable caches and data caches placed in believable maintenance/storage
  spaces.
- Repair prompts with resource cost, progress feedback, and visible system state
  changes.

## Hollowlands Reference

Reference site:

- `https://hollowlands.andreelias.dev/`
- Bundle inspected behaviorally:
  `https://hollowlands.andreelias.dev/assets/index-DTqIPlow.js`

The bundle is a large minified React/Three/Rapier app. It was reachable as HTTP
200 on 2026-05-09 and can be beautified temporarily for inspection, but do not
copy source into this repo. Reuse the behavior patterns only.

Useful Hollowlands patterns confirmed from the site and bundle:

- Central constants/config object for gameplay tuning. SGU should keep comparable
  tuning in shared systems, not scattered magic numbers.
- Unified input snapshot with movement, sprint, interact, inventory, hotbar,
  and escape state. SGU already has `src/systems/input.ts`; extend that path.
- Context-sensitive interaction mode derived from current world state. The
  prompt label changes between Open, Cook, Craft, Door, Climb, Pick, Eat, and
  related actions. SGU should use the same single nearest-interaction decision
  pattern for crates, consoles, doors, data caches, scrubbers, and crew.
- Loot and container pattern: nearby interactable exposes an Open prompt,
  interaction toggles a menu or one-shot open state, audio feedback plays, and
  contents move into inventory/resources.
- Pickup feedback pattern: collected objects provide short visual/audio
  acknowledgement before disappearing or dimming.
- Objective tracker pattern: only a few active objectives are visible at once,
  completion animates, and the next objective slides in. SGU's HUD can keep the
  same discipline without copying the UI.
- Mobile controls pattern: left joystick zone for movement, right drag zone for
  camera, and contextual action buttons based on available interaction state.
- Debug-friendly gameplay loops: direct route loading, injected input/events,
  stable screenshot hooks, and deterministic state setup for tests.

## Current Gameplay Architecture

Keep the existing architecture:

- Scene modules own scene-local geometry, prompts, route transitions, and
  scene-specific interaction placement.
- Shared systems own cross-scene game state, events, input, HUD, quests,
  resources, ship state, save/load hooks, and debug hooks.
- Do not create a second app shell, second input layer, or second quest system.

Important systems:

- `src/systems/input.ts`: shared keyboard/gamepad/touch action mapping.
- `src/systems/event-bus.ts`: game event transport.
- `src/systems/quest-manager.ts`: SGU adapter over the engine quest manager.
- `src/systems/resources.ts`: ship-wide resource pool.
- `src/systems/supply-crates.ts`: shared supply crate mesh/open-state helper.
- `src/systems/ship-state.ts`: Destiny systems, sections, subsystems, repairs,
  and power distribution.
- `src/systems/save-manager.ts`: save/load bridge.
- `src/systems/debug-api.ts`: `window.__sgu` controls for Playwright/manual QA.
- `src/ui/hud.ts`: Hollowlands-inspired DOM HUD.
- `src/ui/touch-controls.ts`: mobile/coarse-pointer controls.

Important scenes:

- `src/scenes/start-screen/index.ts`
- `src/scenes/opening-cinematic/index.ts`
- `src/scenes/destiny-gate-room/index.ts`, registered as scene id `gate-room`
- `src/scenes/desert-planet/index.ts`
- `src/scenes/scrubber-room/index.ts`
- `src/scenes/destiny-corridor/index.ts`

Important quests:

- `src/quests/air-crisis/definition.ts`
- `src/quests/air-crisis/index.ts`
- `src/quests/destiny-power-crisis/definition.ts`
- `src/quests/destiny-power-crisis/index.ts`

## Run And Build

Install dependencies:

```bash
bun install
```

Run for manual testing:

```bash
bun run dev -- --host 127.0.0.1
```

Playwright's config starts the dev server automatically for tests using:

```bash
bun run dev
```

Useful direct routes:

```text
http://127.0.0.1:5173/
http://127.0.0.1:5173/?scene=gate-room&webgl=1
http://127.0.0.1:5173/?scene=gate-room&lime=1&webgl=1
http://127.0.0.1:5173/?scene=desert-planet&webgl=1
http://127.0.0.1:5173/?scene=scrubber-room&webgl=1
http://127.0.0.1:5173/?scene=destiny-corridor&webgl=1
```

Use `&webgl=1` for headless/Playwright work. Browser/WebGPU screenshot capture
can be unreliable in headless Chromium; the existing visual tests use
`page.screenshot()` plus `toMatchSnapshot()` because that path has been more
stable than `toHaveScreenshot()`.

Build:

```bash
bun run build
```

The build runs PWA generation first. If `public/manifest.webmanifest` or
`public/sw.js` changes, inspect whether the generation is deterministic before
staging.

## Test Path

Fast static check:

```bash
bun run typecheck
```

Focused unit/system harness:

```bash
bunx vitest run tests/unit tests/systems
```

Full Vitest suite:

```bash
bun run test
```

Core Playwright E2E:

```bash
bun run test:e2e
```

Air Crisis visual route suite:

```bash
bun run test:visual -- tests/visual/air-questline.spec.ts
```

If snapshots are intentionally changed:

```bash
bun run test:visual:update -- tests/visual/air-questline.spec.ts
```

The Air Crisis visual suite is the most concrete acceptance test for the next
slice. It covers:

- Gate room initial CO2 HUD.
- Rush dialogue panel and response options.
- Gate dialing.
- Lime return banner.
- Desert planet arrival.
- Calcium deposit states.
- Gate return prompt.
- Scrubber room blocked-without-lime state.
- Scrubber repair transition and quest completion.

## Air Crisis Continuation Path

The fixed acceptance path is:

```text
gate-room -> desert-planet -> gate-room -> scrubber-room -> gate-room completion
```

Implementation priorities:

1. Gate room briefing
   - Rush starts or advances the Air Crisis quest.
   - Gate console/dialing transitions reliably to `desert-planet`.
   - HUD shows current visible Air objectives and CO2 pressure.
2. Desert planet collection
   - Player can collect three calcium/lime deposits through the real input path.
   - Collection updates resources or scene transition state through shared
     events, not test-only DOM injection.
   - Completion enables the gate return prompt.
3. Return and scrubber repair
   - Returning to gate room with lime shows the real `#lime-delivery-banner`.
   - Player is routed to `scrubber-room`.
   - Scrubber repair requires lime, updates visuals from red to green, emits
     `ship:subsystem:repaired`, and completes `fix-scrubbers`.
4. Completion
   - Quest completion normalizes CO2 HUD state.
   - Player returns to gate room with a visible sense that Destiny is more
     stable than before.

## Known Risks

- Current uncommitted character/VRM work may change player rendering and route
  load behavior. Inspect before editing character code.
- `gate-room` is the registered gameplay scene id even though the implementation
  file lives under `src/scenes/destiny-gate-room/`.
- Some tests use event injection for visual states. Do not treat those as proof
  of real input flow unless the matching E2E or manual path has also been tested.
- WebGPU/WebGL behavior differs between manual browser, Playwright, and
  SwiftShader. Use `&webgl=1` when checking deterministic screenshots.
- Service worker/PWA generation can modify tracked files.
- The Hollowlands bundle is third-party minified source. Use it as a design and
  behavior reference only.

## Definition Of Done For The Next Slice

- `HANDOFF.md` and `PLAN.md` remain current.
- Air Crisis can be completed through real gameplay input from gate room to
  desert planet to scrubber room.
- HUD objectives, resource counts, prompts, and repair state all update from
  shared systems/events.
- Lootable crates/caches work through the same interaction decision path as
  repairs and consoles.
- `bun run typecheck`, `bun run build`, and
  `bunx vitest run tests/unit tests/systems` pass.
- `tests/visual/air-questline.spec.ts` either passes or has explicitly reviewed
  snapshot updates.
