# Adversarial Code Review — SGU Air Questline
Reviewer: Claude (adversarial mode)
Date: 2026-04-12

---

## Executive Summary

The core systems (dialogue, quest, NPC, save managers) are well-architected and cleanly typed — the factory-function pattern, typed event bus, and functional dialogue state are genuinely good work. However, the codebase has a **critical save/reload soft-lock** from the lime flag not being persisted, **pervasive GPU memory leaks** from missing Three.js disposal, and a **test suite that actively lies** — visual tests inject synthetic events with wrong IDs and fake DOM elements, providing false confidence while the real game flow is untested. The gate-room scene (2048 lines) is doing far too much. Not shippable without fixing BUG-001, BUG-003, and BUG-004.

---

## Critical Bugs (must fix before shipping)

### BUG-001: lime flag lost on save/reload — guaranteed soft-lock
**File:** `src/systems/scene-transition-state.ts` (line 18), `src/systems/save-manager.ts`

**Problem:** `_limeCollected` is a plain module-level `let` that never enters the save schema. `SaveData` serializes `questState`, `dialogueState`, `shipState`, and `resources` — but not scene-transition-state. If the player:
1. Gates to the desert planet, collects all 3 deposits, returns to Destiny
2. Presses F5 (autosave or manual save fires)
3. Closes the tab or reloads
4. Loads the slot

…they land in gate-room with quest showing `return-to-destiny` complete, but `isLimeCollected()` returns `false`. The scrubber entrance only appears when `isLimeCollected()` is true. The player cannot access the scrubber room. The gate can be re-dialed, but on the fresh desert-planet scene `collectedCount` starts at 0, and the `return-to-destiny` objective is already completed (so advancing it via `advanceObjective` is silently ignored). The player is effectively stuck.

**Reproduction:**
1. Complete desert planet collection; return through gate
2. F5 → reload → Load the save slot
3. Gate room: scrubber entrance never appears; quest log still says `fix-scrubbers` is pending

**Fix:**
```typescript
// src/types/save.ts — add to SaveData
limeCollected?: boolean;

// src/systems/save-manager.ts — in save():
import { isLimeCollected } from '../systems/scene-transition-state.js';
// ...
const data: SaveData = {
  ...,
  limeCollected: isLimeCollected(),
};

// in load(), after gotoScene():
import { setLimeCollected } from '../systems/scene-transition-state.js';
setLimeCollected(data.limeCollected ?? false);
```

---

### BUG-002: Player can return from desert without all deposits — UX dead-end
**File:** `src/scenes/desert-planet/index.ts` (~line 468)

**Problem:** The E-key handler for gate return:
```typescript
} else if (nearGate) {
    setLimeCollected(collectedCount >= totalDeposits);  // false if partial
    questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "return-to-destiny");
    void context.gotoScene("gate-room");
}
```
There is **no guard** preventing return with partial collection. If `collectedCount < 3`, `setLimeCollected(false)` is called, the player lands in gate-room with `isLimeCollected() === false`, and the scrubber entrance never appears. There is no on-screen message telling them why they're stuck or that they need to go back. Combined with BUG-001 (save after this state), this is a guaranteed soft-lock.

**Reproduction:** Enter gate, collect 1 of 3 deposits, stand near gate and press E.

**Fix:** Either block the return entirely (`if (collectedCount < totalDeposits) { show message; return; }`) or allow partial return but make the gate-room clearly tell the player why the scrubber entrance isn't visible. The former is simpler and more faithful to the show (Rush would never accept a half-measure).

---

### BUG-003: GPU memory leak — Three.js geometry and materials never disposed on scene teardown
**File:** `src/scenes/gate-room/index.ts` (dispose block ~lines 1999-2031), `src/scenes/desert-planet/index.ts`, `src/scenes/scrubber-room/index.ts`

