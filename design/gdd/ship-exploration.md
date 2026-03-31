# Ship Exploration System

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-30
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

Exploration has two phases: **discovery** (first visit — learn what's here, find
data, identify subsystems to repair) and **navigation** (return visits — use
accumulated knowledge to unlock efficient routes and access previously impassable
areas).

Ship data is tiered by Eli's growing understanding of Ancient technology and
language. Early in the game, Ancient consoles display unreadable glyphs and Eli
comments "I can't read this yet." As the story progresses and Eli's knowledge
grows, previously opaque data becomes readable — rewarding players who revisit
old sections with new understanding. The player never receives explicit objectives
or waypoints; exploration is self-directed, guided by environmental cues, the
Kino Remote map, and curiosity.

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
Γ-7" anymore, it's "Hydroponics Bay." The map was always complete — *your
understanding* is what grows. Over hours of play, Destiny transforms from a
foreign labyrinth into a home you know by name.

This serves **Pillar 3 (Earned Discovery)**: everything is marked in the Ancient
schematics, but meaning is earned through Eli's growing knowledge. The
information is there — you just can't read it yet. It serves **Pillar 1 (The
Ship IS the World)**: exploration IS the core gameplay, and the map itself is a
progression system — your understanding of Destiny deepens with every translated
label.

## Detailed Design

### Core Rules

1. **Section discovery**: When the player enters a section for the first time
   (detected via trigger volume at section boundaries), the system:
   - Publishes `player:entered:section` with `first_visit: true`
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

3. **Ancient knowledge tier**: Data readability scales with a global
   `ancient_knowledge_level` (0-5) that increases through story progression:
   - **Tier 0** (start): Can read nothing. Glyphs everywhere.
   - **Tier 1** (early S1): Basic symbols — numbers, directions, warnings.
     Critical map labels (bridge, gate room) become readable.
   - **Tier 2** (mid S1): Simple phrases. System status displays readable.
   - **Tier 3** (late S1/S2): Full sentences. Mission logs and engineering
     notes. Most map labels readable.
   - **Tier 4** (S2): Technical Ancient. Complex system data, diagnostics.
   - **Tier 5** (S3): Fluent. Everything readable, including encrypted text.

4. **Barrier types**: Navigation obstacles gating access to new areas:
   - **Power-gated doors**: Require power to section. Repair upstream conduits
     → door opens automatically.
   - **Mechanically jammed doors**: Physical damage. Interact + Ship Parts to
     force/repair. May be a contextual traversal (squeeze through partial
     opening).
   - **Emergency sealed doors**: Locked by Destiny's safety protocols
     (compromised section behind). Requires console override or remote hazard
     repair.
   - **Debris blockage**: Collapsed structure. Requires clearing (Ship Parts)
     or alternate route (vent, maintenance shaft) via contextual traversal.
   - **Knowledge-gated consoles**: Ancient interface requires minimum
     knowledge tier. Eli can see it but can't use it until he understands
     enough Ancient.

5. **Section boundary detection**: Sections defined by trigger volumes in the
   ggez scene. Player position entering a new volume fires section-entry
   logic. Overlapping volumes at doorways use hysteresis to prevent rapid
   toggling.

6. **Points of interest (POIs)**: Discoverable content and interactable
   subsystems register as POIs for the Camera System's auto-framing offset.
   POIs include: unread data nodes, supply caches, damaged subsystems,
   barrier-solving consoles.

7. **Revisit value**: Previously explored sections gain new value when:
   - Ancient knowledge tier increases (unreadable → readable)
   - Ship State changes (conduit repair powers up a console in old room)
   - Episode events create new content in old sections

8. **Guided exploration**: Exploration is free-form but the game provides
   clear guidance toward story objectives:
   - **Objective markers**: The current story objective is marked on the Kino
     Remote map and shown as a waypoint in the world (subtle, diegetic —
     e.g., a pulsing indicator on the Kino Remote's HUD overlay, not a
     floating diamond in the sky).
   - **Kino Remote map**: Complete Ancient schematics with labels that resolve
     as Eli learns. Objective destination is highlighted.
   - **Environmental cues**: Light, sound, power humming, crew activity — all
     reinforce where the story is pulling.
   - **Crew hints**: NPCs mention locations and objectives in dialogue.
   - **Free to ignore**: The player can always ignore the objective and
     explore freely. The story waits. But the guidance is always there when
     you want it.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **Free Exploration** | Default. No active interaction. | Approach barrier → Barrier Encounter. Approach data node → Data Reading. | Player moves freely. POIs trigger camera auto-frame. Section boundaries detect entry. |
