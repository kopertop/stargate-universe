# Resource & Inventory System

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-30
> **Implements Pillar**: Pillar 2 (Survival with Purpose)

## Overview

The Resource & Inventory System tracks all resources and items the crew has
collected. Resources are gathered from supply caches on Destiny, scavenging on
alien worlds during planetary runs, and occasionally from story events. All
resources go into a shared ship-wide pool — there are no carry limits, no weight,
no inventory tetris. Eli doesn't manage a backpack; the crew stores everything
communally aboard Destiny.

The system starts with a small set of core resources (Ship Parts, Water, Food) and
expands as the story progresses — new resource types are unlocked through
exploration and narrative events (Ancient Components, Naquadah, Medical Supplies,
etc.). Story-specific items are a distinct category that can grant new capabilities
or unlock progression gates (e.g., a recovered Ancient control crystal that enables
a new ship system). The resource economy is designed to create drama through
scarcity, not busywork through management — in line with **Pillar 2 (Survival with
Purpose)**.

## Player Fantasy

The Resource & Inventory System serves the fantasy of **managing survival on a
ship that's running out of everything.** You are not a hoarder sorting inventories
— you are a crisis manager triaging what the crew needs most. Water is low? That's
not a number going down; that's rationing, crew arguments, and a desperate search
on the next planet. Ship Parts running out? That's choosing which broken system to
fix and which to leave broken.

Resources are never abstract — they're tied to visible consequences aboard Destiny.
When you find a cache of Ship Parts in an unexplored section, it's not "loot" —
it's relief. When you return from a planet with lime for the CO2 scrubbers, the
crew breathes easier. When you find an Ancient control crystal, it's not just an
item — it's a door to new capabilities the crew didn't have before.

Story items are the real prizes. A recovered Ancient data core might unlock a new
section of the ship. A Lucian Alliance communication device might open a diplomatic
channel. These items feel like **discoveries that change the game**, not just
numbers in a ledger.

This serves **Pillar 2 (Survival with Purpose)**: resources serve story, not grind.
Every resource has a visible impact on the ship and crew. Scarcity creates drama,
not busywork.

## Detailed Design

### Core Rules

1. **Two item categories**: The inventory holds **resources** (stackable,
   countable commodities) and **story items** (unique, named objects with
   narrative significance). Tracked separately.

2. **Resource types** (expandable — new types unlock via story):

   | Resource | Available From | Primary Use | Introduced |
   |----------|---------------|-------------|------------|
   | Ship Parts | Start | General repairs (most subsystems) | Episode 1 |
   | Water | Start | Crew hydration (biological need) | Episode 1 |
   | Food | Start | Crew nutrition (morale, health) | Episode 1 |
   | Lime | Early S1 | CO2 scrubbing (life support consumable) | First planet mission |
   | Naquadah | Mid S1 | Power system repairs, high-tier fixes | Story event |
   | Medical Supplies | Early S1 | Crew health events, injury treatment | First aid discovery |
   | Ancient Components | Late S1 | Advanced repairs, unlocking Ancient tech | Ancient section discovered |
   | *(more unlocked in S2/S3)* | Story progression | Specialized uses | As needed |

3. **Ship-wide pool**: All resources go into a single shared inventory. No
   personal carry limits, no weight system, no storage containers. Resources
   are available from anywhere on the ship.

4. **Resource sources**:
   - **Supply caches on Destiny**: Found during ship exploration (2-8 Ship
     Parts per cache, plus occasional other resources)
   - **Planetary scavenging**: Gathered during timed planetary runs (primary
     source for Water, Food, Lime, specialized resources)
   - **Story events**: Episodes can grant or consume resources as narrative
   - **Salvage**: Broken subsystems can be salvaged for parts (destroys the
     subsystem permanently)

5. **Resource consumption**:
   - **Ship repairs**: Ship State requests resources via `resource:consumed`.
     Most repairs cost Ship Parts.
   - **Crew biological needs**: Crew members consume **Water** and **Food**
     over time. Running low triggers rationing, morale drops, crisis
     episodes. Running out triggers severe narrative consequences.
   - **Life support (CO2 scrubbing)**: Life support consumes **Lime** (or
     equivalent CO2 sequestration substance) to scrub CO2 from breathable
     air. O2/CO2 balance is a throttle — when lime runs out, CO2 builds up
     and oxygen becomes unbreathable. Lime consumption rate scales with
     crew size and active section count. This is the primary survival
     pressure.
   - **Story costs**: Narrative choices may require spending resources
     ("Trade half our food for safe passage").