**Problem:** The `dispose()` lifecycle of all three scenes cleans up event listeners, DOM elements, and system managers — but it does NOT call `geometry.dispose()` or `material.dispose()` on the hundreds of `BoxGeometry`, `LatheGeometry`, `CircleGeometry`, `TorusGeometry`, `CylinderGeometry`, `SphereGeometry`, `RingGeometry`, and `MeshStandardMaterial` objects created during `mount()`. Each round-trip gate-room→desert-planet→gate-room creates and orphans ~200+ GPU objects. These accumulate in VRAM.

There's exactly ONE geometry dispose call visible in the codebase: inside the progress-bar widget's internal `dispose()` (gate-room lines ~1346-1353). The room, stargate, lighting, corridor, storage room, scrubber units, calcium deposits — none are disposed.

The `extWallMat` and `extCeilingMat` (gate-room lines ~966-973) are created at **module scope** and never disposed at all, not even between remounts.

**Fix:** Build the scene into a traversable group, then in `dispose()`:
```typescript
scene.traverse((obj) => {
  if (obj instanceof THREE.Mesh) {
    obj.geometry.dispose();
    if (Array.isArray(obj.material)) obj.material.forEach(m => m.dispose());
    else obj.material.dispose();
  }
});
```
Or maintain an explicit disposal list built during `mount()` — the latter is safer since it doesn't accidentally dispose shared assets.

---

### BUG-004: Visual tests inject wrong dialogue IDs — false confidence
**File:** `tests/visual/air-questline.spec.ts` (lines 82-115)

**Problem:** Tests 2 and 3 emit `crew:dialogue:started` and `crew:dialogue:node` with `dialogueId: "dr-rush-air-crisis"` and `nodeId: "co2-intro"`. The actual dialogue tree has `id: 'dr-rush'` (`src/dialogues/dr-rush.ts` line 21) and starts at `startNodeId: 'greeting'` (line 22). These IDs do not exist anywhere in the real codebase.

Test 5 (lime banner) **manually injects a fake DOM div** via `page.evaluate()` that impersonates the lime banner, then asserts the fake element is visible. This test tells you nothing about whether `isLimeCollected()` actually triggers the banner. It is purely cosmetic.

These tests will pass even if:
- The dialogue system is completely broken
- The player:interact → startDialogue → crew:dialogue:started event chain never fires
- The lime banner logic is deleted

**Fix:** Tests 2-3 must use the actual IDs `dialogueId: "dr-rush"`, `nodeId: "greeting"`. Test 5 must actually trigger `setLimeCollected(true)` via the game's exposed API (or via the existing `__sguEmit` hook wiring a real `resource:collected` sequence), not by hand-crafting DOM.

---

### BUG-005: `advance()` terminates on `options.length === 0`, not visible options
**File:** `src/systems/dialogue-manager.ts` (line 101)

**Problem:**
```typescript
if (nextNode.options.length === 0) { endDialogue(); return null; }
```
This checks the raw `options` array, not the filtered `getVisibleOptions()` result. If every option on a node has a `condition` that returns `false` for the current state (all options hidden), the dialogue system stays active and `null` options are sent to the UI. The player sees speaker text with no reply buttons and no way to close the panel. Since `isActive()` remains true, no other interaction can start. This is a hard UI freeze.

The current Rush tree has no such node, but the system is one badly-written condition away from this happening.

**Fix:**
```typescript
const visible = getVisibleOptions(nextNode, session.state);
if (nextNode.options.length === 0 || visible.length === 0) { endDialogue(); return null; }
```

---

### BUG-006: `requestAnimationFrame` callback in `buildLighting` runs on disposed scene
**File:** `src/scenes/gate-room/index.ts` (~line 425)

**Problem:**
```typescript
const helper = new THREE.SpotLightHelper(spot, 0xffff00);
helper.visible = false;
scene.add(helper);
requestAnimationFrame(() => helper.update());  // ← stale closure risk
debugObjects.push(helper);
```
`buildLighting()` is called inside `mount()`, which returns synchronously. If `dispose()` is called before the RAF fires (e.g., rapid scene transition, test teardown), `helper.update()` runs on a helper whose parent scene has been cleared. `SpotLightHelper.update()` calls `this.light.target.getWorldPosition()`, which can throw if the light was removed from the scene graph without proper disposal.