| **Barrier Encounter** | Player approaches a barrier | Barrier resolved or player leaves | Radial menu shows available actions (repair, force, bypass, override). Ship State and resources checked. |
| **Data Reading** | Player interacts with Ancient data node | Reading complete or cancelled | If knowledge tier sufficient: data displays with translation. If insufficient: glyphs shown, Eli comments. Game pauses during reading. |
| **Discovery Moment** | First entry into a new section | Moment completes (2-3s) | Brief cinematic beat: lights activate, Eli reacts, ambient audio shifts. Player retains movement, camera may subtly reframe. |
| **Cache Looting** | Player interacts with supply cache | Items collected | Cache opens, contents shown, resources added to inventory. Cache marked empty (persistent). |

All states respect universal pause — pausing freezes any active state and
resumes exactly.

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Player Controller** | Inbound | Receives `player:entered:section` for discovery. Radial menu interactions trigger barrier resolution, data reading, cache looting. |
| **Camera System** | Outbound (POI registration) | Registers discoverable content and subsystems as POIs for auto-frame offset. Triggers Discovery Moment camera reframe on first section entry. |
| **Ship State** | Inbound (read) | Reads section states (Explored, Accessible, Compromised), subsystem conditions, power levels, atmosphere. Determines what barriers are present and whether they can be resolved. |
| **Ship State** | Outbound (write via events) | Section discovery updates (`ship:section:discovered`). Barrier resolution may trigger `ship:subsystem:repaired` or `ship:section:unlocked`. |
| **Event Bus** | Both | Subscribes to `ship:power:changed` (may open power-gated doors), `episode:*` (new content in sections). Publishes section discovery and barrier events. |
| **Resource & Inventory** *(undesigned)* | Bidirectional | Checks resource availability for barrier resolution (Ship Parts). Adds resources from supply caches. |
| **Episode Narrative** *(undesigned)* | Inbound | Episodes set the current objective and its location. Exploration system displays the objective marker on Kino Remote and as a world-space waypoint. |
| **Kino Remote** *(undesigned)* | Outbound | Provides section discovery state, Ancient labels (with knowledge tier filtering), objective marker position, and POI locations for the map display. |
| **Ancient Tech Puzzles** *(undesigned)* | Outbound | Some barriers are resolved by puzzles rather than simple interaction. Exploration hands off to the puzzle system and receives completion callback. |
| **ggez Scene Management** | Inbound | Sections map to ggez scenes or sub-scenes. Scene loading/unloading triggered by section transitions. |

**Provisional contracts:**
- Episode Narrative: objective data format (location, description, priority) TBD
- Resource & Inventory: cache content schema TBD
- Kino Remote: map data format and label rendering protocol TBD

## Formulas

### Data Node Readability

```
readable = data_node.required_tier <= ancient_knowledge_level
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `data_node.required_tier` | int | 0-5 | level design | Minimum knowledge tier to read this node |
| `ancient_knowledge_level` | int | 0-5 | story progression | Eli's current Ancient comprehension |

### Map Label Resolution

```
label_readable = label.knowledge_tier <= ancient_knowledge_level
display_text = label_readable ? label.translated : label.ancient_glyphs
```

Labels are pre-authored with both Ancient glyph text and English translations.
The system selects which to display based on Eli's current tier.

### Barrier Resolution Cost

```
can_resolve = player_has(barrier.resource_cost)
              AND (barrier.knowledge_requirement <= ancient_knowledge_level)
              AND (barrier.power_requirement <= section.power_level)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `barrier.resource_cost` | int | 0-20 Ship Parts | level design | Ship Parts required |
| `barrier.knowledge_requirement` | int | 0-5 | level design | Minimum Ancient tier |
| `barrier.power_requirement` | float | 0-1.0 | level design | Minimum section power |

