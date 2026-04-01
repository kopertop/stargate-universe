# Stargate & Planetary Runs

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-31
> **Implements Pillar**: Pillar 2 (Survival with Purpose), Pillar 3 (Earned Discovery)

## Overview

The Stargate & Planetary Runs system is the mission orchestrator for off-ship
gameplay. When Destiny drops out of FTL near a star system, this system determines
which planets are reachable, what resources and hazards each offers, and manages
the full gate-to-planet-to-ship lifecycle. It coordinates existing systems rather
than reimplementing their mechanics: the Timer system runs the departure countdown,
the Resource system handles collection, the Player Controller governs movement on
the planet surface, and ggez Scene Management loads and unloads planet environments.

The system owns three things: **planet data** (a catalog of planet definitions with
resource tables, hazard types, environment configs, and narrative hooks), **gate
flow** (the state machine from FTL drop → dial → wormhole → planet → return), and
**mission structure** (objectives, time pressure, and the triage decisions the
player faces on each run). Planets are authored as ggez scenes with resource nodes
and hazard zones placed in the World Editor. The Stargate system loads these scenes,
configures the Timer with the appropriate countdown, and lets the player loose.

The player's core decision on every run is triage: "I have 15 minutes. Do I grab
the lime we desperately need, explore that Ancient ruin, or try to do both?" This
system exists to make that decision meaningful — every planet offers more than
the player can do in the time available.

## Player Fantasy

The Stargate & Planetary Runs system serves the fantasy of **stepping through a
portal onto an alien world** — and that fantasy evolves as Eli grows.

**Season 1 — First steps on alien ground**: Some runs are desperate supply raids —
the timer is tight, the air might be toxic, and you're racing to find water before
Destiny jumps without you. But not every run is a crisis. Sometimes the gate opens
onto a beautiful, quiet world with a generous window, and the run becomes a genuine
expedition — exploring alien terrain, discovering strange life, stumbling onto
Ancient ruins. The mix of desperate and wonderful is what makes Season 1 exciting:
you never know what's on the other side of the gate. When you make it back with
supplies in hand, the relief (or satisfaction) is earned.

**Season 2 — Planned expeditions**: The crew has a rhythm now. You can read the
Kino Remote's planet scans, you know what to prioritize, and you've done this
enough times to plan your route. Runs feel like expeditions — still timed, still
surprising, but you're making *choices* instead of panicking. "The Ancient ruin
is 400 meters east, but lime deposits are south. I have 18 minutes. I can do
both if I sprint." The excitement shifts from survival to optimization.

**Season 3+ — Confident operations**: Eli knows what he's doing. Planet runs are
still timed, but the tension comes from *what you find*, not whether you'll make
it back. Bigger discoveries, stranger worlds, narrative surprises. The gate isn't
a lifeline anymore — it's a doorway to possibility. But the universe still has
surprises, and overconfidence is its own hazard.

This serves **Pillar 2 (Survival with Purpose)**: planet runs are where resources
come from, and scarcity makes every run matter. It serves **Pillar 3 (Earned
Discovery)**: alien worlds reward exploration with Ancient ruins, strange life,
and clues to Destiny's mission — but only if you budget your time well.

## Detailed Design

### Core Rules

1. **FTL drop cycle**: Destiny periodically drops out of FTL near star systems.
   The drop creates a **gate window** — a period during which the Stargate can
   connect to nearby planets. The gate window duration varies by story (10-20
   minutes real-time, configured per episode). When the window expires, Destiny
   jumps back to FTL. This cycle is managed by two timers: a `Countdown` for the
   gate window and a `Cooldown` for the FTL drive recharge.

