# Systems Index: Stargate Universe — The Destiny Mission

> **⚠️ Engine mapping updated — Three.js web era (2026-09-08 re-pivot)**
>
> The former engine-provided foundation section has been replaced with the
> Three.js foundation layer. The system catalog below has been audited
> against the actual `src/*.js` codebase — 16 of 19 systems are implemented.

> **Status**: Updated — implementation audit 2026-10-12
> **Created**: 2026-03-29
> **Last Updated**: 2026-10-12 (implementation audit: 16/19 systems implemented)
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

Stargate Universe is a third-person exploration-survival game aboard the Ancient
ship Destiny. The systems divide into two domains: **ship systems** (exploring,
repairing, and managing Destiny) and **planetary systems** (gating to worlds for
time-limited supply runs). A narrative layer drives the story through episodes,
crew relationships, and player choices. The Three.js engine provides scene
management, physics, animation, and the render pipeline — all custom
systems build on top of this foundation.

The game pillars that constrain system design:
- **The Ship IS the World** — Ship State is the bottleneck system; everything reads it
- **Survival with Purpose** — Resources serve story, not grind
- **Earned Discovery** — No hand-holding UI; Kino Remote is diegetic
- **Your Choices, Your Destiny** — Dialogue and Episode systems must support branching

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Code | Depends On |
|---|-------------|----------|----------|--------|------------|------|------------|
| 1 | Event Bus | Core | MVP | Implemented | design/gdd/event-bus.md | Quest triggers + main.js event wiring | (none — foundation) |
| 2 | Player Controller (third-person) | Core | MVP | Implemented | design/gdd/player-controller.md | src/player.js | Three.js render loop, custom physics (src/*.js) |
| 3 | Camera System (third-person) | Core | MVP | Implemented | design/gdd/camera-system.md | src/main.js (camera rig) | Player Controller |
| 4 | Ship State System | Gameplay | MVP | Implemented | design/gdd/ship-state-system.md | src/ship.js | Event Bus, Save/Load (interface) |
| 5 | Ship Exploration System | Gameplay | MVP | Implemented | design/gdd/ship-exploration.md | src/ship.js, src/gate-room.js | Player Controller, Camera, Ship State, Three.js scene mgmt |
| 6 | Resource & Inventory System | Economy | MVP | Implemented | design/gdd/resource-inventory.md | src/rpg.js | Event Bus, Save/Load (interface) |
| 7 | Timer & Pressure System | Gameplay | MVP | Implemented | design/gdd/timer-pressure-system.md | src/ftl.js (createFtlSystem), src/main.js (wiring) | Event Bus |
| 8 | Stargate & Planetary Runs | Gameplay | MVP | Implemented | design/gdd/stargate-planetary-runs.md | src/stargate.js, src/destination.js | Player Controller, Camera, Timer, Three.js scene mgmt, Resource System |
| 9 | Crew Dialogue & Choice System | Narrative | MVP | Implemented | design/gdd/crew-dialogue-choice.md | src/ui.js (subtitle), data/characters.json | Event Bus, Save/Load (interface) |
| 10 | Kino Remote (diegetic menu) | UI | MVP | Implemented | design/gdd/kino-remote.md | src/ui.js (Kino Remote tabs) | Ship State, Resource System, Three.js scene mgmt |
| 11 | Ship Atmosphere & Lighting | Audio/Visual | MVP | Implemented | design/gdd/ship-atmosphere-lighting.md | src/ancient.js, src/ship.js (nearest-6 lights) | Ship State, Three.js materials/lighting |
| 12 | Save/Load System | Persistence | Vertical Slice | Implemented | — | src/save.js (createSaveSystem, 22 unit tests) | Event Bus |
| 13 | Ancient Tech Puzzle System | Gameplay | Vertical Slice | Implemented | — | src/hotwire.js, src/flow.js | Player Controller, Ship State |
| 14 | Crew AI & Schedule System | Gameplay | Vertical Slice | Partial | — | src/autoplay.js (NPC movement only) | Ship State, Event Bus, Three.js scene mgmt |
| 15 | Kino Drone (first-person scout) | Gameplay | Vertical Slice | Implemented | — | src/kino.js | Camera System, Ship State, Player Controller |
| 16 | Episode Narrative System | Narrative | Vertical Slice | Implemented | — | src/quest.js, data/chapters.json | Dialogue System, Ship State, Timer, Event Bus |
| 17 | Audio & Ambience System | Audio/Visual | Vertical Slice | Implemented | — | src/music.js | Ship State, Event Bus, Three.js scene mgmt |
| 18 | Tutorial / Onboarding (Icarus Base) | Meta | Alpha | Partial | — | data/chapters.json (story progression) | All MVP + VS gameplay systems |
| 19 | VRM Character Models | Audio/Visual | Vertical Slice | Designed | design/gdd/vrm-model-integration.md | — | Player Controller, Camera, Crew Dialogue, Three.js animation pipeline |

---

## Categories

| Category | Description | Systems |
|----------|-------------|---------|
| **Core** | Player-facing foundation systems | Player Controller, Camera, Event Bus |
| **Gameplay** | The systems that make the game fun | Ship Exploration, Stargate & Planetary Runs, Ancient Tech Puzzles, Ship State, Timer & Pressure, Crew AI, Kino Drone |
| **Economy** | Resource creation and consumption | Resource & Inventory |
| **Persistence** | Save state and continuity | Save/Load |
| **UI** | Player-facing information displays | Kino Remote |
| **Audio/Visual** | Atmosphere and immersion | Ship Atmosphere & Lighting, Audio & Ambience |
| **Narrative** | Story and dialogue delivery | Crew Dialogue & Choice, Episode Narrative |
| **Meta** | Systems outside the core game loop | Tutorial / Onboarding |

---

## Foundation Layer (provided by Three.js + src/*.js)

These systems are built into the Three.js engine and custom src/*.js modules, and do NOT require custom design
documents. They are configured, not designed:

| System | Package | Notes |
|--------|-------------|-------|
| Scene Management | Three.js `Scene` + custom loaders | Scene loading, preload, caching |
| Physics | Custom collision in src/*.js | Rigid bodies, collision, raycasting |
| Animation Pipeline | Three.js `AnimationMixer` + GLTFLoader | Skeletal animation playback |
| Render Pipeline | Three.js `WebGLRenderer` | PBR materials, instanced mesh |
| Gameplay Runtime Loop | Custom `requestAnimationFrame` loop | Fixed timestep update, system registration |

Custom systems register with the gameplay runtime via the main update loop
and receive `update(delta)` calls at 60 FPS.

---

## Priority Tiers

| Tier | Definition | Target Milestone | Systems Count |
|------|------------|------------------|---------------|
| **MVP** | Required for the core loop: walk Destiny, gate to planet, gather supplies, repair something, talk to crew | First playable prototype | 11 |
| **Vertical Slice** | Complete experience: episodes, puzzles, NPC schedules, kino scouting, save/load | Vertical slice / demo | 6 |
| **Alpha** | All features rough: Icarus Base tutorial, full episode structure | Alpha milestone | 1 |

---

## Dependency Map

### Foundation Layer (Three.js + src/*.js)

- Three.js Scene Management — loading/unloading environments
- Custom Physics (src/*.js) — collision, raycasting, rigid bodies
- Three.js Animation Pipeline — skeletal animation playback
- Three.js WebGLRenderer — PBR materials, rendering
- Custom Gameplay Runtime — update loop, system registration

### Core Layer (no custom dependencies)

1. **Event Bus** — Centralized pub/sub for all system communication
2. **Player Controller** — Third-person movement, interaction, Eli's character
3. **Camera System** — Third-person follow, cinematic cameras (depends on: Player Controller)

### Feature Layer (depends on core)

4. **Ship State System** — Power, life support, section access, repair tracking (depends on: Event Bus). **BOTTLENECK: 7+ systems depend on this.**
5. **Resource & Inventory System** — Supply tracking, crew needs (depends on: Event Bus)
6. **Timer & Pressure System** — Countdown timers, event scheduling (depends on: Event Bus)
7. **Ship Exploration System** — Corridor navigation, room scanning, doors (depends on: Player Controller, Camera, Ship State)
8. **Stargate & Planetary Runs** — Gate travel, planet environments, scavenging (depends on: Player Controller, Camera, Timer, Resources)
9. **Crew Dialogue & Choice System** — Conversations, relationships, branching (depends on: Event Bus)
10. **Ancient Tech Puzzle System** — Logic puzzles, console interaction (depends on: Player Controller, Ship State)
11. **Crew AI & Schedule System** — NPC placement, routines, reactions (depends on: Ship State, Event Bus)
12. **Kino Drone** — First-person pilotable scout (depends on: Camera, Ship State)
13. **Episode Narrative System** — Story progression, crisis triggers (depends on: Dialogue, Ship State, Timer, Event Bus)

### Presentation Layer (depends on features)

14. **Kino Remote** — Diegetic menu: map, status, inventory, objectives (depends on: Ship State, Resources, Episode System)
15. **Ship Atmosphere & Lighting** — Volumetric fog, dynamic lights, Ancient glow (depends on: Ship State)
16. **Audio & Ambience System** — Ship sounds, environmental audio, music (depends on: Ship State, Event Bus)
19. **VRM Character Models** — Player and crew VRM loading, spring bones, expressions, LOD (depends on: Player Controller, Camera, Crew Dialogue, Three.js Animation Pipeline)

### Polish Layer

17. **Tutorial / Onboarding** — Icarus Base evacuation sequence (depends on: all gameplay systems)
18. **Save/Load System** — Serialization of all game state. Note: other systems depend on a Save/Load *interface* (contract) but not the implementation. Design the interface early, implement in VS tier.

---

## Recommended Design Order

Combining dependency sort and priority tiers. Design these systems in this
order. Each system's GDD should be completed before starting the next,
though independent systems at the same layer can be designed in parallel.

| Order | System | Priority | Layer | Est. Effort |
|-------|--------|----------|-------|-------------|
| 1 | Event Bus | MVP | Core | S |
| 2 | Player Controller (third-person) | MVP | Core | M |
| 3 | Camera System (third-person) | MVP | Core | M |
| 4 | Ship State System | MVP | Feature | L |
| 5 | Ship Exploration System | MVP | Feature | M |
| 6 | Resource & Inventory System | MVP | Feature | S |
| 7 | Timer & Pressure System | MVP | Feature | S |
| 8 | Stargate & Planetary Runs | MVP | Feature | L |
| 9 | Crew Dialogue & Choice System | MVP | Feature | M |
| 10 | Kino Remote (diegetic menu) | MVP | Presentation | M |
| 11 | Ship Atmosphere & Lighting | MVP | Presentation | M |
| 12 | Save/Load System | VS | Core | M |
| 13 | Ancient Tech Puzzle System | VS | Feature | L |
| 14 | Crew AI & Schedule System | VS | Feature | M |
| 15 | Kino Drone (first-person scout) | VS | Feature | M |
| 16 | Episode Narrative System | VS | Feature | L |
| 17 | Audio & Ambience System | VS | Presentation | M |
| 18 | Tutorial / Onboarding (Icarus Base) | Alpha | Polish | M |

Effort estimates: S = 1 session, M = 2-3 sessions, L = 4+ sessions.

---

## Circular Dependencies

None found. The Save/Load System has a special note: many systems depend on a
Save/Load *interface* (serialization contract) but not the full implementation.
Resolution: define the ISaveableSystem interface in the Event Bus / Ship State
design phase. Implement the full Save/Load system in Vertical Slice tier.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| Ship State System | Design + Scope | Bottleneck system — its data model affects 7+ systems. Wrong abstractions here cascade everywhere. | Design this GDD with extreme care. Prototype the data model before building dependent systems. |
| Episode Narrative System | Scope | Branching narrative with player choices multiplies content. Each branch needs writing, testing, and state tracking. | Start with linear episodes (S1), add branching in later seasons. Define a branching budget per episode. |
| Stargate & Planetary Runs | Technical | Each planet is a unique scene with its own environment, hazards, and resources. Content pipeline for 30+ planets is the biggest production risk. | Develop a planet template system. Use modular, recombinable elements. AI-assisted asset generation. |
| Ship Atmosphere & Lighting | Technical | Volumetric fog and dynamic lighting in WebGPU need careful performance tuning. Destiny has long corridor views. | Prototype early. Budget 4ms of frame time for atmosphere. Use baked lighting where possible. |
| Ancient Tech Puzzles | Design | Puzzles must feel like "decoding alien technology," not generic game puzzles. Hard to design well. | Research reference games (Outer Wilds, The Witness). Prototype 3 puzzle types before committing. |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 19 |
| Design docs started | 12 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| MVP systems designed | 11/11 |
| Vertical Slice systems designed | 1/6 |
| Systems implemented (code) | 16/19 |
| Systems with unit tests | 9 test files, 169 tests passing |

### Implementation Status (2026-10-12 audit)

| Status | Systems |
|--------|---------|
| Implemented | #1–11 (all MVP), #12 Save/Load, #13 Puzzles, #15 Kino Drone, #16 Episode Narrative, #17 Audio |
| Partial | #14 Crew AI (autoplay NPC movement only — no schedules/routines), #18 Tutorial (story progression via chapters; no dedicated Icarus Base) |
| Designed (not implemented) | #19 VRM Character Models |

---

## Next Steps

- [ ] Implement **VRM Character Models** (#19) — only system with a design doc but no code
- [ ] Expand **Crew AI** (#14) — NPC schedules, routines, reactions beyond autoplay
- [ ] Build dedicated **Icarus Base tutorial** (#18) — separate from chapter progression
- [ ] Run `/design-review` on each completed GDD
- [ ] Run `/gate-check pre-production` — all MVP systems implemented, ready for gate check
