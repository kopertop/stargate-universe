# Stargate Universe Development Plan

Last updated: 2026-05-09

This is the full-game roadmap for Stargate Universe: Destiny Restored. The first
locked implementation target is the Air Crisis episode because it exercises the
core game loop end to end: briefing, gate travel, resource collection, return,
ship repair, HUD feedback, and quest completion.

## Product Direction

Build a third-person exploration-survival game set aboard Destiny. The player is
Eli Wallace, restoring a damaged Ancient ship, solving ship crises, gathering
resources during planetary windows, and shaping crew outcomes through episode
arcs.

Primary pillars:

- The ship is the world. Destiny's rooms, systems, power, atmosphere, and hidden
  data are the main game space.
- Survival has purpose. Resources matter because the crew and ship visibly need
  them, not because of grind.
- Discovery is earned. Consoles, data caches, repairs, and mapped sections
  reveal meaning as Eli learns.
- Choices affect Destiny and the crew. Repairs, resource spending, dialogue, and
  priorities change later options.

Visual target:

- Dark Ancient metal interiors.
- Blue gate and console glow.
- Cinematic third-person framing.
- Code-native HUD based on the Destiny Restored concept images.
- Restoration panels for ship status, resources, repair progress, and system
  overview.

## Confirmed Patterns To Reuse

Use these Hollowlands patterns behaviorally, not by copying source:

- One central gameplay config for constants such as interaction radius, pickup
  radius, container slots, timers, mobile controls, and audio volumes.
- Unified input snapshot for movement, sprint, interact, inventory, hotbar,
  escape, and mobile virtual input.
- Single contextual interaction resolver. The nearest available action decides
  the current prompt and button label.
- Container/open loop. A crate, cache, or console exposes an Open prompt, plays
  feedback, updates state, and persists the opened/looted result.
- Pickup acknowledgement. Loot should give a short visual/audio response before
  disappearing, dimming, or opening.
- Minimal active-objective HUD. Show a few actionable objectives, animate
  completion, then reveal the next objective.
- Mobile parity. Movement joystick, camera drag zone, and context action buttons
  should drive the same input/actions as keyboard and gamepad.
- Debuggable routes. Every major state needs a direct route or debug hook so
  Playwright can test it without replaying the whole game.

## Phase 0: Stabilize The Current Repo

Goal: make the existing branch safe to continue from.

Tasks:

- Preserve current dirty player/VRM work and inspect it before modifying:
  `src/game/player/index.ts`,
  `src/game/player/vrm-player-controller.ts`,
  `src/systems/vrm/vrm-asset-loader.ts`,
  `src/systems/vrm/vrm-character-instance.ts`,
  `src/systems/vrm/vrm-mtoon-converter.ts`, and
  `src/game/player/test-character-controller.ts`.
- Gate or remove verbose VRM debug logging once character display is stable.
- Confirm the registered scene ids and direct routes:
  `gate-room`, `desert-planet`, `scrubber-room`, and `destiny-corridor`.
- Verify character loading in gate room and scrubber room with screenshots that
  show the player model out of bind pose.
- Keep Browser as the first visual QA path. If WebGL/WebGPU screenshots time out,
  use Playwright fallback and record the reason in `HANDOFF.md`.

Acceptance:

- `bun run typecheck` passes.
- `bunx vitest run tests/unit tests/systems` passes.
- `bun run build` passes or any blocker is documented with exact error text.
- Direct routes load with `&webgl=1`.

## Phase 1: Air Crisis Episode

Goal: finish the first complete episode slice.

Player path:

```text
gate-room -> desert-planet -> gate-room -> scrubber-room -> gate-room completion
```

Core implementation:

- Gate room briefing
  - Rush dialogue starts or advances Air Crisis.
  - Gate console/dialing is usable through real input.
  - The player can transition to `desert-planet` after the objective unlocks.
- Planetary run
  - Add a real countdown pressure layer for the planet window.
  - Collect three calcium/lime deposits through scene interaction, not only
    test-event injection.
  - Collection updates quest state, resource/state flags, HUD, and return prompt.
- Return and repair
  - Returning to gate room with lime shows the real lime delivery banner.
  - Route to scrubber room is clear and diegetic.
  - Scrubber repair requires lime, changes visuals red to green, emits
    `ship:subsystem:repaired`, and completes the quest.
- Completion
  - CO2 status normalizes.
  - Air Crisis completion gives a visible reward/state change.
  - Player lands back in gate room ready for the next restoration loop.

Minimum interfaces:

- `TimerSystem` with create, tick, cancel, serialize, and visible countdown
  query. Keep it generic and event-driven.
- Persistent loot/cache state keyed by id.
- Resource/story-item events for lime and ship parts.
- Debug helpers that can set scene, emit events, drive player input, and capture
  deterministic screenshots.

Acceptance:

- `tests/visual/air-questline.spec.ts` passes or snapshots are intentionally
  updated.