2. **Planet catalog**: Each reachable planet is defined as a `PlanetDefinition`:
   - `id`: string (e.g., `"planet-s1e03-desert"`)
   - `name`: string (Ancient designation, becomes readable with knowledge tiers)
   - `sceneId`: string (ggez scene to load)
   - `tier`: enum — `Safe`, `Moderate`, `Dangerous`, `Hostile`
   - `atmosphere`: enum — `Breathable`, `Thin`, `Toxic`, `None`
   - `environment`: enum — `Temperate`, `Desert`, `Ice`, `Jungle`, `Volcanic`, `Ruins`
   - `resources`: array of `{ type: ResourceType, nodes: number, yieldPerNode: [min, max] }`
   - `hazards`: array of `{ type: HazardType, severity: float, zones: string[] }`
   - `wildlife`: array of `{ species: string, behavior: "passive" | "territorial" | "aggressive", count: number }`
   - `hostiles`: optional `{ faction: string, count: number, behavior: string }` (Lucian Alliance, drones, etc.)
   - `pointsOfInterest`: array of `{ id: string, type: "ancient-ruin" | "cache" | "story" | "lore", description: string }`
   - `timerDuration`: float (gate window override for this planet, in game-seconds)
   - `narrativeHooks`: array of episode event IDs triggered by visiting

3. **Planet selection (evolving)**:
   - **Season 1 (early)**: Destiny's sensors are limited. One planet per FTL
     drop. No choice — gate to it or skip. Kino Remote shows minimal data
     (atmosphere only).
   - **Season 1 (late)**: Sensors improve. Kino Remote shows 1-2 planets with
     basic scans (atmosphere + dominant resource type).
   - **Season 2+**: Full sensor capability. 2-3 reachable planets per drop.
     Kino Remote shows detailed scans (resources, hazard level, atmosphere,
     points of interest). Player chooses which to visit.
   - Planet selection is read from the Kino Remote. The player picks, then
     approaches the Stargate to dial.

4. **Gate activation flow**:
   1. Player approaches the Stargate on Destiny
   2. Radial menu shows "Dial [planet name]" (or planet list if multiple)
   3. Player selects → dial sequence begins (inner ring spins, chevrons lock)
   4. Wormhole establishes → event horizon appears
   5. Player walks through the event horizon → scene transition begins
   6. Departure countdown timer starts

5. **Scene transition**: Walking through the active gate triggers a scene load:
   - Current scene (gate room) is suspended, not unloaded
   - Planet scene loads via ggez Scene Management
   - Player spawns at the planet-side gate with the same controller/camera
   - The planet-side Stargate is active (event horizon visible) — it's the way home
   - Gate room scene stays in memory for fast return

6. **Planet gameplay**: On the planet surface, gameplay uses existing systems:
   - **Movement**: Player Controller (identical parameters to ship)
   - **Camera**: Same third-person rig, auto-framing for POIs
   - **Resource nodes**: Major resources (lime deposits, water sources, mineral
     veins) are specific interactable objects — walk up, radial menu "Gather",
     each yields a defined amount. Nodes are consumed after gathering (visual
     change: depleted).
   - **Environmental collection**: Minor resources (edible plants, scattered
     parts) auto-collect when the player walks within range. Small pickup
     feedback (quantity float, chime).
   - **Points of interest**: Ancient ruins, data caches, story objects. Interact
     via radial menu. May yield story items, lore, or Ancient Components.
   - **Hazards**: Environmental hazards affect specific zones (toxic gas pockets,
     extreme heat areas, unstable terrain). Visual/audio warnings at zone edges.
     Entering a hazard zone triggers effects (screen tint, damage over time to
     a "health" bar that triggers auto-retreat, not death).
   - **Wildlife**: Creatures with behavior AI — passive (flee on approach),
     territorial (warn then attack if player stays), aggressive (pursue).
     No combat system — player avoids, flees, or uses environment. Contact
     with aggressive wildlife triggers injury (limp, slowed) and auto-retreat,
     not death.
   - **Hostiles**: Story-scripted encounters only (not random). Lucian Alliance
     patrols, drone scouts. Handled by Episode Narrative triggering specific
     encounter scripts. This system provides the planet environment; episodes
     provide the hostiles.

7. **Timer and warnings**: The departure countdown (created via Timer system) shows
   on the Kino Remote timer screen and on the gate-room doorway displays (FTL
   timer). Warning thresholds:
   - First warning: 2 minutes remaining — Kino Remote alert, Eli comment
   - Final warning: 30 seconds remaining — alarm tone, urgent Eli dialogue,
     screen border flash
   - Expiry: auto-return through the gate (see rule 8)

