# Systems Index: Stargate Universe — The Destiny Mission

> **Status**: Draft
> **Created**: 2026-03-29
> **Last Updated**: 2026-03-29
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

Stargate Universe is a third-person exploration-survival game aboard the Ancient
ship Destiny. The systems divide into two domains: **ship systems** (exploring,
repairing, and managing Destiny) and **planetary systems** (gating to worlds for
time-limited supply runs). A narrative layer drives the story through episodes,
crew relationships, and player choices. The ggez framework provides scene
management, physics (Crashcat), animation, and the render pipeline — all custom
systems build on top of this foundation.

The game pillars that constrain system design:
- **The Ship IS the World** — Ship State is the bottleneck system; everything reads it
- **Survival with Purpose** — Resources serve story, not grind
- **Earned Discovery** — No hand-holding UI; Kino Remote is diegetic
- **Your Choices, Your Destiny** — Dialogue and Episode systems must support branching

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | Event Bus | Core | MVP | Designed | design/gdd/event-bus.md | (none — foundation) |
| 2 | Player Controller (third-person) | Core | MVP | Designed | design/gdd/player-controller.md | ggez Gameplay Runtime, ggez Physics |
| 3 | Camera System (third-person) | Core | MVP | Designed | design/gdd/camera-system.md | Player Controller |
| 4 | Ship State System | Gameplay | MVP | Designed | design/gdd/ship-state-system.md | Event Bus, Save/Load (interface) |
| 5 | Ship Exploration System | Gameplay | MVP | Designed | design/gdd/ship-exploration.md | Player Controller, Camera, Ship State, ggez Scene Mgmt |
| 6 | Resource & Inventory System | Economy | MVP | Not Started | — | Event Bus, Save/Load (interface) |
| 7 | Timer & Pressure System | Gameplay | MVP | Not Started | — | Event Bus |
| 8 | Stargate & Planetary Runs | Gameplay | MVP | Not Started | — | Player Controller, Camera, Timer, ggez Scene Mgmt, Resource System |
| 9 | Crew Dialogue & Choice System | Narrative | MVP | Not Started | — | Event Bus, Save/Load (interface) |
| 10 | Kino Remote (diegetic menu) | UI | MVP | Not Started | — | Ship State, Resource System, ggez Scene Mgmt |
| 11 | Ship Atmosphere & Lighting | Audio/Visual | MVP | Not Started | — | Ship State, ggez Render Pipeline |
| 12 | Save/Load System | Persistence | Vertical Slice | Not Started | — | Event Bus |
| 13 | Ancient Tech Puzzle System | Gameplay | Vertical Slice | Not Started | — | Player Controller, Ship State |
| 14 | Crew AI & Schedule System | Gameplay | Vertical Slice | Not Started | — | Ship State, Event Bus, ggez Scene Mgmt |
| 15 | Kino Drone (first-person scout) | Gameplay | Vertical Slice | Not Started | — | Camera System, Ship State, Player Controller |
| 16 | Episode Narrative System | Narrative | Vertical Slice | Not Started | — | Dialogue System, Ship State, Timer, Event Bus |
| 17 | Audio & Ambience System | Audio/Visual | Vertical Slice | Not Started | — | Ship State, Event Bus, ggez Scene Mgmt |
| 18 | Tutorial / Onboarding (Icarus Base) | Meta | Alpha | Not Started | — | All MVP + VS gameplay systems |

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

## ggez-Provided Foundation

These systems are built into the ggez framework and do NOT require custom design
documents. They are configured, not designed:

| System | ggez Package | Notes |
|--------|-------------|-------|
| Scene Management | `@ggez/gameplay-runtime`, `@ggez/three-runtime` | Scene loading, preload, caching |
| Physics | `@ggez/runtime-physics-crashcat` | Rigid bodies, collision, raycasting |
| Animation Pipeline | `@ggez/anim-core`, `@ggez/anim-runtime`, `@ggez/anim-three` | Skeletal animation playback |
| Render Pipeline | `@ggez/render-pipeline` | PBR materials, instanced mesh, WebGPU |
| Gameplay Runtime Loop | `@ggez/gameplay-runtime` | Fixed timestep update, system registration |

Custom systems register with the gameplay runtime via `createGameplayRuntime()`
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

### Foundation Layer (ggez-provided)

- ggez Scene Management — loading/unloading environments
- ggez Physics (Crashcat) — collision, raycasting, rigid bodies
- ggez Animation Pipeline — skeletal animation playback
- ggez Render Pipeline — PBR materials, WebGPU rendering
- ggez Gameplay Runtime — update loop, system registration

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
| Total systems identified | 18 |
| Design docs started | 5 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| MVP systems designed | 5/11 |
| Vertical Slice systems designed | 0/6 |

---

## Next Steps

- [ ] Design MVP-tier systems in order (use `/design-system [system-name]`)
- [ ] Start with **Event Bus** (Order #1) — smallest, foundational
- [ ] Run `/design-review` on each completed GDD
- [ ] Prototype **Ship State System** data model early (highest risk)
- [ ] Run `/gate-check pre-production` when MVP systems are designed
- [ ] Prototype the core exploration loop with `/prototype core-exploration`