**Fix:** Remove the RAF. The helpers have `visible = false` and serve no runtime purpose — delete them entirely, or if needed for dev mode, call `helper.update()` synchronously right after `scene.add(helper)`.

---

## Architecture Concerns (fix soon)

### ARCH-001: gate-room/index.ts is a 2048-line god object

This file is responsible for: room geometry construction, stargate FSM (5 states), chevron animation, kawoosh physics, camera arm pull-in with raycasting, debug overlay, escape menu, fullscreen/pointer-lock management, corridor+storage rooms, subsystem visual markers, progress bar widget, quest setup, dialogue+NPC+save manager instantiation, event wiring, resource initialization, lime banner UI, HUD creation, and the entire `mount`/`update`/`dispose` lifecycle.

It needs to be decomposed. Suggested split:
- `gate-room/gate-animation.ts` — GateRuntime, FSM, updateGate, buildStargate
- `gate-room/room-geometry.ts` — buildRoom, buildCorridor, buildStorage, buildLighting
- `gate-room/camera-occlusion.ts` — updateCameraPullIn and related module-level state
- `gate-room/systems.ts` — createDialogueManager, createQuestManager, createSaveManager wiring
- `gate-room/hud.ts` — HUD components, escape menu, fullscreen setup
- `gate-room/index.ts` — mount() lifecycle only, delegates to all of the above

---

### ARCH-002: Three independent QuestManagers with manual objective pre-advancement

Each scene creates its own `createQuestManager()` instance and manually advances objectives to simulate "the earlier scenes already happened":

```typescript
// scrubber-room/index.ts
questManager.startQuest(AIR_CRISIS_QUEST_ID);
questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "speak-to-rush");
questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "locate-planet");
questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "gate-to-planet");
questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "find-lime");
questManager.advanceObjective(AIR_CRISIS_QUEST_ID, "return-to-destiny");
```

This is fragile in at least three ways: (1) if an objective ID is renamed, all three scene files silently fail to advance it; (2) the quest log visible to the player never reflects real cumulative progress (each scene starts a fresh log); (3) the pre-advancement bypasses visibility guards — `advanceObjective` advances even non-visible objectives, meaning the objective chain could be corrupted if objectives are reordered.

The right architecture is to deserialize the canonical quest state (from gate-room's save system) into the scene-local manager on mount, rather than replaying fake advances. Or better: make the quest manager a singleton that persists across scene transitions (passed via a global context or the scene's `context` object).

---

### ARCH-003: Module-level mutable arrays shared across scene remounts

