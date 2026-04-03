# VRM Character Model Integration

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-04-03
> **Implements Pillar**: Pillar 1 (The Ship IS the World), Pillar 4 (Your Choices, Your Destiny)

---

## Overview

The VRM Character Model system replaces the placeholder capsule mesh with fully
rigged, expressive 3D character models for the player (Eli Wallace) and crew NPCs
aboard Destiny. VRM is a humanoid avatar format built on glTF 2.0 that provides
standardized bone mapping, spring bone physics (hair, cloth, accessories), blend
shape groups (facial expressions, lip sync visemes), and first-person rendering
annotations. Models load via `@pixiv/three-vrm` on top of the existing Three.js
`GLTFLoader`, then bridge into the ggez animation pipeline through a skeleton
retargeting layer that maps VRM's humanoid bone names to ggez `RigDefinition`
joints. The physics capsule body remains the source of truth for collision and
movement; the VRM mesh is a visual-only representation parented to the player
controller's scene `Group`. Crew NPCs share the same loading and animation
infrastructure but are driven by the Crew AI & Schedule system and the Crew
Dialogue & Choice system rather than player input.

---

## Player Fantasy

Eli Wallace's physical presence on Destiny is the most persistent visual element
in the game. His character model must serve the same arc described in the Player
Controller GDD: a transformation from overwhelmed outsider to confident owner of
every corridor.

**Early game (Season 1)**: Eli's VRM uses a **restrained expression set** — mostly
neutral, with occasional flickers of worry or surprise. His idle animation carries
subtle weight-shifting that reads as uncertainty. Hair and clothing spring bones
move loosely, suggesting someone who hasn't quite settled in. When crew members
speak to him, his expression responses are delayed and muted — he's processing,
not reacting. The player sees a character who doesn't yet belong here, and that
visual dissonance with the Ancient architecture around him reinforces the fantasy
of being stranded.

**Mid game (Season 2)**: Eli's expression range opens up. Confident smiles, focused
determination, sharper emotional reactions during dialogue. His idle animation
shifts to a more grounded, centered stance. Spring bones on accessories (an Ancient
device clipped to his belt, a modified tool on his vest) tell the story of someone
who has been improvising and building. Crew NPCs react to Eli with expressions
that match — Rush's grudging respect, Young's growing trust, Chloe's warmth.

**Late game (Season 3+)**: Eli moves and emotes like someone who owns this ship.
Full expression range, decisive body language, authoritative idle pose. His VRM
may gain cosmetic changes (rolled-up sleeves, Ancient tech woven into his outfit)
that reflect his journey. The crew around him are a team, and their expression
profiles during dialogue reflect established relationships rather than first
impressions.

**Crew as world-building**: Every crew member visible in Destiny's corridors makes
the ship feel alive. Rush hunched over a console, TJ checking supplies in the
infirmary, Greer standing guard at a junction — each VRM with distinct silhouette,
posture, and idle behavior. The VRM system serves **Pillar 1 (The Ship IS the
World)** by populating Destiny with characters whose visual presence tells stories
even when no dialogue is playing.

---

## Detailed Rules

### VRM Loading Pipeline

1. **File format**: All character models use VRM 1.0 format (`.vrm` extension,
   internally glTF 2.0 with VRM extensions).
2. **Loader chain**: `GLTFLoader` → `@pixiv/three-vrm` VRM parser → `VRM` instance
   containing scene graph, humanoid bone mapping, spring bones, expressions, and
   first-person settings.
3. **Skeleton extraction**: The VRM humanoid provides a standardized bone hierarchy.
   A retargeting bridge maps VRM bone names (`hips`, `spine`, `chest`, `head`,
   `leftUpperArm`, etc.) to ggez `RigDefinition` joint names. This mapping is
   defined once in a static bone mapping table (`vrm-bone-map.ts`).
4. **Animation binding**: After retargeting, ggez animation clips (authored in the
   ggez animation editor) drive the VRM skeleton through the standard
   `RuntimeAnimationBundle` pipeline. Clips reference ggez joint names; the
   retarget layer resolves them to VRM bones at bind time.
5. **Loading queue**: Maximum 2 VRM files load concurrently to avoid frame drops.
   Additional requests are queued. Priority: player model first, then visible
   crew sorted by distance to camera.