- A manual playthrough can complete the route without debug injection.
- HUD objective text, resources, and prompts reflect the current real state.

## Phase 2: Destiny Restoration Loop

Goal: make Destiny itself the repeatable core loop.

Core implementation:

- Expand lootable caches.
  - Supply crates grant Ship Parts and occasional survival resources.
  - Data caches unlock lore, map labels, or story flags.
  - Opened/looted state persists across scene remounts and save/load.
- Expand damaged subsystems.
  - Doors, conduits, consoles, lighting panels, and life-support units use the
    same interaction resolver.
  - Repairs show cost, progress, completion, and visible room/system response.
- Add restoration console.
  - Display ship status, resource counts, repairable systems, and priorities.
  - Let the player allocate power priorities through `ShipState.setPriorities`.
- Improve HUD.
  - Replace temporary resource glyphs with final icon assets.
  - Keep objective checklist concise and reactive.
  - Add repair progress and resource-spend feedback.

Acceptance:

- Player can explore, loot, repair, and observe a changed ship state.
- Resource spending and repair results are serialized.
- The restoration console reads and writes shared state, not scene-local copies.

## Phase 3: Crew, Dialogue, And Choice

Goal: make the ship feel inhabited and make choices matter.

Core implementation:

- Stabilize NPC placement and interaction prompts for Rush and key crew.
- Extend dialogue manager usage for episode beats, optional branches, and
  resource-contextual lines.
- Track affinity, major choices, crew morale, and crisis outcomes.
- Add crew status HUD/console surface based on the concept image.
- Make dialogue and quest progression save/load cleanly.

Acceptance:

- Rush and at least two crew members support repeatable interactions.
- Dialogue choices can start objectives, spend resources, or change flags.
- Crew state appears in the UI and persists.

## Phase 4: Planetary Runs And Resource Pressure

Goal: make off-ship runs a reusable survival structure.

Core implementation:

- Generalize the desert planet into a planetary-run framework.
- Add resource categories from the GDD: water, food, lime, Ship Parts, medical
  supplies, naquadah, and Ancient components.
- Add planet window timers, warnings, gate return rules, and failure outcomes.
- Add hazards that fit SGU: heat, low visibility, distance from gate, limited
  oxygen, hostile environmental events.
- Keep resources ship-wide. Do not add inventory tetris or weight management.

Acceptance:

- At least two planet runs use the same framework.
- Resource scarcity changes ship/crew state.
- Timers and resource consequences are visible in HUD or Kino/console UI.

## Phase 5: Polish, Performance, Save/Load, Deployment

Goal: make the game robust enough for repeated playtests.

Core implementation:

- Complete save/load across ship state, resources, quests, timers, exploration,
  dialogue, and current scene.
- Finish audio inventory gaps and remove references to missing voice files or
  upload the missing assets.
- Optimize scene load and memory disposal for repeated route transitions.
- Keep WebGPU default, WebGL fallback, and Playwright `&webgl=1` paths working.
- Add visual regression snapshots for every major episode state.
- Keep PWA generation deterministic and deployment documented.

Acceptance:

- A full Air Crisis save can be loaded from each major stage.
- Route transitions do not leak obvious VRAM/DOM/audio resources.
- CI or local verification covers typecheck, build, unit/system tests, and key
  visual states.

## Public Interfaces To Keep Stable

- Scene ids:
  - `start-screen`
  - `opening-cinematic`
  - `gate-room`
  - `desert-planet`
  - `scrubber-room`
  - `destiny-corridor`
- Debug route convention:
  - `/?scene=<scene-id>&webgl=1`
- Core debug hooks:
  - `window.__sgu.state()`
  - `window.__sgu.gotoScene(sceneId)`
  - `window.__sgu.press(action)`
  - `window.__sgu.drive(moveX, moveZ, lookX?, lookY?)`
  - `window.__sgu.screenshot(opts?)`
- Shared event families:
  - `resource:*`
  - `ship:*`
  - `quest:*`
  - `timer:*`
  - `player:*`

Do not add alternate APIs unless the existing public surface cannot support the
feature.

## Testing Standard

Every gameplay slice must ship with:

- A unit/system test for shared state logic.
- A Playwright or visual route test for the player-visible flow.
- A manual route checklist in `HANDOFF.md` if Browser/Playwright cannot capture
  the state reliably.

Standard commands:

```bash
bun run typecheck
bunx vitest run tests/unit tests/systems
bun run build
bun run test:visual -- tests/visual/air-questline.spec.ts
```

Use `bun run test:e2e` for broader smoke coverage when route/input changes land.

## Implementation Rules

- Use tabs for indentation in code.
- Prefer functional helpers and data-driven definitions where practical.
- Keep code DRY by moving shared interaction, loot, timer, and UI state logic
  into systems instead of copying scene-local variants.
- Use scene-local code for placement and visual flavor only.
- Keep UI text code-native. Concept imagery is a visual guide, not a raster UI.
- Preserve user/uncommitted work unless explicitly told to revert it.