8. **Return to ship**: Two return paths:
   - **Voluntary return**: Walk back to the planet-side Stargate, interact to
     return. Scene transitions back to Destiny gate room. Resources collected
     are confirmed.
   - **Auto-return (timer expired)**: When the departure timer expires, a brief
     cinematic plays (Eli running to the gate, diving through). Scene transitions
     to Destiny. All resources collected up to that point are kept. No penalty
     beyond lost time — no death, no dropped items.
   - After return, the gate shuts down and Destiny jumps to FTL. The FTL
     cooldown timer begins.

9. **Post-run summary**: After returning, a brief diegetic summary shows on the
   Kino Remote: resources gathered, POIs discovered, time remaining when
   returned. No score screen — just information through the in-world UI.

### States and Transitions

| State | Entry Condition | Exit Conditions | Behavior |
|-------|----------------|-----------------|----------|
| **In FTL** | Destiny jumps to FTL (default state) | FTL cooldown timer reaches Ready → FTL Drop | No gate access. FTL cooldown timer visible on doorway displays. Primary gameplay during FTL is ship-side: explore Destiny, repair systems, crew interactions, episode events. FTL time is never dead time. Player can time-skip to next drop if desired. |
| **FTL Drop** | FTL cooldown expires, Destiny exits near a star system | Gate window timer expires → Jump to FTL. Player dials gate → Dialing. Player skips (if no crisis) → In FTL. | Planet(s) become available on Kino Remote. Gate window countdown begins. Ship events may trigger (narrative). |
| **Dialing** | Player selects "Dial" on Stargate radial menu | Dial sequence completes → Wormhole Active. Player cancels → FTL Drop. | Inner ring spins, chevrons lock sequentially. ~5 seconds. Non-interruptible once started (except cancel). |
| **Wormhole Active** | Dial sequence completes, all chevrons locked | Player walks through → On Planet. Gate window timer expires → Wormhole closes, Jump to FTL. | Event horizon visible. Gate window timer continues ticking. Player can walk through or choose not to go. |
| **On Planet** | Player walks through the active wormhole | Player walks back through planet gate → Returning. Departure timer expires → Auto-Return. | Full planet gameplay. Timer counting down. Resources gathered add to ship pool immediately. |
| **Returning** | Player interacts with planet-side gate, or timer expires (auto-return) | Scene transition completes → Post-Run. | Brief transition (voluntary) or cinematic (auto-return). Gate shuts down. |
| **Post-Run** | Return to Destiny complete | Summary dismissed → In FTL (Destiny jumps) | Kino Remote shows run summary. Destiny prepares for FTL jump. FTL cooldown begins. |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Timer & Pressure** | Outbound (creator) | Creates: gate window countdown (`timer:planet:expired`), FTL cooldown (`timer:ftl:ready`). Configures warning thresholds per planet. Subscribes to `timer:planet:warning` and `timer:planet:expired` to trigger warnings and auto-return. |
| **Resource & Inventory** | Outbound (source) | Calls `addResource(type, amount)` when player gathers from nodes or auto-collects. Planet definitions specify resource tables. Primary source for Water, Food, Lime, and specialized resources. |
| **Player Controller** | Reads | Uses same controller on planets. Radial menu shows planet-specific actions ("Gather", "Examine", "Dial"). Subscribes to `player:interact` for resource node and gate interactions. |
| **Camera System** | Reads | Same third-person rig. Auto-framing registers planet POIs. Cinematic mode for auto-return sequence. |
| **ggez Scene Management** | Outbound (loader) | Loads planet scenes on gate entry, suspends/resumes gate room scene. Manages planet scene lifecycle. |
| **Event Bus** | Bidirectional | Publishes: `gate:dial:started`, `gate:activated`, `gate:closed`, `planet:entered`, `planet:returned`, `planet:resource:gathered`, `planet:poi:discovered`. Subscribes to timer events, player interactions, episode triggers. |
| **Ship State** | Reads | Reads sensor condition to determine planet scan detail level (planet selection evolution). Reads FTL drive condition for cooldown duration. |
| **Episode Narrative** *(undesigned)* | Bidirectional | Episodes specify which planets appear per FTL drop. Episodes can trigger hostile encounters on planets. Planet discoveries can trigger narrative events. `narrativeHooks` in planet data. |
| **Kino Remote** *(undesigned)* | Outbound (read) | Provides planet scan data for selection screen. Provides run summary data. Planet timer visible on timer screen. |
| **Ship Exploration** | Reads | Gate room must be discovered/accessible before gate can be used. |
| **Crew Dialogue & Choice** *(undesigned)* | Outbound (context) | Crew may comment on planet scans, suggest priorities. Post-run dialogue reacts to what was gathered (or missed). |
| **Save/Load** *(undesigned)* | Outbound (serialization) | Serializes current gate state, active planet data, and on-planet progress. Must handle save/load while on a planet. |