### Player Model (Eli Wallace)

1. **Visual attachment**: The VRM scene graph replaces the capsule `Mesh` inside
   `StarterPlayerController.object` (the `Group`). The Crashcat rigid body
   capsule remains unchanged — physics and visuals are decoupled.
2. **Locomotion states**: The ggez animation graph for the player defines these
   states, each mapped to authored animation clips:
   - `idle` — breathing, subtle weight shift
   - `walk` — casual walk cycle, speed-matched to controller walk speed
   - `run` — sprint cycle, speed-matched to controller sprint speed (1.8× walk)
   - `jump-start` — launch into air
   - `jump-loop` — airborne hold
   - `jump-land` — landing recovery
   - `interact` — reach forward (contextual interaction)
   - `traverse-squeeze` — squeeze through narrow gap
   - `traverse-duck` — duck under obstacle
   - `traverse-climb` — climb over obstacle
3. **State transitions**: Driven by player controller movement state and grounded
   status. Walk/run blend uses movement speed as the blend parameter. Jump states
   use grounded flag transitions. Traversal states are triggered by interaction
   events.
4. **Root motion**: Disabled. Movement is entirely physics-driven by the Crashcat
   rigid body. The animation plays in-place on the VRM skeleton.

### Crew NPC Models

1. **Character roster**: Each major crew member has a unique VRM file:
   - Nicholas Rush, Everett Young, Chloe Armstrong, Matthew Scott,
     Ronald Greer, Tamara Johansen (TJ), Camile Wray, Eli Wallace (NPC variant
     for cutscenes where player observes Eli)
2. **Animation states**: Crew VRMs use a simpler animation graph:
   - `idle-standing` — default, character-specific idle
   - `idle-sitting` — seated variant (console, mess hall)
   - `idle-working` — task-specific (repairing, typing, examining)
   - `walk` — corridor movement
   - `talk` — conversation body language (gestures, head turns)
3. **Visibility budget**: Maximum **4 crew VRMs** rendered simultaneously. The Crew
   AI system decides which crew are in the player's current section. If more than 4
   are logically present, the furthest from camera are culled (hidden, not unloaded).
4. **Loading strategy**: Crew VRMs for the current ship section are preloaded during
   scene mount. VRMs for adjacent sections begin loading when the player enters a
   transition zone (within 10m of a door).

### Spring Bone Physics

1. **Scope**: Hair, cloth, dangling accessories, loose clothing elements. Each VRM
   defines its own spring bone chains in the VRM file metadata.
2. **Update frequency**: Spring bones update once per frame in the `update()` call,
   after animation pose is applied but before rendering.
3. **Performance budget**: Total spring bone simulation must complete within **1ms**
   per frame across all visible VRMs.
4. **LOD integration**: Spring bones are disabled for characters beyond the near LOD
   threshold (> 5m from camera). Bones snap to their rest pose when disabled.
5. **Collision**: Spring bone colliders (defined in VRM metadata) use simple
   sphere/capsule shapes against the character's own body — no interaction with
   world geometry.

### Expression / Blend Shape System

1. **VRM expression presets**: Each VRM defines blend shape groups for standard
   expressions: `happy`, `angry`, `sad`, `surprised`, `neutral`, `relaxed`.
2. **Custom expressions**: Characters may define additional expressions:
   `thinking`, `determined`, `worried`, `smirk` (character-specific).
3. **Visemes**: Lip sync blend shapes for dialogue: `aa`, `ih`, `ou`, `ee`, `oh`,
   `silence`. Driven by dialogue audio analysis or text-timing data from the
   Crew Dialogue system.
4. **Blending**: Expressions crossfade over a configurable duration (default 0.3s).
   Visemes overlay on top of the base expression with additive blending.
5. **Dialogue integration**: The Crew Dialogue & Choice system emits events
   (`dialogue:expression:change`, `dialogue:viseme:update`) that the VRM
   expression controller listens to. Expression presets are authored per dialogue
   line in the dialogue data files.
6. **Distance falloff**: Expressions are only evaluated for VRMs within the near
   LOD threshold (< 5m). Beyond that, characters hold a neutral expression to
   save blend shape computation.

### First-Person Rendering

1. **Head mesh hiding**: When camera mode is `fps`, the player VRM uses its
   `firstPerson` annotations to hide head, hair, and face meshes. This prevents
   the camera from clipping into the player's own head geometry.
