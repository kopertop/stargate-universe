# Ship Building Mode

> **Status**: Designed (Phase 1 implemented — module choice via room consoles)
> **Author**: User + Claude
> **Last Updated**: 2026-07-05
> **Implements Pillar**: Pillar 1 (The Ship IS the World), Pillar 3 (Earned Discovery)
> **Sibling systems**: `ship-state-system.md` (section condition model), `ship-exploration.md` (discovery), `resource-inventory.md` (costs)

## Overview

Ship Building Mode turns Destiny from a place you *survive* into a place you
*restore*. Every non-corridor room carries persistent state — **structural
damage %** (the inverse of ship-state-system's condition: `condition = 100 −
damage`), **shield strength %**, and an **installed module** — and every such
room hosts a dedicated Room Systems console. Through it the player chooses
what to build in that room: hydroponics units to grow food, sleeping quarters,
research labs, machine shops, infirmary wards, storage depots.

Damaged rooms refuse construction. Rooms above the damage threshold must be
repaired first — by hand early on, and later by dispatching the **repair
robot** (a findable Ancient maintenance automaton) from the control room.
Repairing rooms expands the usable ship: sealed sections become quarters
wings, breached bays become workshops. Building is the reward loop that makes
exploration and repair matter.

This GDD covers the full feature arc. **Phase 1 is implemented** on the merged
deck scenes (`scenes/deck.tscn`): per-room state registry (`ShipState`
autoload), room consoles with a module catalog (`data/room_modules.json`),
damage-gated construction, module placeholder visuals, and remote door
control from the control interface room. Phases 2+ are design targets.

## Player Fantasy

**"This ship is mine to bring back to life."** The Ancients launched Destiny
unmanned; nobody ever furnished it. Every hydroponics bay the player brings
online, every dark breached compartment turned into a lit, humming machine
shop, is the first purposeful habitation in the ship's million-year life. The
fantasy is Subnautica-base-building meets FTL-ship-management, diegetically
grounded: you build through Ancient consoles, not a floating god-menu.

## Detailed Design

### Data Model

**`ShipState` autoload (`scripts/ship_state.gd`) — implemented.** One registry
per kind of thing (collection-fork policy):

```
_rooms: room_id -> {
    damage_pct: float 0..100      # structural damage (100 = destroyed)
    shield_pct: float 0..100      # per-room defensive shield strength
    module: String                # installed module id ("" = none)
}
_doors: door_key -> { open: bool, locked: bool }   # door_key = sorted "a|b"
```

Registered with SaveManager as `"ship_state"`; serialize/deserialize
round-trips both registries plus the merged-deck routing flag. Story-damaged
sections seed their state (`SEED_STATE_BY_ROOM`): the breached shuttle dock
starts at 65 % damage / 20 % shield, the sealed north section at 85 % / 0 %.

**Module catalog (`data/room_modules.json`) — implemented.** Per module:

| Field | Meaning |
|---|---|
| `id`, `name`, `description` | identity + console copy |
| `accent_template` | RoomBuilder accent set used as the built visual |
| `allowed_types` | room types that accept it (empty = any buildable room) |
| `provides` | fiction tags → later feed real systems (food, research, …) |
| `power_cost` | reserved for ship-state power integration (Phase 3) |
| `build_cost` | **implemented** — charged from the shared Inventory pool (`parts`) by `ShipState.build_module`; insufficient stock surfaces in `build_blocker` |

Buildable = any room whose type is not `corridor` / `elevator` / `gate_room`,
excluding the control interface room (it is the bridge).

### Core Rules

1. **One module per room.** Building replaces nothing silently; the console
   shows the installed module and offers *Dismantle* explicitly.
2. **Damage gates construction.** `damage_pct > 25` (BUILD_DAMAGE_THRESHOLD)
   → build refused with a repair pointer. No partial builds.
3. **Repair is one entry point.** `ShipState.repair_room(room_id, amount)` —
   the player's hand-repairs, the repair robot, and story events all call the
   same API, so the build gate can't fork.
4. **Doors are state, not scenery.** Every door between merged rooms persists
   open/closed/locked in `ShipState._doors`; the control-room console and the
   physical door interact through the same registry (single writer path).
5. **Shield strength is per-room.** Drains under exterior events (Phase 3);
   at 0 % an exterior hit converts directly into structural damage. Displayed
   now, simulated later.

### Phases

**Phase 1 — Choose what to build (IMPLEMENTED)**
- Room Systems console in every buildable room on the merged decks.
- Build panel: damage/shield readout, module catalog, damage gating,
  dismantle. Built modules re-dress the room with the module's accent set.
- Control-room consoles: ship-wide door open/close/lock + room status list.
- Save/load round-trip of all of it.

**Phase 2 — Costs and construction time** *(costs implemented; timers ahead)*
- ✅ `build_cost` (Ship Parts via resource-inventory) is checked and spent;
  insufficient parts → blocked Build with cost shown (`ShipState.build_cost` /
  `build_blocker` / `build_module`; tests/smoke/build_economy.gd).
- ✅ Hand-repair stopgap for Phase 3: `ShipState.repair_room_with_parts` spends
  1 × Ship Parts per 25 % structural damage from the room's build panel. NOTE
  the seam: the RepairRobot autoload (issue #131) already ticks parts-priced
  repairs against ProceduralShip room CONDITIONS; this hand spend covers the
  ShipState deck-registry damage that gates module builds. Unify when the
  robot learns to service ShipState rooms — same `repair_room` entry point.
- ✅ The FTL core loop (`FtlLoop` autoload, issue #130 — SHIP → JUMPING →
  PLANET, post-E1) supplies the loop pressure these costs bite against: mine
  parts on each planet window, spend them on repairs/builds during the SHIP leg.
- Builds take in-game hours (GameClock); the room shows scaffold visuals
  while under construction; a `module_built` toast fires on completion.
- Dismantling refunds 50 % of parts.

**Phase 3 — The repair robot**
- A findable repair robot (kino-room or sealed-section discovery beat).
- Dispatch from the control-room console: pick a damaged room → robot
  pathfinds there (ShipLayout BFS — same graph the Kino autopilot uses),
  repairs at `REPAIR_RATE` %/min, then idles. One robot at first; more
  found later for parallel repair queues.
- Robot is interruptible and visible in-world (it matters that you can walk
  past it working).
- Rooms repaired under the threshold unlock building; fully repaired rooms
  restore their shield regeneration (ties into ship-state power).

**Phase 4 — In-room build mode (free placement)**
- Entering *Build Mode* from the room console switches the camera to a
  top-down planning view of THAT room only (merged decks make this a camera
  move, not a scene change).
- Grid: 1 m cells, room-local. Placeable props per module (grow beds, bunks,
  benches, racks) with footprint validation against walls, doorway
  clearance (≥ 1.5 m per the doorway-clearance rule) and each other.
- Placement is preview-then-commit; committed props persist in `ShipState`
  as `props: Array[{id, cell, rot}]` per room (extends the room record).
- Gamepad parity: cursor snapping, bumper-cycle through prop catalog.

**Phase 5 — Systems payoff**
- `provides` tags become real: hydroponics feeds the food clock and helps
  CO2 scrubbing, machine shops convert salvage → Ship Parts on a timer,
  research labs unlock Ancient-database tiers, quarters raise rest quality.
- Power routing: modules draw `power_cost` from the section's conduit (ship
  state system DAG); underpowered modules run degraded.
- Crew assignment: named crew staff modules for output multipliers.

### States and Transitions (room)

| State | Condition | Console behaviour |
|---|---|---|
| **Wrecked** | damage > 25 % | Build disabled; shows repair pointer (robot) |
| **Ready** | damage ≤ 25 %, no module | Full catalog offered |
| **Under construction** | build committed, timer running (Phase 2) | Progress readout; cancel refunds |
| **Operational** | module installed | Status + dismantle |
| **Offline** | module installed, power starved (Phase 3+) | Warning + power routing hint |

### Interactions with Other Systems

| System | Direction | Contract |
|---|---|---|
| Ship State System | shared model | `condition = 100 − damage_pct`; the section condition bands (Failed/Critical/…) map onto the build gate. Power + conduits arrive in Phase 3. |
| Resource & Inventory | inbound | `build_cost` spends Ship Parts (Phase 2). Machine shop produces them (Phase 5). |
| Ship Exploration | inbound | Only discovered rooms appear in the handheld Kino list; the control console sees everything (it has the schematic). |
| Kino Remote | outbound | Map badges: wrench (wrecked), hammer (under construction), module glyph (operational). |
| Save/Load | bidirectional | All state lives in the `ship_state` system block. |
| Event Bus (undesigned) | outbound | `ship:room:built`, `ship:room:repaired`, `ship:door:changed` once the bus exists. |

## Formulas

```
condition            = 100 - damage_pct
build_allowed        = damage_pct <= 25 and module_compatible and (phase2: parts >= cost)
repair_robot_time    = damage_pct / REPAIR_RATE            # minutes, REPAIR_RATE default 5 %/min
exterior_hit(dmg)    = shield_pct > 0
                         ? shield_pct -= dmg * SHIELD_SOAK  # SHIELD_SOAK default 1.0
                         : damage_pct += dmg * HULL_FACTOR  # HULL_FACTOR default 0.6
module_output        = base_output * power_ratio * crew_multiplier   # Phase 5
```

## Edge Cases

| Case | Resolution |
|---|---|
| Build attempted in a corridor / elevator / gate room / bridge | `is_room_buildable` false → no console spawns there at all; API returns a blocker string. |
| Room damaged (event) while a module is installed | Module survives but goes **Offline** above the threshold; repairs bring it back. Never silently deleted. |
| Door locked while open | Registry slams it shut first (`set_door_locked`), then locks — a locked-open door cannot exist. |
| Console opens door into a vacuum section (Compromised, per ship-state GDD) | Phase 3: console refuses with the decompression warning; requires robot/EVA breach repair first. Today the sealed section door seeds LOCKED. |
| Repair robot's target room becomes inaccessible mid-route | Robot re-paths via ShipLayout BFS; if no path exists it returns to dock and the console reports the blockage. |
| Two writers change one door on the same frame (player + console) | Single registry writer path: last `set_door_open` wins; the door node only reacts to `door_changed`, never mutates its own state directly. |
| Save from mid-Build-Mode (Phase 4) | Preview (uncommitted) props are discarded; committed props persist. |

## Dependencies

- **Implemented on**: merged deck scenes (`scenes/deck.tscn` + `scripts/deck.gd`), `ShipState`, `RoomBuilder.build_merged` / `apply_template_accents`, door physical mode (`scripts/door.gd`).
- **Phase 2** needs: resource-inventory Ship Parts type; GameClock hooks.
- **Phase 3** needs: repair robot actor + BFS driver (Kino autopilot precedent), ship-state power/conduit model.
- **Phase 4** needs: top-down camera rig for View, prop footprint data per module.

## Tuning Knobs

| Knob | Default | Range | Effect |
|---|---|---|---|
| `BUILD_DAMAGE_THRESHOLD` | 25 % | 10–50 | Lower = repairs matter more before expansion. |
| `REPAIR_RATE` (robot) | 5 %/min | 2–15 | Pace of the reclaim loop. |
| `SHIELD_SOAK` | 1.0 | 0.5–2.0 | How fast exterior events strip room shields. |
| `HULL_FACTOR` | 0.6 | 0.3–1.0 | Damage bleed-through once shields are gone. |
| Module `build_cost` | 2–8 parts | — | Economy pressure per module tier. |
| Module `power_cost` | 0–4 | — | Phase 3 power budget pressure. |

## Visual/Audio Requirements

- Wrecked rooms: red alarm pool light + deterministic debris scatter
  (implemented as the deck damage overlay), sparking loop SFX (todo).
- Build commit: module accent set drops in (implemented); Phase 2 replaces
  the instant swap with scaffold → reveal.
- Room console: shared Ancient console silhouette (`attach_console_mesh`)
  + cyan "ROOM SYSTEMS" label (implemented).
- Doors: status lozenge — red locked / amber shut / green open (implemented);
  servo SFX placeholder pending a real blast-door sample.
- Repair robot: dome + manipulator silhouette, warm work-light, weld flicker.

## UI Requirements

- **Room build panel** (implemented): damage/shield/installed header, module
  list with descriptions, damage blocker banner, dismantle.
- **Ship systems panel** (implemented, control room only): Doors tab —
  open/close/lock every door; Rooms tab — damage/shield/module per room.
- Phase 2+: costs on Build buttons, construction progress bars, robot
  dispatch picker on the Rooms tab, Kino-map badges.

## Acceptance Criteria (Phase 1 — verified by tests/smoke/deck_boot.gd)

- [x] Every buildable room on a merged deck spawns a Room Systems console;
      corridors, elevators and the bridge do not.
- [x] Building is refused above 25 % damage with a repair-robot pointer, and
      allowed again once `repair_room` brings damage under the threshold.
- [x] Installed modules persist through serialize/deserialize and re-dress
      the room on load and on live build.
- [x] Door open/closed/locked state persists across deck rebuilds and saves;
      console lock slams a live open door shut.
- [x] The control-room console opens the ship-systems panel on decks and
      keeps its classic E1 behaviour in room.tscn scenes.

## Open Questions

1. Should dismantle exist at all pre-Phase-2 (free undo) or only with the
   50 % refund economy? (Current: free dismantle.)
2. Does the repair robot need its own GDD once Phase 3 starts? (Likely yes —
   pathing, interruption, and multi-robot queueing deserve edge-case tables.)
3. Merged-deck migration: when do the E1 story interactables (room.gd
   `_spawn_interactables`) move onto the decks so `--decks` becomes the
   default flow? Tracked as the headline follow-up in production notes.
4. Hydroponics module inside the native hydroponics room double-dresses the
   space (native accents + module accents). Cosmetic; resolve when Phase 4
   replaces accent-swaps with placed props.