6. **Story items**: Unique objects that cannot be stacked, consumed, or
   traded. They exist as flags — either you have it or you don't.
   Story items can:
   - Unlock new ship capabilities (Ancient control crystal → new system)
   - Open narrative branches (Lucian Alliance device → new dialogue)
   - Gate progression (requires item X to proceed with episode Y)
   - Grant passive bonuses (Ancient tool → repair_skill_modifier improves)

7. **Events**: Published via Event Bus:
   - `resource:collected` — payload: resource type, amount, source
   - `resource:consumed` — payload: resource type, amount, consumer
   - `resource:depleted` — payload: resource type (fires when hitting 0)
   - `inventory:story-item:acquired` — payload: item ID, item name

8. **Serialization**: Inventory serializes as `{ resource_type: amount }` map
   for resources and `string[]` of story item IDs for story items.

### States and Transitions

Resources don't have states — they are simple integer quantities. The
interesting states are the **scarcity thresholds** that trigger gameplay:

| Resource | Comfortable | Low | Critical | Depleted |
|----------|------------|-----|----------|----------|
| Water | >70% of capacity | 30-70% | <30% | 0 |
| Food | >70% | 30-70% | <30% | 0 |
| Lime | >50% | 20-50% | <20% | 0 |
| Ship Parts | >20 | 5-20 | <5 | 0 |

| Threshold | Effect |
|-----------|--------|
| **Comfortable** | No gameplay effect. Crew is content. |
| **Low** | Crew dialogue mentions shortages. Kino Remote shows amber warning. Rationing begins (consumption rate halved, morale penalty). |
| **Critical** | Crisis episode may trigger. Kino Remote shows red warning. Crew arguments and desperation. Heavy morale penalty. |
| **Depleted** | Severe narrative consequences. Crew health degrades (water/food). Forces urgent planetary run or desperate measures. |

**Lime scarcity response**: When lime drops to Low or Critical, the crew
begins shutting down non-essential sections to reduce the atmosphere volume
that needs CO2 scrubbing. This is an automatic Ship State response — sections
are sealed off in reverse priority order (least essential first). The player
can override this via the Kino Remote, but doing so accelerates lime
consumption. When lime is resupplied, sections reopen. This creates a visible,
spatial consequence of resource scarcity — Destiny literally shrinks around
you when supplies run low.

Story items have two states: **not acquired** and **acquired**. Some may
additionally track **used** (consumed during a story event, no longer in
inventory).

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Event Bus** | Outbound (publish) | Publishes `resource:collected`, `resource:consumed`, `resource:depleted`, `inventory:story-item:acquired`. |
| **Event Bus** | Inbound (subscribe) | Subscribes to `player:interact` (cache looting triggers collection). |
| **Ship State** | Inbound (consumer) | Ship State requests resources for repairs. Checks availability via `hasResource(type, amount)`. Consumes via `resource:consumed`. |
| **Ship Exploration** | Inbound (source) | Supply caches provide resources. Exploration system calls `addResource(type, amount)` on cache loot. |
| **Stargate & Planetary Runs** *(undesigned)* | Inbound (source) | Primary source for Water, Food, Lime, and specialized resources. Planetary scavenging adds to the pool. |
| **Timer & Pressure** *(undesigned)* | Outbound (trigger) | Resource depletion can trigger timed crisis events. |
| **Crew Dialogue & Choice** *(undesigned)* | Outbound (context) | Dialogue system reads resource levels for contextual crew reactions (rationing complaints, gratitude after resupply). |
| **Episode Narrative** *(undesigned)* | Bidirectional | Episodes can grant/consume resources and story items. Resource thresholds can trigger episode events. |
| **Kino Remote** *(undesigned)* | Outbound (read) | Displays resource quantities, scarcity warnings, and story item inventory. |
| **Save/Load** *(undesigned)* | Outbound (serialization) | `serialize()`/`deserialize()` for resource counts and story item list. |

**Provisional contracts:**
- Stargate & Planetary Runs: resource gathering mechanics and yields TBD
- Crew Dialogue: resource-contextual dialogue trigger thresholds TBD

## Formulas

### Crew Water Consumption