**Provisional contracts:**
- Episode Narrative: planet assignment per episode and hostile encounter scripting TBD
- Kino Remote: planet selection UI and scan display format TBD

## Formulas

### Atmosphere Access Requirements

| Atmosphere | Access Requirement | Health Effect | Timer Impact |
|------------|-------------------|---------------|-------------|
| `Breathable` | None — walk freely | No drain | None |
| `Thin` | None — but health drains slowly | 2 HP/min drain | None |
| `Toxic` | Requires suit (story unlock) | 10 HP/min without suit, 0 with | Suit has limited air: creates a secondary timer |
| `None` | Requires suit (story unlock) | Instant retreat without suit | Suit air timer (shorter than gate window) |

- **Suit availability**: Spacesuits are a **story item** unlocked through narrative
  progression. Before unlocking, Toxic and None planets show "Cannot gate —
  no atmospheric protection" on Kino Remote. The scan still shows what resources
  are there, creating desire for the unlock.
- **Suit air timer**: When suited, a secondary `Countdown` timer tracks remaining
  air. This is shorter than the gate window (configurable per planet), adding
  another triage layer: "I have 15 minutes on the gate window but only 8 minutes
  of air."

### Resource Node Yield

```
yield = random(yieldMin, yieldMax) * planet_tier_modifier
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `yieldMin` / `yieldMax` | int | 1-20 | planet config | Base yield range per node |
| `planet_tier_modifier` | float | 0.5-1.5 | planet tier | Safe=1.0, Moderate=1.2, Dangerous=1.4, Hostile=1.5 |

Higher-tier (more dangerous) planets reward more resources per node — risk/reward.

### Environmental Auto-Collection Rate

```
collection_per_second = BASE_COLLECTION_RATE * resource_density
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `BASE_COLLECTION_RATE` | float | 0.1-0.5 | config | Units per second while in a collection zone |
| `resource_density` | float | 0.5-2.0 | zone config | How rich this area is |

### Gate Window Duration

```
window_seconds = planet.timerDuration ?? DEFAULT_GATE_WINDOW
```

No formula — purely data-driven per planet/episode. Default is 900s (15 min).

### FTL Cooldown Duration

```
cooldown_seconds = BASE_FTL_COOLDOWN * (1 / ftl_drive_condition)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `BASE_FTL_COOLDOWN` | float | 1800s (30 min) | config | Cooldown at 100% FTL condition |
| `ftl_drive_condition` | float | 0.2-1.0 | Ship State | Lower condition = longer cooldown |

### Hazard Damage Rate

```
health_drain_per_second = hazard_severity * HAZARD_BASE_DAMAGE
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `hazard_severity` | float | 0.1-1.0 | zone config | How dangerous this hazard zone is |
| `HAZARD_BASE_DAMAGE` | float | 5-15 | config | Base health drain per second |

