# Observation Room — Rush Intro

> **Status**: Designed — ready for implementation
> **Author**: Plan agent + Claude
> **Last Updated**: 2026-04-15
> **Blocker**: None. Three open decisions resolved (new scene / Chloe+Greer / Yes quest)

## Overview

After the opening cinematic and Scott's dialogue, Rush is NOT in the gate room. Chloe + Greer (civilian + military survivor pairing) stand where Rush used to be. They direct the player to the observation room via a new forward doorway. Rush is inside, silhouetted against the big Destiny forward window.

## Decisions

| Question | Choice | Rationale |
|---|---|---|
| New scene vs alcove | **New scene** (`src/scenes/observation-room/`) | Gate-room `index.ts` is already 2,700+ lines. Scene transition plumbing is well-established (`gotoScene`) — cheaper than growing gate-room. |
| Which two scientists | **Chloe + Greer** | Both have VRMs in manifest. Chloe (civilian) + Greer (military) = natural "survivor pair" mirroring the show. TJ is canonically with wounded Young, shouldn't be free-standing. |
| Quest log entry | **Yes — "Find Rush"** with two objectives (`ask-crew`, `find-rush-observation`). | Matches existing `air-crisis` quest pattern. Cheap. Auto-completes on skip-path. |

## Player Flow