```
water_per_hour = crew_count * WATER_PER_PERSON_PER_HOUR * rationing_modifier
rationing_modifier = water_level > LOW_THRESHOLD ? 1.0 : 0.5
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `crew_count` | int | 10-80 | story state | Active crew members aboard |
| `WATER_PER_PERSON_PER_HOUR` | float | 0.1-0.5 | config | Water units consumed per person per game-hour |
| `rationing_modifier` | float | 0.5 or 1.0 | calculated | Halved when water is Low or Critical |

### Crew Food Consumption

```
food_per_hour = crew_count * FOOD_PER_PERSON_PER_HOUR * rationing_modifier
```

Same structure as water. Food rationing additionally applies a morale penalty.

### Lime Consumption (CO2 Scrubbing)

```
lime_per_hour = active_section_count * LIME_PER_SECTION_PER_HOUR
             * crew_density_modifier
crew_density_modifier = crew_in_section / STANDARD_CREW_PER_SECTION
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `active_section_count` | int | 1-30+ | Ship State | Sections with active life support |
| `LIME_PER_SECTION_PER_HOUR` | float | 0.05-0.2 | config | Lime consumed per section per hour |
| `crew_density_modifier` | float | 0.5-3.0 | calculated | More people = more CO2 = more lime needed |

**Key relationship**: Shutting down non-essential sections reduces
`active_section_count`, directly reducing lime consumption.

### Supply Cache Contents

