# Ship Exploration System

> **Status**: Partially Implemented (Godot 4.6 — see Implemented vs. Designed below)
> **Author**: User + Claude
> **Last Updated**: 2026-06-09
> **Implements Pillar**: Pillar 1 (The Ship IS the World), Pillar 3 (Earned Discovery)

## Overview

The Ship Exploration System governs the gameplay of navigating and discovering
Destiny's interior. It manages what happens when the player enters new sections
(discovery events, lore reveals, environmental hazards), defines the rules for
accessing sealed or damaged areas (spatial connectivity puzzles), and populates
the ship with discoverable content — Ancient engineering data embedded in ship
systems, mission logs from Destiny's million-year autopilot journey, automated
sensor readings from star systems visited, and environmental storytelling from
the ship's physical wear. The Ancients never inhabited Destiny — it launched
unmanned — so the lore is the ship's own history, not a crew's.

**Implementation status (as of 2026-06-09):** Floors 0–1 are hand-authored rooms
wired in `data/ship_layout.json`. Floors 2+ are procedurally generated at runtime
by `ProceduralShip` (see §Procedural Floor Architecture below) and floor-gated
behind an escalating parts cost. The browser-era ggez/EventBus design in the
sections below describes the aspirational vision; the Godot 4.6 implementation
is documented in the new section first.

---

## Procedural Floor Architecture (Implemented — Godot 4.6)

### System Boundary

| Autoload | Role |
|---|---|
| `ProceduralShip` | Facade over `ShipLayout`; owns generated floor topology, floor unlocking, room assignment, repair state, save/load |
| `ShipLayout` | Authored room/edge data from `data/ship_layout.json`; static read-only; ProceduralShip delegates base-room calls to it |
| `GameState` | Quest flags, player stats, air-crisis phase, `rooms_discovered` collection |
| `SceneRouter` | Scene transitions; `instant_mode` flag for headless/test runs |

### Floor-Access Model