2. **Transition**: When switching between FPS and third-person modes, head mesh
   visibility transitions over **0.15 seconds** using opacity fade (not instant
   pop) to avoid visual jarring.
3. **Crew VRMs**: First-person settings are ignored for crew NPCs — they always
   render fully.

### Level of Detail (LOD)

1. **Near (< 5m from camera)**:
   - Full mesh resolution
   - Spring bones active
   - Expressions active
   - All blend shapes evaluated
2. **Mid (5–15m from camera)**:
   - Full mesh resolution
   - Spring bones disabled (rest pose)
   - Expressions disabled (neutral face)
   - Reduced draw call batching
3. **Far (> 15m from camera)**:
   - Simplified mesh (lower polygon count, defined as secondary mesh in VRM or
     generated at load time via mesh decimation)
   - No spring bones, no expressions
   - Single material pass
4. **LOD transitions**: Crossfade over 0.5 seconds using opacity blending to
   avoid popping artifacts.

---

## Formulas

### Spring Bone Frame Cost

```
springBoneMs = numActiveChains * avgBonesPerChain * COST_PER_BONE
```

Where:
- `numActiveChains` = total spring bone chains on all visible near-LOD VRMs
- `avgBonesPerChain` = average bones per chain (typically 3–6)
- `COST_PER_BONE` ≈ 0.004ms (empirical, single-threaded JS)

**Budget constraint**: `springBoneMs < 1.0ms`
**Max active bones**: ~250 spring bones across all visible characters

### Expression Blend Weight

```
finalWeight = targetWeight * smoothstep(t / blendDuration)
visemeWeight = visemeTargetWeight * visemeSmooth(t)
combinedWeight = clamp(finalWeight + visemeWeight, 0, 1)
```

Where:
- `targetWeight` = expression intensity from dialogue data (0–1)
- `blendDuration` = configurable, default 0.3s
- `visemeTargetWeight` = lip sync weight from audio analysis (0–1)
- `smoothstep(x)` = 3x² − 2x³

### LOD Distance Thresholds

```
lodLevel = camera.distanceTo(vrm.position) < LOD_NEAR ? "near"
         : camera.distanceTo(vrm.position) < LOD_MID  ? "mid"
         : "far"
```

Where:
- `LOD_NEAR` = 5.0 (configurable)
- `LOD_MID` = 15.0 (configurable)

### VRM File Size Budget

```
targetFileSize = baseMeshKB + textureKB + springBoneDataKB
```

Where:
- `baseMeshKB` ≈ 800–1500 KB (8k–15k triangles per character)
- `textureKB` ≈ 1000–3000 KB (diffuse + normal + emission, 1024² max)
- `springBoneDataKB` ≈ 5–20 KB

**Target per character**: 2–5 MB uncompressed `.vrm`

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| **VRM file fails to load** (network error, corrupt file) | Fall back to capsule placeholder mesh. Log warning. Retry once after 2 seconds. If retry fails, remain on capsule for the session. |
| **VRM missing expected bones** | Log warning listing missing bones. Use bind pose for missing joints. Animation clips that reference missing bones are silently skipped for those joints. |
| **Multiple VRMs loading during scene transition** | Loading queue enforces max 2 concurrent loads. Player model always has priority slot 1. Crew models share slot 2 in distance-sorted order. |
| **Camera mode switch mid-animation** | Head mesh visibility transitions over 0.15s via opacity. Spring bones and expressions continue unaffected. |
| **Spring bones during game pause** | Freeze spring bone simulation (skip update). On unpause, spring bones resume from frozen state — no snap or reset. |
| **Crew VRM enters near LOD while talking** | Expression system activates mid-blend. Start from neutral and blend to the current dialogue expression over standard blend duration. |
| **Player VRM not yet loaded at spawn** | Show capsule placeholder immediately. When VRM finishes loading, crossfade from capsule to VRM over 0.5s (capsule fades out, VRM fades in). |
| **Two crew share same VRM file** (e.g., background crew) | VRM loader caches parsed VRM data. Each instance clones the scene graph but shares geometry and texture GPU resources. |
| **VRM with MToon shader on WebGPU** | Convert MToon materials to PBR-equivalent at load time. Map MToon shade color → PBR roughness approximation. Preserve outline if performance allows, otherwise disable. |
| **Device runs below 30 FPS with VRMs** | Adaptive quality: disable spring bones globally, reduce max visible crew to 2, force all VRMs to mid-LOD. |