### Discovery Moment Duration

```
moment_duration = BASE_DISCOVERY_DURATION * section_importance_multiplier
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `BASE_DISCOVERY_DURATION` | float | 2.0 s | config | Standard discovery beat |
| `section_importance_multiplier` | float | 1.0-2.0 | level design | Longer moments for major areas (bridge, observation deck) |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Player enters section with no power** | Discovery moment plays in darkness — Eli's phone light activates (per Player Controller), minimal ambient light from hull breaches/starlight. Data nodes are dark and non-functional. | Unpowered sections are explorable but limited. Adds motivation to restore power. |
| **Player re-reads a data node after knowledge tier increases** | New content appears. Previously shown glyphs now have translations. Eli comments on understanding it now. | Core revisit value mechanic. |
| **Player tries to resolve barrier without resources** | Radial menu shows the action greyed out with "Requires X Ship Parts" label. | Clear feedback, no confusion. |
| **Knowledge-gated console at current tier** | Console shows glyphs. Eli says "I'm not sure what this does yet." Interaction logged so Kino Remote can show "unresolved data node" on map. | Player knows to come back later. |
| **Two section trigger volumes overlap** | Hysteresis: player must fully exit one volume before entering another. If straddling boundary, remains in previous section. | Prevents rapid section-toggling at doorways. |
| **Supply cache already looted** | Cache shows as open/empty. No interaction prompt. | Persistent state — caches are one-time. |
| **Section becomes compromised after exploration** | Section marked as Compromised on Kino Remote (flashing red). Player cannot re-enter until breach repaired. Previously discovered data is retained. | Story events can seal off explored areas. Adds drama. |
| **Episode changes content in explored section** | New content silently appears. No notification — the player discovers it on revisit. Unless it's critical, in which case crew dialogue hints at it. | Rewards exploration without spoiling surprise. |
| **Player ignores story objective entirely** | No penalty. Objective marker persists on Kino Remote. Crew may comment but never block. Story waits for the player. | Free exploration is a pillar. Story guides but never forces. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Player Controller | Hard | Section entry detection, radial menu interactions, contextual traversals |
| Camera System | Hard | POI auto-framing, Discovery Moment camera reframe |
| Ship State | Hard | Section states, subsystem conditions, power levels, atmosphere |
| Event Bus | Hard | Section discovery events, ship state change subscriptions |
| ggez Scene Management | Hard | Scene loading for section transitions |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Kino Remote | Hard | Section map data, Ancient labels with tier filtering, objective markers, POI locations |
| Episode Narrative | Soft | Section discovery state for story triggers |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `BASE_DISCOVERY_DURATION` | 2.0 s | 1.0-4.0 | Longer discovery beats. Above 4.0 disrupts flow. | Briefer. Below 1.0 barely noticeable. |
| `SECTION_BOUNDARY_HYSTERESIS` | 1.0 m | 0.5-2.0 | Wider boundary overlap before section switch. | Tighter. Below 0.5 may rapid-toggle. |
| `POI_DETECTION_RANGE` | 8.0 m | 4.0-15.0 | POIs influence camera from further away. | Must be closer before auto-frame activates. |
| `BARRIER_REPAIR_COST_DOOR` | 3 SP | 1-10 | Doors cost more to repair. Resources scarcer. | Doors cheap. Faster progression. |
| `BARRIER_REPAIR_COST_DEBRIS` | 5 SP | 2-15 | Debris clearance expensive. | Cheaper debris clearing. |
| `BARRIER_REPAIR_COST_CONSOLE` | 0 SP | 0-5 | Console overrides cost Ship Parts. | Free to use (just knowledge-gated). |
| `CACHE_SHIP_PARTS_MIN` | 2 | 1-5 | Minimum Ship Parts per cache. | Caches less rewarding. |
| `CACHE_SHIP_PARTS_MAX` | 8 | 3-15 | Maximum Ship Parts per cache. | Smaller cache rewards. |
| `OBJECTIVE_MARKER_OPACITY` | 0.7 | 0.3-1.0 | More visible waypoint. | Subtler marker. Below 0.3 easy to miss. |
| `ANCIENT_KNOWLEDGE_TIER_*` | per story | 0-5 per event | Faster knowledge growth. | Slower unlock of readable content. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Section discovery (first entry) | Lights activate (if powered), dust particles, environmental reveal | Power-up hum, Eli's reaction voice line, ambient shift | High |
| Data node interaction (readable) | Ancient text with English translation overlay | Console activation sound, data processing tone | High |
| Data node interaction (unreadable) | Ancient glyphs displayed, no translation | Console beep, Eli's "I can't read this" | Medium |
| Supply cache opened | Cache lid/door opens, contents glow briefly | Mechanical open, resource pickup chime | High |
| Barrier resolved (door opens) | Door animation, light floods through | Door mechanism, atmosphere equalization hiss | High |
| Objective marker (world-space) | Subtle diegetic pulse on Kino Remote HUD overlay | None (silent — not intrusive) | Medium |
| POI nearby | Camera auto-frame offset (handled by Camera System) | None | Low |

## UI Requirements

| Information | Display Location | Update Trigger | Condition |
|-------------|-----------------|----------------|-----------|
| Objective waypoint | World-space Kino Remote HUD overlay | Episode sets/clears objective | Active story objective exists |
| Data node content | Screen overlay (pause-style) | Player reads a data node | Interaction with data node |
| Barrier info | Radial menu labels | Player approaches barrier | Within interaction range |
| "New data available" | Kino Remote notification | Ancient knowledge tier increases | Previously unreadable nodes now readable |

No persistent HUD for exploration. Objective marker is the only always-visible
element, and it's rendered as a diegetic Kino Remote overlay, not a game UI
element.

## Acceptance Criteria

- [ ] **Section discovery**: Entering a new section triggers discovery moment, marks section as Explored in Ship State, and logs on Kino Remote.
- [ ] **Discovery moment**: Lights activate (if powered), Eli reacts, audio shifts. Duration matches config. Player retains movement.
- [ ] **Ancient data nodes**: Readable nodes display translated content. Unreadable nodes show glyphs + Eli comment. Tier check is correct.
- [ ] **Data node revisit**: Increasing ancient_knowledge_level makes previously unreadable nodes readable on revisit.
- [ ] **Supply caches**: Caches grant Ship Parts / resources. Looted caches persist as empty. Cannot loot twice.
- [ ] **Barrier types**: All 5 barrier types (power-gated, jammed, sealed, debris, knowledge-gated) function correctly with their resolution conditions.
- [ ] **Barrier resource check**: Insufficient resources greys out the action with clear cost display.
- [ ] **POI registration**: Data nodes, caches, and subsystems register as POIs for Camera auto-framing.
- [ ] **Objective markers**: Active story objective shows on Kino Remote map and as a world-space waypoint. Free to ignore.
- [ ] **Map labels**: Ancient labels on Kino Remote resolve to English as ancient_knowledge_level increases.
- [ ] **Section boundary detection**: Trigger volumes correctly detect entry/exit. Hysteresis prevents rapid toggling at doorways.
- [ ] **Revisit value**: Ship State changes (power restored, episode events) create new interactable content in previously explored sections.
- [ ] **Universal pause**: All exploration states pause and resume correctly.
- [ ] **Performance**: Section entry logic completes within 1ms. POI detection within 0.5ms per frame.
- [ ] **All tuning values externalized**: Barrier costs, cache amounts, discovery durations loaded from config.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| How many total sections should Destiny have? Each needs level design, content placement, and barrier design. | Level Designer | Before content planning | — |
| Should the objective marker be toggleable in settings (for players who want harder exploration)? | UX Designer | Before UI implementation | — |
| How does ancient_knowledge_level increase? Discrete story events, or gradual via reading data nodes? | Episode Narrative GDD | When Episode Narrative designed | — |
| Should environmental storytelling include "ghost" holograms showing Ancient construction/launch? (High production cost but very cool) | Creative Director | Pre-production | — |
| How many data nodes per section is the right density? Too few = boring. Too many = overwhelming. Needs playtesting. | Level Designer | During prototype | — |
| Should the Kino drone be deployable to scout ahead into unpowered sections before Eli enters? | Kino Drone GDD | When Kino Drone designed | — |