```
ship_parts = random(CACHE_SP_MIN, CACHE_SP_MAX)
bonus_resource = random_chance(CACHE_BONUS_CHANCE) ? random_resource() : none
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `CACHE_SP_MIN` | int | 2 | config | Min Ship Parts per cache |
| `CACHE_SP_MAX` | int | 8 | config | Max Ship Parts per cache |
| `CACHE_BONUS_CHANCE` | float | 0.3 | config | 30% chance of bonus resource |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Resource reaches 0** | `resource:depleted` fires. Narrative consequences begin. No negative values — clamped to 0. | Clean depletion trigger. Negative inventory makes no sense. |
| **Repair attempted with 0 Ship Parts** | Repair action greyed out in radial menu. Clear "Need X Ship Parts" label. | Consistent with Ship Exploration barrier feedback. |
| **Lime depleted** | CO2 builds up. Sections begin shutting down automatically. Life support enters crisis mode. Crew dialogue becomes desperate. Triggers urgent planetary run episode. | The most dangerous depletion — affects everyone aboard. |
| **Water depleted** | Crew health degrades over time. Morale crashes. Crisis episode triggers. | Severe but slower than lime — humans can survive days without water. |
| **Food depleted** | Morale crashes. Crew arguments increase. Rationing dialogue. Less immediately lethal than water. | Food scarcity is drama fuel, not instant death. |
| **Story item already acquired** | Cannot pick up again. Source shows as "already taken" or doesn't appear. | Story items are flags — no duplicates. |
| **Resource overflow (gathering more than needed)** | No cap. Resources accumulate indefinitely. Surplus is fine — it means the player is doing well. | No artificial caps. Abundance is earned. |
| **New resource type unlocked** | Resource appears in Kino Remote inventory display at 0 quantity. Player now knows it exists and can seek it. | Discovery of a new resource type is itself a progression moment. |
| **Salvage a subsystem the player needs later** | Salvage is permanent — subsystem is destroyed. Warning dialog: "This cannot be undone. Salvage for X Ship Parts?" Player must confirm. | Prevent accidental destruction of important subsystems. |
| **Episode grants negative resources (cost)** | Deducted from pool. If insufficient, episode handles gracefully (reduced amount or alternative narrative). | Story costs should never softlock the player. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Event Bus | Hard | Publishes resource events, subscribes to interaction events |
| Save/Load (interface) | Hard (contract) | Serialization of resource counts + story item list |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Ship State | Hard | `hasResource()` check + `resource:consumed` for repairs |
| Ship Exploration | Soft | `addResource()` for cache looting |
| Stargate & Planetary Runs | Hard | `addResource()` for planetary scavenging yields |
| Kino Remote | Hard | Resource quantities + scarcity warnings for display |
| Crew Dialogue & Choice | Soft | Resource levels for contextual dialogue |
| Episode Narrative | Hard | Resource grants/costs, story item acquisition |
| Timer & Pressure | Soft | Depletion events as crisis triggers |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `WATER_PER_PERSON_PER_HOUR` | 0.2 | 0.1-0.5 | Water depletes faster. More planetary runs needed. | Water lasts longer. Less pressure. |
| `FOOD_PER_PERSON_PER_HOUR` | 0.15 | 0.05-0.3 | Food depletes faster. | Food lasts longer. |
| `LIME_PER_SECTION_PER_HOUR` | 0.1 | 0.05-0.2 | Lime pressure increases. Sections shut down sooner. | Lime lasts longer. Less spatial pressure. |
| `LOW_THRESHOLD` | 0.3 (30%) | 0.2-0.5 | Rationing kicks in earlier. More time in scarcity. | Rationing delayed. Less drama. |
| `CRITICAL_THRESHOLD` | 0.1 (10%) | 0.05-0.2 | Crisis triggers later. More warning time. | Crisis triggers sooner. More urgent. |
| `CACHE_SP_MIN` | 2 | 1-5 | More Ship Parts per cache. Faster repairs. | Fewer parts. Tighter economy. |
| `CACHE_SP_MAX` | 8 | 3-15 | Larger cache rewards. | Smaller rewards. |
| `CACHE_BONUS_CHANCE` | 0.3 | 0.1-0.5 | More bonus resources in caches. | Fewer bonuses. |
| `RATIONING_MODIFIER` | 0.5 | 0.3-0.8 | Rationing saves more. | Rationing saves less. |
| `SECTION_SHUTDOWN_LIME_THRESHOLD` | 0.3 | 0.2-0.5 | Sections shut down earlier. | Later shutdown. More lime consumed before response. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Resource collected | Brief pickup animation, quantity floats up | Collection chime (varies by resource type) | High |
| Story item acquired | Special acquisition moment, item examined | Unique discovery tone, Eli reaction | High |
| Resource depleted | Kino Remote warning flash | Alarm tone | High |
| Rationing begins | Kino Remote amber indicator | Subtle warning tone | Medium |
| Sections shutting down (lime low) | Visible: lights dim, doors seal in affected sections | Mechanical sealing sounds, power-down hum | High |
| Salvage subsystem | Disassembly animation, parts extracted | Mechanical breakdown sounds | Medium |

## UI Requirements

| Information | Display Location | Update Trigger | Condition |
|-------------|-----------------|----------------|-----------|
| Resource quantities | Kino Remote inventory panel | On collection/consumption | Always available in Kino Remote |
| Scarcity warnings | Kino Remote main display | Resource crosses threshold | Resource at Low or Critical |
| Story item list | Kino Remote inventory panel | On acquisition | Always available in Kino Remote |
| Repair cost | Radial menu label on subsystems | Player approaches repairable | Within interaction range |
| Section shutdown status | Kino Remote map | Lime threshold crossed | Sections sealed due to lime scarcity |

No floating HUD for resources. All information accessed through the Kino Remote,
consistent with diegetic UI philosophy.

## Acceptance Criteria

- [ ] **Resource tracking**: All resource types correctly track quantities. Add and consume work. Values never go negative.
- [ ] **Story items**: Unique items acquired, tracked as flags. Cannot duplicate. Correctly gate story progression.
- [ ] **Consumption**: Water, Food, Lime consumed over time at correct rates. Rationing halves consumption when Low.
- [ ] **Lime scarcity response**: When lime drops below threshold, non-essential sections automatically shut down. Reopened when lime resupplied.
- [ ] **Depletion events**: `resource:depleted` fires when any resource hits 0. Narrative consequences trigger.
- [ ] **Ship Parts for repairs**: Ship State can check availability and consume Ship Parts. Insufficient resources prevents repair.
- [ ] **Cache looting**: Supply caches grant correct resource amounts. Caches persist as empty after looting.
- [ ] **New resource types**: Unlocking a new resource type adds it to Kino Remote display at 0 quantity.
- [ ] **Salvage**: Subsystem salvage grants Ship Parts, permanently destroys the subsystem. Confirmation dialog prevents accidents.
- [ ] **Serialization**: `serialize()`/`deserialize()` correctly preserves all resource counts and story item IDs.
- [ ] **Performance**: Resource operations (add/consume/check) are O(1). Consumption tick runs once per game-minute, not per-frame.
- [ ] **All tuning values externalized**: Consumption rates, thresholds, cache amounts from config.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Exact planetary scavenging yields per resource type — how much per planet run? | Stargate & Planetary Runs GDD | When that system is designed | — |
| Should crew count change over the story (deaths, rescues, departures)? Affects consumption. | Episode Narrative GDD | Before S1 story writing | — |
| How many story items total across all seasons? Each needs unique art, narrative, and integration. | Creative Director | Content planning | — |
| Should salvage be available for all subsystem types, or only specific ones? | Game Designer | During prototype | — |
| Exact lime consumption rate that creates drama without frustration — needs playtesting. | Systems Designer | During prototype | — |