`wallMeshes`, `occludableMeshes`, `cameraRaycaster`, `scratchCamDir`, `smoothedCamDistance`, `lastHitDistance`, `activeWormholeFrame`, `extWallMat`, `extCeilingMat` are all declared at module scope in `gate-room/index.ts`. The mount function clears the arrays (`wallMeshes.length = 0`, `occludableMeshes.length = 0`) and resets scalars, which partially mitigates this. But:
- The module-level materials (`extWallMat`, `extCeilingMat`) are created ONCE at import time and never disposed — if those materials ever gain textures, they'll never be freed
- The camera raycaster and scratch vector being module-level means two concurrent mount calls (shouldn't happen but could in test environments) would corrupt state
- Any refactor that adds a path to `buildCorridor()` without going through `mount()` would silently accumulate meshes

All of this state should live inside `mount()` and be captured in the closure.

---

### ARCH-004: Save/load does not restore scene position — only saves sceneId

`save-manager.ts` saves `currentSceneId` and `playerPosition`, but after `load()` the position is not applied. Looking at `load()`:
```typescript
await gotoScene(data.currentSceneId);
shipState.deserialize(data.shipState);
deserializeResources(data.resources ...);
questManager.deserialize(data.questState);
dialogueManager.deserialize(data.dialogueState);
// playerPosition: never used
```
The saved player position is captured but never restored. Every load spawns the player at the scene's default spawn point.

---

## UX / Soft-lock Risks

### UX-001: CO2 timer is purely cosmetic — urgency completely undermined

The `createCO2Timer(8 * 60 * 60)` in desert-planet starts an 8-hour countdown. It counts down, changes color below 2 minutes, shows a ⚠ icon — but when it reaches 0, nothing happens. No fail state, no game over screen, no forced return, no Rush yelling at you. Players who explore for 30 minutes in-game have the exact same outcome as players who sprint directly to the gate.

This completely kills the tension that defines SGU's "Air" episode. The whole premise is that people are **dying**. If the timer has no teeth, it's decoration. Either enforce it (fail state / forced scene transition at zero) or remove it and replace it with a visible but consequence-free atmospheric indicator.

### UX-002: No waypoint to scrubber room entrance

After returning from the desert, the lime banner says "Take the lime to the CO₂ scrubber room — Deck 3, Section 7." But the scrubber entrance (`SCRUBBER_ENTRANCE_POS`) is just a position in world space with a 2.2m proximity radius. There's no marker, no glowing floor arrow, no minimap dot. In a 26×40m room with a corridor and storage extension, "somewhere near the front" could mean anything. First-time players will walk past it.

### UX-003: No feedback when player tries to gate back without lime

If the player returns from desert with `collectedCount < 3` (BUG-002), then tries to enter the scrubber entrance in gate-room, they just can't — the entrance proximity check returns false because `isLimeCollected() === false`. No message. No "you need to collect the calcium deposits first." Complete silence.

### UX-004: Dialogue can be escaped mid-conversation with no state consequence

`farewell-early` option ends the dialogue without committing. If Rush's `rush-co2-committed` flag is never set, the dialogue tree offers the same commitment options on re-entry — which is correct. But if the player speaks to Rush, triggers the `crew:dialogue:started` animation, then dismisses with ESC before picking any option, the panel hides but `session` is still active in the dialogue manager (`endDialogue` is never called). The NPC is stuck in `interact` state indefinitely. The only recovery is calling `endDialogue()` or navigating away.

---

## Test Gaps

1. **No test for the actual player:interact → startDialogue → crew:dialogue:node chain.** Unit tests verify the quest definition structure. Visual tests inject fake events. Nobody tests that clicking on Rush actually triggers the dialogue system.

2. **No test for save/load round-trip.** The most important serialization behavior — does loading a save restore quest state correctly? Does the lime flag serialize correctly (it doesn't, per BUG-001)? Zero coverage.

3. **No test for dialogue completion triggering quest objective advance.** The `commit-to-gate` → `advanceObjective("speak-to-rush")` wiring is untested. It lives in an event bus subscription in gate-room/index.ts and is invisible to the unit tests.

4. **No test for the scene-transition-state lime flag lifecycle.** The unit tests have `isLimeCollected()/setLimeCollected()` basic tests, but nothing that tests: "collect all deposits → return through gate → gate-room shows scrubber entrance → enter scrubber → repair → flag cleared."

5. **No test for QuestManager auto-wiring.** The `on('resource:collected')` subscription in quest-manager is never unit-tested. What if `targetId` doesn't match? What if the event fires before the quest starts?

6. **Visual test 10 teleports player via `window.__sgPlayer` which may not be exposed.** There is no `(window as any).__sgPlayer = player;` in the desert-planet scene's mount() — only `__sceneReady` and `__sguBus`. This test will silently fail to teleport the player and screenshot an arbitrary player position.

7. **No integration test for quest completion triggering autosave.** The save manager subscribes to `quest:completed` on the global bus, but this is not tested at the system level.

---

## Code Quality Issues

### CQ-001: Double cast hides real type incompatibility
`src/systems/save-manager.ts` line ~150:
```typescript
resources: resourcesRaw as unknown as ResourceSnapshot,
```
And line ~175:
```typescript
deserializeResources(data.resources as unknown as Record<string, unknown>);
```
The `as unknown as X` double cast is a code smell that says "the types don't match and I don't want to fix it." This should be typed properly — either `serializeResources()` should return `ResourceSnapshot` directly, or `ResourceSnapshot` should be typed as `Record<string, unknown>`.

### CQ-002: `as any` in production game loop
`src/scenes/desert-planet/index.ts` and `src/scenes/scrubber-room/index.ts`:
```typescript
compassHud.update(camera as any, delta);
```
`camera` is `THREE.Camera` everywhere in the scene context; `HudComponent.update` expects `THREE.Camera`. These types match — the cast is unnecessary and hides whether this was ever a real type error that was just silenced.

### CQ-003: Magic strings across scene boundaries
The string `"calcium-deposit"` appears in: `quests/air-crisis/definition.ts` (targetId), `scenes/desert-planet/index.ts` (emit payload type), and implicitly `systems/quest-manager.ts` (comparison). Same pattern for `"co2-scrubbers"`, `"gate-console"`, `"dr-rush"`, `"desert-planet"`. There's a `QUEST_ID = 'air-crisis'` constant — apply the same discipline to all cross-scene strings:
```typescript
// src/systems/resources.ts or src/constants.ts
export const RESOURCE_CALCIUM = 'calcium-deposit' as const;
export const SUBSYSTEM_CO2 = 'co2-scrubbers' as const;
export const SCENE_DESERT_PLANET = 'desert-planet' as const;
```

### CQ-004: `Math.random()` in deterministic geometry builders
`src/scenes/desert-planet/index.ts`:
```typescript
crystal.rotation.z = (Math.random() - 0.5) * 0.4;
```
```typescript
const mat = Math.random() > 0.4 ? rockMat : darkRockMat;
```
Non-deterministic terrain means rocks and crystals change position/appearance on every scene load. Not currently a problem (no collision detection), but if you add physics or navigation later, these random positions will make reproduction of physics bugs impossible. Seed a PRNG or use fixed geometry.

### CQ-005: `resources.ts` serialization type gap
`src/systems/resources.ts` exports `serialize()` and `deserialize()` but the save manager casts around both their types. The resource system's type surface needs to align with `ResourceSnapshot` in `types/save.ts`.

### CQ-006: `getResource`, `addResource`, `consumeResource`, `hasResource`, `getAllResources` are all imported in gate-room but only `initResources` is actually needed at setup time
Six resource functions imported; unclear which are actually called in the gate-room scene vs imported speculatively. Dead imports increase bundle surface and create confusion about ownership.

### CQ-007: Dialogue `endDialogue()` is called from both `advance()` (auto-end on empty options) and externally — double-call risk
`advance()` calls `endDialogue()` when `nextNode.options.length === 0`. `endDialogue()` guards with `if (!session) return` — so a double-call is safe. But `dispose()` on the manager also calls `endDialogue()`. Consider whether `dispose()` should call `endDialogue()` or just null out the session directly, since `endDialogue()` fires `crew:dialogue:ended` which triggers NPC state transitions — inappropriate during scene teardown.

---

## SGU Authenticity Issues

### SGU-001: "Remarkable. You actually pulled it off." — Not Rush's voice
`src/scenes/scrubber-room/index.ts`:
```typescript
createRushDialogue("Remarkable. You actually pulled it off.")
```
Rush would **never** say this. He's not impressed by people doing the obvious minimum to survive. He might say: *"The scrubbers are cycling. The crew won't asphyxiate. Don't expect gratitude — you did what any marginally competent person would have done given sufficient motivation."* Or, more Rush: *"CO₂ nominal. Try not to die from something else while I get back to work."* The current line sounds like a mentor praising a student. Rush sounds like a man who's annoyed you interrupted him.

### SGU-002: CO2 timer at 8 hours is too generous
The episode creates acute crisis tension. Rush says "twelve hours" but the scrubber degradation makes that optimistic. Eight hours of casual exploration on a desert planet drains the urgency. In the show, Eli is running. A 20-minute timer (matching a real episode's compressed drama) with an actual fail state would be closer to canon.

### SGU-003: Gate stays active indefinitely — no FTL timer
In SGU, the wormhole doesn't stay open indefinitely — and more critically, Destiny has a jump timer. The ship could jump to FTL and strand anyone on the planet. There is no FTL threat mechanic here. Even a visible countdown ("FTL jump in: 4h 22m") would add tension, even if it's not enforced initially.

### SGU-004: Rush is at position `{ x: 0, y: 0, z: -8 }` with no patrol
The NPC definition has `patrolDwellTime: 0` and no `patrolPath`. Rush is a statue. He never paces, never turns to a console, never gestures. For a character who's always working, always at the interface, this is wrong even with placeholder VRM. Even a slow 2-point patrol along his console would read better.

### SGU-005: Players choose to go through the gate — it should feel more desperate
The "I'll go through the gate" option is presented alongside "I need a moment to think." In the episode, Eli doesn't really have a choice — he's basically voluntold. The tone of options is too casual. Rush's opening line should pressure harder: no "or else" implicit. "Stop asking questions and start moving" should be the default branch, not an option the player selects.

---

## What's Actually Solid

1. **The event bus design is excellent.** Typed GameEventMap, error isolation per handler, re-entry depth limiting, `scopedBus` for automatic cleanup — this is production-quality pub/sub architecture. The re-entry guard at depth 8 is a particularly thoughtful detail.

2. **Dialogue tree system is clean and functional.** The purely functional `DialogueState` passed through options, `condition` predicates for branching visibility, `onSelect` side-effects — this is a well-designed tree walker. The `createDialogueState()` fresh-state factory is correct.

3. **Rush's actual dialogue is genuinely good.** The lime explanation node is scientifically accurate and sounds like Rush. "The planet's sensors show silicate desert — limestone, chalk formations, calcium carbonate. Any of it will do." is good writing. The urgency escalation across branches is well-paced.

4. **Stargate animation FSM is well-structured.** The five-state machine (idle → dialing → kawoosh → active → shutdown) with dedicated update functions per state, and the performance optimization (material updates every 3rd frame during active wormhole) is thoughtful game code.

5. **The quest manager auto-wiring is a smart design.** Subscribing to `resource:collected` and `ship:subsystem:repaired` at QuestManager creation time, then routing them to objectives by `targetId`, means scenes don't have to manually advance collect/repair objectives — they just emit the event and the manager handles it.

6. **Camera arm pull-in instead of wall transparency.** Raycasting from player to desired camera position and smoothly interpolating the camera arm length is the right way to handle camera occlusion. The pull-fast/recover-slow asymmetry is a good UX decision.

7. **Save manager's slot system with index.** Keeping a lightweight slot metadata index separate from full save blobs (for fast UI listing) is a thoughtful storage architecture. The F5 shortcut wiring and autosave-on-objective-complete hooks are solid.

8. **`scopedBus` pattern is excellent.** The scoped event bus that auto-unsubscribes on `cleanup()` prevents the entire category of "forgot to unsubscribe" memory leaks. Every scene using this correctly is a genuine engineering win.

---

## Prioritized Fix List

1. **Fix BUG-001 (lime flag not saved):** Add `limeCollected` to `SaveData`, serialize/deserialize in save-manager. Five-minute fix, blocks a guaranteed soft-lock.

2. **Fix BUG-002 (unguarded desert return):** Block E-key gate return if `collectedCount < totalDeposits` with an explicit message. Prevents the primary soft-lock path.

3. **Fix BUG-004 (visual test fake IDs):** Update test dialogue IDs to match real tree (`"dr-rush"`, `"greeting"`). Fix test 5 to actually drive game state, not DOM injection.

4. **Fix BUG-003 (GPU memory leak):** Implement geometry/material disposal in all three scenes' `dispose()`. Track GPU objects in an explicit array during mount.

5. **Fix BUG-005 (dialogue hang on all-hidden options):** Change terminal-node check from `options.length === 0` to `visible.length === 0` in `advance()`.

6. **Add player position restore to save/load:** Apply `data.playerPosition` after `gotoScene()` in save-manager `load()`.

7. **Add waypoint marker for scrubber entrance:** Show a blinking floor indicator at `SCRUBBER_ENTRANCE_POS` when `isLimeCollected()` is true.

8. **Make CO2 timer consequential:** Add a fail state at 0 seconds (return to gate room, crew incapacitated, optional "try again" flow). Even a 20-second grace period before fail is better than nothing.

9. **Replace magic strings with shared constants:** Extract `RESOURCE_CALCIUM`, `SUBSYSTEM_CO2`, `NPC_DR_RUSH`, `SCENE_*` constants to a shared file.

10. **Fix ARCH-002 (quest manager fragility):** Move quest state into the saved game data properly and deserialize it into scene-local managers on mount, rather than replaying fake `advanceObjective` calls.

---

## Dream Features
(After all the above is fixed — ranked by experiential impact)

1. **Enforced CO2 timer with graceful fail state.** 20-minute countdown. At zero: atmosphere critical cutscene, Rush appears (or voice-over), "You were too slow — people are unconscious. The gate closed. Everyone on Destiny is incapacitated." Optional retry from last save. This alone makes the game a genuine SGU experience.

2. **Rush follows you during the crisis.** He trails you from console to gate, talking urgency. Uses the existing NPC FSM — give him a 3-point patrol: console → gate approach → back. He reacts if you take too long. This costs patrol path data + 2 dialogue nodes.

3. **The kawoosh kills you if you're too close.** When the wormhole erupts during activation, player within 1.5m takes damage or gets knocked back. Forces engagement with the gate as a dangerous artifact, not just a loading screen.

4. **Kino footage replay in the gate room.** Pick up a Kino that shows recorded footage of the prior Icarus Base evacuation. Use `canvas` + timeline scrubbing. Sets context for players who don't know the show.

5. **Rush reacts to Eli's choices in real time.** The `affinityDelta` system is already wired. Make Rush's facial expression (when VRM is live) actually change: skeptical clench vs guarded acknowledgement based on accumulated affinity. The infrastructure exists — use it.

6. **Inventory UI for calcium deposits.** 3 deposit slots in the HUD. As each one is collected, a slot fills with a chalk-white mineral icon. Visual, tactile, clear. Replace the `Calcium deposits: 0 / 3` text.

7. **Gate room atmosphere: audible Destiny hull groaning.** SGU's defining sound design was the ship sounds — creaks, distant FTL hum, air recycler noise. Add `AudioManager` to the gate room with a looping ambient track. The system is already wired (`src/systems/audio/`).

8. **Destiny power fluctuation mechanic.** `ShipState` already has `powerLevel` and `SHIP_STATE_CONFIG`. Make the gate room lighting flicker during the CO2 crisis — dim, emergency red, partial panel failures. Power is what makes SGU's Destiny feel alive. The lighting dynamic system (`updateRoomLighting`) already exists; just hook it to a deteriorating power level during the crisis.

9. **Rush's memory — he references choices made in earlier conversations.** "You asked about the timeline before. Good. Then you already know we're out of time." The `hasMetNpc()` and `getAffinity()` APIs already exist in the dialogue manager. Use them.

10. **The gate CLOSES while you're on the planet.** Mid-mission, the wormhole drops (Destiny moved out of range). Panic. You have to re-establish the address and dial from the planet side to get back. The GateRuntime FSM on the desert-planet side only has `active → closing → closed` — extend it with re-dialing. This would be the most distinctively SGU mechanic in the game.