| Floor | Access Route | Cost |
|---|---|---|
| Floor 1 (authored spine) | Always unlocked; authored in `ship_layout.json` | Free |
| Floor 2 (upper deck) | Gate-room stairs + upper-deck link from `hydroponics`; no parts, no code required | Free |
| Floors 3 … MAX\_FLOOR | Elevator (powered) + known access code + `floor_unlock_cost(n)` parts | Escalating |
| Down-floors SL-1, SL-2 … | Elevator-only after Bridge discovered (#138); no stairs shortcut | Same formula, `absi(n)` |

Elevator power is restored by delivering the `ELEVATOR_FUSE_REQUIREMENT`
(`{"large_fuse": 1, "bus_fuse": 2}`) and completing the elevator minigame
(issue #132). Signal `elevator_power_changed` fires on restore.

### Room Catalog Categories

Defined in `data/room_types.json`, read at startup by `ProceduralShip._load_catalog()`:

| Category | Examples | Notes |
|---|---|---|
| `special_once` | bridge, observation\_deck, infirmary, astrometrics, interface\_chair, weapons\_control | `max_count=1`; drawn without replacement from pool |
| `special_limited` | stasis\_pods, mess\_hall, engineering, research\_lab | `max_count=2`; capped per type across all floors |
| `assignable` | armory, recreation, hydroponics\_bay | Unlocked by spending `ROOM_ASSIGN_COST` parts on an unassigned storage room |
| `filler` | corridor, storage, power\_node, recycling, crew\_quarters | Weighted random draw; forms the bulk of generated floors |
| `preset` | gate\_room, kino\_room, control\_interface\_room | Hand-authored; never generated |

Per-floor generation caps: specials ≤ 3 per floor; special draw fires only past
room 3 and at 20% probability (`_draw_child_type`). Floor room count cap is 12–20.

### FTL Loop and Ship Systems (Implemented)

| Issue | System | Key symbol |
|---|---|---|
| #130 | `FtlLoop` autoload — warp cycle timer, `ftl_jumped` signal | `scripts/ftl_loop.gd` |
| #133 | `BridgeLoopConfig` — Bridge consoles tune FTL parameters | `scripts/bridge_loop_config.gd` |
| #134 | `Consumption` autoload — resource drain per FTL tick | `scripts/consumption.gd` |
| #131 | `RepairRobot` — heals sealed/damaged rooms, emits `repair_completed` | `scripts/repair_robot.gd` |

### Floor-Gating Cost Curve

Constants (all in `scripts/procedural_ship.gd`):

```
FLOOR_UNLOCK_COST_BASE  = 5          # parts per floor index
ROOM_ASSIGN_COST        = 3          # parts to assign an unassigned room
SALVAGE_PANEL_GRANT     = 3          # parts per salvage-panel interaction
PARTS_BUDGET_MARGIN_PCT = 120        # 20% headroom over bare unlock cost
```

Formulas:

```
floor_unlock_cost(n)  = FLOOR_UNLOCK_COST_BASE * absi(n)
                       = 5*n   (floors 3,4,5 -> 15,20,25...)
                       = 5*|n| (down-floors SL-1,SL-2 -> 5,10...)

floor_parts_budget(n) = floor_unlock_cost(n+1) * PARTS_BUDGET_MARGIN_PCT / 100
                      >= floor_unlock_cost(n+1)    [guaranteed by construction]
```

**Affordability invariant (validated, no retune required):**
`floor_parts_budget(n) >= floor_unlock_cost(n+1)` holds for all generated floors
because `PARTS_BUDGET_MARGIN_PCT=120` ensures the budget always exceeds the bare
unlock cost by at least 20%. The curve is monotonically escalating: each floor
costs 5 more parts than the previous. Physical parts seeding (salvage panels in
`power_node`, `storage`, and `control_room`/`engineering` type rooms; 3 parts each)
is governed by `room.gd::_spawn_salvage_panel` and tracked via the budget metadata.

Filler floor\_weights (DO NOT MODIFY — changing them perturbs the deterministic
RNG seed and breaks floor-room-count assertions in `tests/smoke/test_procedural_ship.gd`):

| Type | floor\_weight |
|---|---|
| corridor | 5 |
| storage | 3 |
| power\_node | 2 |
| recycling | 2 |
| crew\_quarters | 2 |

### Per-Type Authored Set-Dressing (Implemented — Issue #135)

Special rooms are built on shared template shells but look generic without
additional detail. Issue #135 adds a **data-driven, per-room-TYPE set-dressing
layer** placed on top of the shared shell by `RoomBuilder._add_authored_setdressing()`.

**Architecture:**
- Data lives in `data/room_types.json` under a `setdressing` key per type.
- Flag `authored_setdressing: true` + presence of `setdressing` dict gates placement.
- `RoomBuilder._load_setdressing_catalog()` reads the JSON once (static cache via `_setdressing_loaded` flag).
- `RoomBuilder.build()` calls `_add_authored_setdressing()` as 4th step after shell + accents + fill light.
- Hero props placed via existing `_spawn_kenney_prop()` (tint required — glTF import strips Kenney textures, white without it).
- Walk-blockers via existing `_add_walk_blocker()` at **layer 1 ONLY** (never layer 2 / SpringArm camera layer).
- Signage via `Label3D` on the named wall face.
- No per-room `.tscn` files; no fork of `_build_shell` — purely additive.

**Authored iconic types (Issue #135):**

| Type | Template base | Hero props | Signage |
|---|---|---|---|
| `bridge` | control-room-template | table-display-planet (central holotable), 2x chair-armrest, computer-wide | "BRIDGE" on -Z wall |
| `observation_deck` | quarters-template | 3x chair-cushion, table-display, emissive window slab | "OBSERVATION DECK" on +Z wall |
| `astrometrics` | control-room-template | table-display-planet (central), 2x table-display, chair-cushion | "ASTROMETRICS" on -Z wall |
| `interface_chair` | control-room-template | chair-armrest (oversized central), 2x computer-system flanking | "INTERFACE CHAIR" on -Z wall |
| `stasis_pods` | quarters-template | 3x bed-single-cover (stasis units), computer-system monitor | "STASIS POD CHAMBER" on +Z wall |
| `infirmary` | quarters-template | 2x bed-single, computer-system (medical), container-tall (supplies) | "INFIRMARY" on -Z wall |
| `weapons_control` | control-room-template | computer-wide (main board), 2x computer-system, chair-armrest | "WEAPONS CONTROL" on -Z wall |

All prop GLBs live under `res://models/props/space_station_kit/`.

**Doorway-clearance rule:** `RoomBuilder` runs before `room.gd` stamps doors.
Props are authored at centre/back-wall positions (>= 3 m from wall midpoints
where doors stamp). Smoke test `tests/smoke/setdressing.gd` asserts no set-dressing
walk-blocker AABB centroid is within 1.5 m of representative door positions
(wall midpoints at +-half\_width, +-half\_depth on Y=0).

### Pre-Designed Group Clusters (Deferred)

The cluster mechanic (a special anchor forces an adjacent annex via
`_compute_child_rect`/`_has_collision`/`_pick_free_dir`) is designed in issue #135
§3 but **not implemented** in this sprint. An optional `cluster: {annex_type, dir_pref}`
key in `room_types.json` is reserved for future use. No data-off flag is needed
— the field is simply absent from all current entries.

---

## Player Fantasy

The Ship Exploration System serves the fantasy of **being the first person to
walk these halls in a million years.** Destiny is not a ruin — it's a functioning
(barely) vessel that has been sailing the universe on autopilot since before
humanity existed. Every room you enter, every console you activate, every sealed
door you pry open — you are the first living being to do this. The ship has been
waiting.

**Discovery** feels like archaeology in real time. You round a corner and find a
room you've never seen. The lights flicker on as power reaches it. Ancient
consoles display data you can't yet read. The walls tell a story through damage
patterns, emergency seals, and the slow erosion of a million years. You piece
together what this room was for, what went wrong, what it could be again. The
satisfaction is in *understanding* — not being told.

**Navigation** evolves with comprehension. The Kino Remote provides a complete
map of Destiny from the Ancient schematics — every section, every room, every
system is marked. But the labels are in Ancient. Early on, the map is a maze of
unreadable glyphs. You can see where rooms are, but not what they are. As Eli
learns the language, labels resolve into meaning: that room isn't just "Section
G-7" anymore, it's "Hydroponics Bay." The map was always complete — *your
understanding* is what grows. Over hours of play, Destiny transforms from a
foreign labyrinth into a home you know by name.

This serves **Pillar 3 (Earned Discovery)**: everything is marked in the Ancient
schematics, but meaning is earned through Eli's growing knowledge. The
information is there — you just can't read it yet. It serves **Pillar 1 (The
Ship IS the World)**: exploration IS the core gameplay, and the map itself is a
progression system — your understanding of Destiny deepens with every translated
label.

---

## Detailed Design (Aspirational / Forward-Looking)

> The sections below describe the full designed vision. Items noted
> [FORWARD-LOOKING] are designed but not yet built. The browser-era references
> to `ggez`, `EventBus`, and `player:entered:section` have been superseded by
> the Godot autoload architecture described in the Procedural Floor Architecture
> section above.

### Core Rules

1. **Section discovery** [FORWARD-LOOKING]: When the player enters a section for the first time
   (detected via trigger volume at section boundaries), the system:
   - Publishes a section-entry signal via `GameState` (replaces `player:entered:section` / EventBus)
   - Ship State marks the section as Explored
   - Plays a brief discovery moment: lights activate (if powered), Eli reacts
     ("What is this place?"), ambient audio shifts
   - Logs the section in the Kino Remote with its Ancient label

2. **Discoverable content types**: Each section can contain:
   - **Ancient data nodes**: Consoles, wall panels, or embedded displays
     containing ship data. Content tiered by Eli's Ancient knowledge level.
     Unreadable data shows as glyphs; readable data reveals lore, mission
     data, or system information.
   - **Supply caches**: Containers with Ship Parts, emergency supplies, or
     rare materials. Placed in logical locations (storage rooms, maintenance
     bays, emergency lockers).
   - **Environmental storytelling**: Damage patterns, emergency seals, scorch
     marks, hull repairs, rerouted conduits. Visual narrative, not interactive.

3. **Ancient knowledge tier** [FORWARD-LOOKING]: Data readability scales with a global
   `ancient_knowledge_level` (0-5) that increases through story progression.
   This system formally owns the value — it exposes `getKnowledgeLevel()`
   and `setKnowledgeLevel(tier)` as its public API. Tiers:
   - **Tier 0** (start): Can read nothing. Glyphs everywhere.
   - **Tier 1** (early S1): Basic symbols — numbers, directions, warnings.
     Critical map labels (bridge, gate room) become readable.
   - **Tier 2** (mid S1): Simple phrases. System status displays readable.
   - **Tier 3** (late S1/S2): Full sentences. Mission logs and engineering
     notes. Most map labels readable.
   - **Tier 4** (S2): Technical Ancient. Complex system data, diagnostics.
   - **Tier 5** (S3): Fluent. Everything readable, including encrypted text.

4. **Barrier types** [FORWARD-LOOKING]: Navigation obstacles gating access to new areas.
   In Godot 4.6, sealed rooms are handled by `ProceduralShip._room_conditions`
   (state: "sealed" | "damaged" | "repairing" | "repaired") with repair via
   `RepairRobot` (#131). The designed barrier taxonomy below is aspirational:
   - **Power-gated doors**: Require power to section.
   - **Mechanically jammed doors**: Physical damage. Interact + Ship Parts to force/repair.
   - **Emergency sealed doors**: Locked by Destiny's safety protocols.
   - **Debris blockage**: Collapsed structure.
   - **Knowledge-gated consoles**: Ancient interface requires minimum knowledge tier.

5. **Section boundary detection** [FORWARD-LOOKING]: Sections defined by trigger volumes.
   Player position entering a new volume fires section-entry logic.
   (Currently rooms are discovered via `GameState.rooms_discovered` collection.)

6. **Points of interest (POIs)** [FORWARD-LOOKING]: Discoverable content and interactable
   subsystems register as POIs for the Camera System's auto-framing offset.

7. **Revisit value** [FORWARD-LOOKING]: Previously explored sections gain new value when
   Ancient knowledge tier increases or Ship State changes.

8. **Guided exploration**: Exploration is free-form but the game provides
   clear guidance toward story objectives via Kino Remote map, environmental
   cues, crew hints, and world-space waypoints. Player can always ignore the
   objective — the story waits.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **Free Exploration** | Default. No active interaction. | Approach barrier or data node. | Player moves freely. POIs trigger camera auto-frame. |
| **Barrier Encounter** | Player approaches a barrier | Barrier resolved or player leaves | Radial menu shows available actions. |
| **Data Reading** | Player interacts with Ancient data node | Reading complete or cancelled | If knowledge tier sufficient: data displays. If insufficient: glyphs shown. |
| **Discovery Moment** | First entry into a new section | Moment completes (2-3s) | Brief cinematic beat. |
| **Cache Looting** | Player interacts with supply cache | Items collected | Cache opens, contents shown, resources added. |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Player Controller** | Inbound | Section entry detection, radial menu interactions |
| **Camera System** | Outbound | POI auto-framing, Discovery Moment reframe |
| **ProceduralShip** | Inbound (read) | Section states, room conditions, floor access costs |
| **ProceduralShip** | Outbound (write) | Section discovery, barrier resolution, floor unlock |
| **GameState** | Both | `rooms_discovered` collection, quest flags |
| **SceneRouter** | Inbound | Scene transitions, `instant_mode` for headless tests |
| **Inventory / Parts** | Bidirectional | Parts for floor unlock / room repair / salvage panels |
| **Episode Narrative** [forward-looking] | Inbound | Episodes set the current objective and its location |
| **Kino Remote** [forward-looking] | Outbound | Section discovery state, Ancient labels, objective marker, POI locations |

### Formulas

#### Data Node Readability [forward-looking]

```
readable = data_node.required_tier <= ancient_knowledge_level
```

#### Barrier Resolution Cost [forward-looking]

```
can_resolve = player_has(barrier.resource_cost)
              AND (barrier.knowledge_requirement <= ancient_knowledge_level)
              AND (barrier.power_requirement <= section.power_level)
```

#### Discovery Moment Duration [forward-looking]

```
moment_duration = BASE_DISCOVERY_DURATION * section_importance_multiplier
```

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Player enters section with no power** | Discovery moment plays in darkness. Data nodes dark and non-functional. | Unpowered sections explorable but limited. |
| **Player re-reads data node after knowledge tier increase** | New content appears. | Core revisit value mechanic. |
| **Player tries to resolve barrier without resources** | Action greyed out with cost display. | Clear feedback. |
| **Supply cache already looted** | Cache shows as open/empty. No interaction prompt. | Persistent state. |
| **Section compromised after exploration** | Marked Compromised on Kino Remote. Previously discovered data retained. | Story events can seal explored areas. |
| **Player ignores story objective** | No penalty. Objective marker persists. Story waits. | Free exploration is a pillar. |

## Dependencies

**Upstream:**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Player Controller | Hard | Section entry detection, radial menu, contextual traversals |
| Camera System | Hard | POI auto-framing, Discovery Moment reframe |
| ProceduralShip | Hard (Godot 4.6) | Section states, floor unlock, room conditions, save/load |
| GameState | Hard (Godot 4.6) | rooms_discovered collection, quest flags |
| SceneRouter | Hard (Godot 4.6) | Scene transitions, instant_mode |

**Downstream:**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Kino Remote | Hard | Section map data, Ancient labels, objective markers, POI locations |
| Episode Narrative | Soft | Section discovery state for story triggers |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `FLOOR_UNLOCK_COST_BASE` | 5 | **Do not change** — RNG-sensitive | Higher cost per floor | Lower cost per floor |
| `ROOM_ASSIGN_COST` | 3 | 2-6 | Room assignment costs more | Cheaper assignment |
| `SALVAGE_PANEL_GRANT` | 3 | 2-6 | More parts per panel | Fewer parts per panel |
| `PARTS_BUDGET_MARGIN_PCT` | 120 | 110-150 | More headroom above unlock cost | Less headroom |
| `BASE_DISCOVERY_DURATION` | 2.0 s | 1.0-4.0 | Longer discovery beats | Briefer |
| `BARRIER_REPAIR_COST_DOOR` | 3 SP | 1-10 | Doors cost more to repair | Cheaper repair |
| `CACHE_SHIP_PARTS_MIN` | 2 | 1-5 | More parts per cache minimum | Less rewarding |
| `CACHE_SHIP_PARTS_MAX` | 8 | 3-15 | More parts per cache maximum | Smaller rewards |

## Acceptance Criteria

### Implemented (Godot 4.6)

- [x] Procedural floor generation: floors 3+ generated deterministically; 12-20 rooms; <=3 specials per floor.
- [x] Floor-access gating: floor 1 always free; floor 2 via stairs (no cost); floors 3+ require elevator power + code + parts.
- [x] Elevator power restore via fuse delivery + minigame (#132).
- [x] Floor unlock cost curve: `floor_unlock_cost(n) = 5*absi(n)`; budget >= next unlock cost guaranteed.
- [x] FTL loop: `FtlLoop` autoload warp cycle with Bridge tuning (#130, #133).
- [x] Consumption: resource drain per FTL tick (#134).
- [x] Repair robot: sealed/damaged rooms healed over time (#131).
- [x] Room assignment: unassigned storage rooms assignable for `ROOM_ASSIGN_COST` parts.
- [x] Save/load: full round-trip for generated topology, conditions, assignments.
- [x] Authored set-dressing: 7 iconic special room types have per-TYPE hero props + signage + accent lights (#135).

### Forward-Looking (not yet implemented)

- [ ] Section discovery trigger volumes and first-visit events.
- [ ] Discovery moment: lights activate, Eli reacts, audio shifts.
- [ ] Ancient data nodes: knowledge-tier readable/unreadable pipeline.
- [ ] Supply caches: grant resources, persist as empty.
- [ ] Full barrier taxonomy: all 5 barrier types functional.
- [ ] POI registration for camera auto-framing.
- [ ] Objective markers on Kino Remote map and in world-space.
- [ ] Map label resolution: Ancient to English as knowledge tier grows.
- [ ] Pre-designed group clusters: anchor special + forced-adjacent annex.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| How many total sections should Destiny have? | Level Designer | Before content planning | — |
| Should the objective marker be toggleable in settings? | UX Designer | Before UI implementation | — |
| How does ancient_knowledge_level increase — discrete events or gradual? | Episode Narrative GDD | When Episode Narrative designed | — |
| Should environmental storytelling include ghost holograms of Ancient construction? | Creative Director | Pre-production | — |
| How many data nodes per section is the right density? | Level Designer | During prototype | — |
| Should the Kino drone scout ahead into unpowered sections? | Kino Drone GDD | When Kino Drone designed | — |
| Cluster mechanic: which specials form clusters, what adjacency preferences? | Systems Designer | Post-E1 | Deferred from #135 |