---

## Dependencies

| Dependency | Type | Purpose |
|------------|------|---------|
| `@pixiv/three-vrm` | New npm package | VRM file parsing, spring bones, expressions, first-person |
| ggez Animation Pipeline (`@ggez/anim-*`) | Existing | Skeleton retargeting, animation clip playback, animation graphs |
| Player Controller (`src/game/starter-player-controller.ts`) | Existing | Visual attachment point (`object` Group), movement state for animation |
| Camera System (`design/gdd/camera-system.md`) | Existing | Camera mode (FPS/third-person) for head hiding, distance for LOD |
| Crew Dialogue & Choice System (`design/gdd/crew-dialogue-choice.md`) | Existing | Expression triggers, viseme events during dialogue |
| Crew AI & Schedule System | Future (VS tier) | Crew placement, visibility decisions, animation state triggers |
| Event Bus (`design/gdd/event-bus.md`) | Existing | Expression change events, VRM load status events |
| Ship Exploration System (`design/gdd/ship-exploration.md`) | Existing | Section awareness for crew preloading |

---

## Tuning Knobs

| Parameter | Type | Default | Range | Description |
|-----------|------|---------|-------|-------------|
| `maxVisibleCrew` | integer | 4 | 1–8 | Maximum crew VRMs rendered simultaneously |
| `springBoneEnabled` | boolean | true | — | Global toggle for spring bone simulation |
| `springBoneStiffness` | float | 1.0 | 0.1–5.0 | Global stiffness multiplier applied to all spring bones |
| `springBoneDamping` | float | 0.4 | 0.0–1.0 | Global damping multiplier for spring bone oscillation |
| `expressionBlendSpeed` | float | 0.3 | 0.05–1.0 | Seconds to crossfade between expressions |
| `visemeBlendSpeed` | float | 0.08 | 0.02–0.2 | Seconds to blend between viseme shapes |
| `lodNearDistance` | float | 5.0 | 2.0–10.0 | Distance threshold for near LOD (meters) |
| `lodMidDistance` | float | 15.0 | 8.0–25.0 | Distance threshold for mid LOD (meters) |
| `lodTransitionDuration` | float | 0.5 | 0.1–1.0 | LOD crossfade duration (seconds) |
| `maxConcurrentLoads` | integer | 2 | 1–4 | Maximum simultaneous VRM file loads |
| `headFadeTransition` | float | 0.15 | 0.05–0.5 | FPS head hide/show transition duration (seconds) |
| `adaptiveQualityThreshold` | float | 30.0 | 20.0–50.0 | FPS threshold that triggers adaptive quality reduction |
| `meshTriangleBudget` | integer | 15000 | 5000–30000 | Max triangles per character mesh |

All values are loaded from `assets/config/vrm-config.json` at startup and can be
hot-reloaded during development.

---

## Acceptance Criteria

- [ ] A `.vrm` file loads successfully and renders a character model in place of
      the blue capsule mesh
- [ ] Player VRM plays idle, walk, and run animations driven by controller
      movement state (speed-matched blending)
- [ ] VRM head mesh hides when camera mode switches to FPS, with smooth 0.15s
      opacity transition
- [ ] Spring bones simulate on hair and cloth elements with total frame cost
      < 1ms across all visible characters
- [ ] Facial expressions change during dialogue sequences, driven by dialogue
      system events
- [ ] Viseme blend shapes animate during dialogue audio playback
- [ ] At least 2 crew NPCs render with unique VRM models in a ship scene
- [ ] Fallback to capsule placeholder works gracefully when a VRM file is missing
      or fails to load
- [ ] 60 FPS maintained with player + 4 crew VRMs on screen (near LOD) on target
      hardware
- [ ] LOD transitions work correctly: spring bones and expressions disable at
      mid/far distances
- [ ] Adaptive quality kicks in below 30 FPS, reducing spring bones and crew count
- [ ] VRM bone mapping retargets correctly to ggez animation clips without visual
      artifacts
- [ ] All tuning knobs are externalized in `vrm-config.json` (no hardcoded values)