Player has 100 "health" on planets. At 0, auto-retreat triggers (not death).
Health regenerates outside hazard zones at `HEALTH_REGEN_RATE` (default 5 HP/s).

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Player doesn't go through the gate** | Gate window expires, Destiny jumps. Resources on that planet are lost. No penalty. | Player choice — maybe ship repairs were more urgent. |
| **Timer expires while player is far from gate** | Auto-return cinematic: Eli sprints to gate regardless of distance. Brief fade-to-black, respawn on Destiny. All gathered resources kept. | No death. No punishment for poor time management beyond "didn't get everything." |
| **Player walks through gate during dial sequence** | Nothing happens — event horizon isn't active yet. Player bounces off the ring. | Can't enter a wormhole that doesn't exist. |
| **Planet scene fails to load** | Gate activation aborts gracefully. Error logged. Kino Remote shows "Unable to establish connection." Player stays on Destiny. | Network/asset loading failure shouldn't crash the game. |
| **Player tries to gate without suit to Toxic/None planet** | Gate dial is blocked. Radial menu shows "Requires atmospheric protection." Kino Remote shows the planet's resources as motivation to find suits. | Progression gate — creates desire for story advancement. |
| **Suit air runs out on planet** | Auto-return cinematic triggers (same as departure timer expiry). Resources kept. | No death — air depletion is the same as time running out. |
| **Both departure timer and suit air expire same frame** | Departure timer takes precedence (same behavior — auto-return). | Consistent: auto-return is auto-return. |
| **Save while on a planet** | Save captures: current planet ID, player position on planet, gathered resources so far, remaining timer, remaining suit air. On load, player resumes on the planet at saved position with timers restored. | Save/load must work mid-run. |
| **FTL drive at 0% condition** | Cooldown becomes extremely long (effectively stuck at current position). Episode system should trigger a narrative event (crisis). | Broken FTL = major crisis, not a soft lock. |
| **All resource nodes on a planet already gathered** | Nodes show as depleted (visual change). Player can still explore POIs, but no more resources to collect. | Prevents farming — each planet run is a one-shot opportunity. |
| **Player returns through gate with 0 resources gathered** | No penalty. Post-run summary shows "0 gathered." Crew dialogue may react ("That was a waste of time."). | Player chose to explore instead of scavenge — valid choice. |
| **Hostile encounter while gathering** | Gathering interaction is interrupted. Player must deal with the threat (flee/hide) then resume gathering. Resource node is NOT consumed by the interruption. | Fair — don't waste a node because an alien showed up mid-gather. |
| **Multiple planets available, player dials one then wants to switch** | Cannot switch once wormhole is active. Must wait for gate to close (return or let window expire) then re-dial. In practice, one trip per FTL drop. | Consistent with Stargate physics — one connection at a time. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Player Controller | Hard | Movement, interaction, radial menu on planets |
| Camera System | Hard | Third-person camera, cinematic mode for auto-return |
| Timer & Pressure | Hard | Gate window countdown, FTL cooldown, suit air timer |
| Resource & Inventory | Hard | `addResource()` for gathered resources, story items for suit unlock |
| Event Bus | Hard | All gate/planet events, timer subscriptions |
| ggez Scene Mgmt | Hard | Planet scene loading/unloading/suspension |
| Ship State | Soft | Sensor condition for scan detail, FTL condition for cooldown |
| Ship Exploration | Soft | Gate room must be accessible |
| Save/Load (interface) | Hard (contract) | Serialize gate state + on-planet progress |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Episode Narrative | Hard | Planet assignment per episode, narrative hooks, hostile encounters |
| Kino Remote | Hard | Planet scan data, selection UI, run summary, planet timer |
| Crew Dialogue & Choice | Soft | Planet context for dialogue (what's available, what was gathered) |
| Audio & Ambience | Soft | Planet environment type for ambient audio |
| Ship Atmosphere & Lighting | Soft | Gate activation state for gate room lighting effects |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `DEFAULT_GATE_WINDOW` | 900s (15 min) | 300-1800s | More time per run. Less pressure, more exploration. | Tighter runs. More triage pressure. |
| `BASE_FTL_COOLDOWN` | 1800s (30 min) | 600-3600s | Longer between planet opportunities. More ship time. | Faster cycle. More planet time overall. |
| `PLANET_TIER_MODIFIER_SAFE` | 1.0 | 0.5-1.5 | Safe planets more rewarding. Less incentive for risk. | Safe planets less rewarding. |
| `PLANET_TIER_MODIFIER_HOSTILE` | 1.5 | 1.0-2.5 | Dangerous planets much more rewarding. Stronger risk/reward. | Less difference between tiers. |
| `BASE_COLLECTION_RATE` | 0.2/s | 0.05-0.5 | Auto-collection faster. Minor resources abundant. | Slower collection. Player must spend more time in zones. |
| `HAZARD_BASE_DAMAGE` | 10/s | 5-20 | Hazard zones more deadly. Less time to explore them. | More forgiving. Player can linger in hazards. |
| `HEALTH_REGEN_RATE` | 5/s | 2-15 | Faster recovery. Hazards feel like speed bumps. | Slower recovery. Hazards have lasting impact on the run. |
| `PLAYER_PLANET_HEALTH` | 100 | 50-200 | More buffer in hazards. | Less margin. Hazards more impactful. |
| `SUIT_AIR_DURATION` | 480s (8 min) | 180-600s | More time on hostile atmospheres. | Tighter air constraint. Additional triage pressure. |
| `DIAL_SEQUENCE_DURATION` | 5s | 3-8s | Slower, more cinematic dial. | Snappier gate activation. |
| `MAX_PLANETS_PER_DROP` | 3 | 1-5 | More choice. Harder to pick. | Less choice. Simpler decision. |
| `SENSOR_DETAIL_THRESHOLD` | 0.5 | 0.2-0.8 | Sensors need higher condition for full scans. | Full scans available sooner. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| FTL drop (Destiny exits FTL) | Ship shudder, star streaks decelerate, viewport reveals star system | FTL deceleration rumble → silence → ambient space | High |
| Gate dial sequence | Inner ring spins, chevrons lock with flash, energy builds | Mechanical grinding, chevron lock clunks (iconic SGU sounds), energy crescendo | High |
| Wormhole establish (kawoosh) | Event horizon bursts outward then settles to shimmering pool | Explosive whoosh → settle to gentle ripple hum | High |
| Walk through gate | Screen whites out briefly, ambient crossfade to planet audio | Wormhole transit whoosh → immediate planet ambience | High |
| Planet first step | Wide vista reveal, sky color, terrain stretching out | Planet-specific ambient (wind, insects, volcanic rumble, silence) | High |
| Resource node gathered | Node depletes visually (wilts, crumbles, dims), quantity floats up | Collection chime (varies by resource), satisfying "got it" | High |
| Auto-collection pickup | Small sparkle at player's feet, tiny quantity number | Soft pickup plink | Low |
| Timer warning (2 min) | Kino Remote amber flash, subtle screen border pulse | Warning chime, Eli: "Two minutes!" | High |
| Timer final warning (30s) | Screen border flashes red, urgent visual overlay | Alarm tone, Eli: "We gotta go NOW!" | High |
| Auto-return cinematic | Camera pulls to cinematic, Eli sprints, dives through gate | Running footsteps, heavy breathing, gate transit whoosh | High |
| Hazard zone entry | Screen tint (green for toxic, red for heat, blue for cold), edge vignette | Environmental warning sound, breathing changes | Medium |
| Wildlife encounter | Creature animations, territorial warning displays | Creature sounds (growl, screech, hiss), Eli reaction | Medium |
| Return to Destiny | Gate room re-establishes, gate shuts down | Gate shutdown hum, Destiny ambient returns | High |

**Planet environment variety**: Each environment type (Temperate, Desert, Ice, Jungle,
Volcanic, Ruins) has a distinct skybox, ambient lighting, fog color/density, ground
material, and audio bed. This is the highest content-production cost in the game.

## UI Requirements

| Information | Display Location | Update Trigger | Condition |
|-------------|-----------------|----------------|-----------|
| Available planets | Kino Remote — Planet Scan screen | On FTL drop | During FTL Drop state |
| Planet scan details | Kino Remote — Planet Scan screen | On planet selection | Detail level depends on sensor condition |
| Departure countdown | Kino Remote timer screen + doorway displays | Each tick | While on planet or wormhole active |
| Suit air remaining | Kino Remote timer screen (secondary timer) | Each tick | On Toxic/None atmosphere planets with suit |
| Resources gathered (running total) | Kino Remote inventory panel | On each gather | While on planet |
| Post-run summary | Kino Remote — Summary screen | On return to Destiny | After planet return |
| "Requires atmospheric protection" | Kino Remote — Planet Scan screen | On planet selection | Toxic/None planets without suit |
| Hazard warning | Screen-edge visual overlay (non-diegetic) | On entering hazard zone | In hazard zone |

No floating HUD for planet gameplay. All information through Kino Remote except
hazard zone warnings (screen-edge tint) which are non-diegetic for safety.

## Acceptance Criteria

- [ ] **FTL cycle**: Destiny drops out of FTL, gate window opens, planets appear on Kino Remote. After window expires, Destiny jumps back. FTL cooldown begins.
- [ ] **Gate activation**: Player approaches gate, radial menu shows "Dial". Dial sequence plays (ring spins, chevrons lock). Wormhole establishes.
- [ ] **Scene transition**: Walking through active wormhole loads planet scene. Player spawns at planet-side gate. Gate room scene stays in memory.
- [ ] **Planet movement**: Player Controller works identically on planet surface. Camera, interaction, radial menu all function.
- [ ] **Resource nodes**: Interacting with a resource node adds correct amount to ship pool. Node shows depleted state after gathering.
- [ ] **Auto-collection**: Walking through a minor resource zone auto-collects at configured rate. Pickup feedback shown.
- [ ] **Timer integration**: Departure countdown visible on Kino Remote. Warnings fire at thresholds (2 min, 30s). Expiry triggers auto-return.
- [ ] **Auto-return**: Timer expiry plays brief cinematic, transitions to Destiny. All gathered resources kept. No death.
- [ ] **Voluntary return**: Walking through planet-side gate returns to Destiny. Resources confirmed.
- [ ] **Post-run summary**: Kino Remote shows resources gathered, POIs discovered, time remaining.
- [ ] **Atmosphere gating**: Toxic/None planets blocked without suit. Kino Remote shows requirement.
- [ ] **Suit air timer**: Secondary countdown on suited planets. Expiry triggers auto-return.
- [ ] **Planet selection evolution**: S1 early: 1 planet, minimal scan. S2+: 2-3 planets, full scans. Sensor condition affects detail.
- [ ] **Hazard zones**: Environmental hazards drain health in affected areas. Auto-retreat at 0 HP. Health regenerates outside.
- [ ] **Wildlife**: Passive creatures flee, territorial warn, aggressive pursue. Contact causes injury (limp). No death.
- [ ] **Hostiles**: Story-scripted only, triggered by Episode system. Not generated by this system.
- [ ] **Save/load on planet**: Can save and load while on a planet. Position, timer, gathered resources, and suit air all restored.
- [ ] **Performance**: Planet scene loads within 3 seconds. Scene transition (gate → planet) under 2 seconds with loading indicator.
- [ ] **All tuning values externalized**: Timer durations, yields, damage rates, tier modifiers from config.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| How many unique planet scenes needed for MVP / Vertical Slice / Alpha? Each needs level design + assets. | Level Designer + Producer | Before content planning | — |
| Should planets be fully hand-crafted or use modular terrain + procedural placement of resource nodes? | Technical Director | Before planet pipeline design | — |
| How does the Kino drone interact with planet exploration? Can you deploy a Kino to scout ahead on a planet? | Game Designer | Before Kino Drone GDD | — |
| Exact spacesuit unlock timing in the story — which episode? Too early removes a progression gate, too late locks out content. | Creative Director | Before S1 story outline | — |
| Should the player be able to return to a previously visited planet (if Destiny passes near it again), or is every planet one-shot? | Game Designer | Before Episode Narrative GDD | — |
| How do hostile encounters (Lucian Alliance, drones) work mechanically? Need at minimum a stealth/flee system. Separate GDD? | Game Designer | Before hostile encounters are implemented | Likely a sub-system GDD |
| What's the right balance between "exploring feels rewarding" and "timer creates pressure"? Core tension needs playtesting. | Systems Designer | During prototype | — |
| Can crew members accompany Eli on planet runs? Would add dialogue but massively increase complexity. | Creative Director | Before S1 design | SGU show has team runs — likely yes |