1. Cinematic ends → Scott's dialogue → "Rush went off toward the observation deck — forward of the ship."
2. Quest `find-rush` starts, objective `ask-crew` active.
3. Player sees Chloe + Greer near the left-side consoles (Rush's former spot).
4. Player talks to either → "Rush? He went through there — the observation room, forward of the gate room."
5. Objective `ask-crew` completes → `find-rush-observation` activates.
6. Player walks to front-wall doorway. New interact trigger: "Go to the Observation Room."
7. `gotoScene("observation-room")` fires.
8. Player spawns in observation room. Rush at far end facing the window.
9. Player interacts with Rush → existing CO2-crisis dialogue plays.
10. `find-rush-observation` completes → quest done. Existing `air-crisis` `speak-to-rush` objective advances as before.
11. Back-doorway returns to gate room.

**Fallback:** player finds door first → `ask-crew` auto-advances when `find-rush-observation` completes. Talking to scientists afterward is just flavor.

## Scene Spec — `observation-room`

- **Geometry**: 20m W × 14m D × 5m H. Forward (-Z) wall is a 12m × 4m emissive transparent window showing starfield/nebula. Two small consoles flank the window. Side/back walls match gate-room Ancient metal (`0x1a1a2e`).
- **Lighting**: dim blue-grey hemisphere (`0.3` intensity), faint blue emissive from window, two soft point lights on consoles.
- **Audio**: Low Destiny ship hum (reuse existing drone).
- **Rush spawn**: `(0, 0, -4)` facing -Z (window).
- **Player spawn**: `(0, 0.5, 5)` facing -Z.
- **Back door**: +Z wall, returns to gate-room.

### Approximate `scene.runtime.json` structure

```json
{
  "metadata": { "format": "web-hammer-engine", "version": 6 },
  "entities": [
    { "id": "entity:player-spawn:observation-room", "type": "player-spawn",
      "transform": { "position": { "x": 0, "y": 0.5, "z": 5 },
                     "rotation": { "x": 0, "y": 3.14159, "z": 0 } } }
  ],
  "nodes": [
    { "id": "node:obs:floor", "kind": "primitive",
      "data": { "shape": "cube", "size": { "x": 20, "y": 1, "z": 14 },
                "physics": { "bodyType": "fixed", "colliderShape": "trimesh" } } },
    { "id": "node:obs:light:hemisphere", "kind": "light",
      "data": { "type": "hemisphere", "color": "#1a1a3a",
                "groundColor": "#0a0a15", "intensity": 0.3 } }
  ],
  "settings": {
    "player": { "cameraMode": "third-person", "movementSpeed": 4.0 },
    "world": { "fogColor": "#050510", "fogNear": 12, "fogFar": 25,
               "physicsEnabled": true }
  }
}
```

## Characters

| Character | Scene | Position | VRM ID | Facing |
|---|---|---|---|---|
| Chloe Armstrong | gate-room | `(-18, 0, 44)` | `chloe` | +X |
| Ron Greer | gate-room | `(-18, 0, 52)` | `greer` | +X |
| Dr. Rush | observation-room | `(0, 0, -4)` | `rush` | -Z |

## Dialogue Changes

- **New** `src/dialogues/scientists-gateroom.ts` — shared tree used by Chloe + Greer. 2 nodes: greeting → "observation room" directions → exit. Advances `ask-crew` on dialogue end.
- **New** `src/dialogues/dr-rush-observation.ts` (or modify `dr-rush.ts`) — preamble acknowledging the FTL/window context, then chains into existing CO2-crisis tree.
- **Modify** `src/dialogues/scott-opening.ts` line ~112 — change `"Find Rush — he's by the main console."` to `"Find Rush — he headed toward the observation room, forward of the gate room."`

## Quest — `find-rush`

```typescript
{
  id: 'find-rush',
  name: 'Find Dr. Rush',
  description: 'Dr. Rush left the gate room. Find him.',
  type: 'main',
  giverNpcId: 'scott-opening',
  objectives: [
    { id: 'ask-crew', type: 'talk',
      description: 'Ask the crew where Rush went.',
      targetId: 'scientists-gateroom', required: 1, current: 0,
      completed: false, visible: true },
    { id: 'find-rush-observation', type: 'reach',
      description: 'Find Rush in the observation room.',
      targetId: 'observation-room', required: 1, current: 0,
      completed: false, visible: false, unlockedBy: 'ask-crew' },
  ],
  reward: { type: 'multiple', xp: 50 },
}
```

## Implementation Plan (ordered)

1. `src/scenes/observation-room/scene.runtime.json` — new. Copy scrubber-room structure.
2. `src/scenes/observation-room/index.ts` — new (~200 LOC). `defineGameScene` with id `observation-room`. Builds room geometry, forward window, consoles, Rush VRM load at `(0, 0, -4)`. Back door → `gotoScene("gate-room")`.
3. `src/npcs/dr-rush-observation.ts` — new NPC def for Rush in observation room.
4. `src/npcs/chloe-gateroom.ts` — new NPC def.
5. `src/npcs/greer-gateroom.ts` — new NPC def.
6. `src/dialogues/scientists-gateroom.ts` — new dialogue tree.
7. `src/dialogues/dr-rush-observation.ts` — new (or modify `dr-rush.ts` greeting text).
8. `src/quests/find-rush/` — new quest definition.
9. `src/scenes/gate-room/index.ts` — surgical edits:
   - Remove `import { drRushNpc }` + its registration (~line 15, 1791)
   - Remove Rush VRM loading block (~lines 1849-1863)
   - Remove Rush dot indicator (~lines 1802-1809)
   - Add imports for new scientists NPCs + dialogue + quest
   - Register Chloe + Greer + their dialogue tree
   - Load Chloe + Greer VRMs at `(-18, 0, 44)` + `(-18, 0, 52)`
   - Add front-wall observation-room doorway trigger (mirror scrubber-entrance pattern, no quest gate)
   - Wire `find-rush` quest start after Scott's opening dialogue ends
   - Remove `rushCharacter` references from cinematic hide/show (~lines 1876, 2268-2286)
10. `src/dialogues/scott-opening.ts` — update line 112.

## Test Plan

| Beat | URL / verify |
|---|---|
| Gate room loads without Rush | `/?scene=gate-room` — no Rush at `(-20, 0, 48)` |
| Scientists visible | Same — see Chloe + Greer at `(-18, 0, 48)` area |
| Scientist dialogue | Talk → "observation room" text |
| Door prompt | Walk to front doorway → "Go to Observation Room" appears |
| Transition | Press E → scene switches |
| Rush at window | Observation room loads → Rush VRM at `z=-4` facing window |
| Rush dialogue | Press E near Rush → CO2 crisis dialogue |
| Quest tracking | Quest log shows "Find Rush" with objectives updating |
| Return | Back door → gate-room |
| Skip path | Go to observation directly without scientists — still works |
| Cinematic path | New game → cinematic → Scott says "observation room" |

No `skipCinematic` URL param exists. Cinematic gate: `sessionStorage.getItem("sgu-new-game")`. Loading `/?scene=gate-room` directly bypasses it.

## Risks & Unknowns

- **Biggest**: the cinematic's `rushCharacter` (ragdoll-thrown in cinematic + separately-loaded gameplay VRM). Removing the gameplay-VRM load (step 9) should suffice, but the cinematic-spawned Rush body may remain visible on the floor. Verify cleanup in cinematic completion callback.
- `air-crisis` quest's `giverNpcId: 'dr-rush'` — cosmetic ref in quest log tooltip, should still work since we're keeping Rush NPC id stable.
- No existing always-available doorway trigger (scrubber-room needs lime). The observation-room door is a new unconditional-trigger pattern — straightforward but novel.

## Formulas

_(None — no numeric tuning. Positions and dimensions only.)_

## Edge Cases

- **Player walks to observation door during Scott's opening dialogue** — door trigger disabled until Scott's dialogue ends.
- **Player talks to Chloe then Greer (or vice versa)** — objective `ask-crew` advances once on first dialogue end; second conversation plays normally for flavor but doesn't double-advance.
- **Player interrupts Rush's CO2 dialogue then re-enters** — dialogue resumes from last unanswered node per existing dialogue-manager behavior.
- **Scene exit while in observation** — back-door press saves scene state via existing scene-manager conventions; next visit respawns at player-spawn.

## Dependencies

- **Upstream**: `@ggez/runtime-format` (scene JSON schema), `@ggez/gameplay-runtime` (scene manager), `@ggez/runtime-physics-crashcat` (floor collider).
- **Downstream**: Future sprint-3 dialogue will reference "the observation room" as a familiar place — this scene becomes the anchor.

## Tuning Knobs

- Room dimensions (`20 × 14 × 5`) — safe range 15-25 wide, 10-20 deep, 4-6 tall. Smaller = claustrophobic; larger = spatially empty.
- Window emissive intensity — safe range 0.2-0.8. Too high = washes out Rush silhouette.
- Fog near/far (`12/25`) — gates visibility through the window. Far < 20 = stars don't read.

## Acceptance Criteria

1. `/?scene=gate-room` shows Chloe + Greer, no Rush NPC, no Rush blue dot.
2. Talking to either scientist opens dialogue referencing "observation room" and completes `ask-crew` objective.
3. Front-wall doorway interact prompt appears within 3m of the door.
4. Pressing E at door transitions to observation-room scene within 2 seconds.
5. Rush is visible at scene load at `(0, 0, -4)` facing the window.
6. Talking to Rush triggers existing CO2-crisis dialogue and advances `air-crisis` quest's `speak-to-rush`.
7. Back-door returns to gate room, player spawns at gate-room-back position.
8. Opening cinematic's "Find Rush" line says "observation room" not "main console."
9. Quest log shows "Find Rush" quest with two objectives and correct completion states.
