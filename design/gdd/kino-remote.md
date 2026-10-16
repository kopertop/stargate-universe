# Kino Remote (Diegetic Menu)

> **⚠️ Engine mapping updated — Three.js web era (2026-09-08 re-pivot)**
>
> The old scene management dependency has been replaced with Three.js scene
> management (`THREE.Scene` overlay rendering). The Three.js-era repo runs
> plain `src/*.js` + `index.html` (`build.sh`). The diegetic menu design
> (tabs, hold-to-open, ship-state/resource readouts) remains reference
> until implemented in the web codebase.

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-04-01
> **Implements Pillar**: Pillar 3 (Earned Discovery)

## Overview

The Kino Remote is Eli's primary tool aboard Destiny — an Ancient handheld device
whose original purpose is to control Kino drones (floating camera scouts), but
which proves capable of far more. Through the Kino Remote, Eli can access ship
status, manage power priorities, view resource inventories, scan planets, check
timers, and review crew information. It replaces traditional game menus with a
diegetic in-world interface: you're not opening a game menu, you're using an
Ancient tablet.

The Kino Remote has two modes: **quick-check** (tap to glance at the device — a
small in-world display appears while gameplay continues) and **full mode** (hold to
open a full-screen Ancient UI that pauses the game for deep management). Quick-check
shows the most urgent info: active timers, resource warnings, current objective.
Full mode provides tabbed screens: ship map, system status, power priorities,
resource inventory, timer list, planet scans, crew status, and Kino drone control.

The device's capabilities **expand through two paths**: Eli's growing Ancient
knowledge (labels become readable, hidden screens reveal themselves) and
**console integration** (connecting the Kino Remote to ship consoles around
Destiny unlocks new features and data feeds). Finding and activating a sensor
console might add a detailed sensor readout screen. Linking to the weapons
console adds targeting data. Each console connection is a progression moment —
the Kino Remote grows from a simple drone controller into Destiny's command
interface, one discovery at a time. It can even interface with alien technology
encountered on planets or aboard other ships.

## Player Fantasy

The Kino Remote serves the fantasy of **holding the key to an alien ship in your
hands.** Early on, it's a mysterious device that barely makes sense — screens
labeled in Ancient, most functions locked, just enough to control a flying camera.
But every console you connect to, every knowledge tier you gain, unlocks something
new. The moment a previously unreadable screen suddenly resolves into "POWER
DISTRIBUTION GRID" is a genuine thrill — you didn't just learn Ancient, you
gained *power* over the ship.

By mid-game, the Kino Remote feels like a smartphone you can't live without.
You check it reflexively — "What's our water level? How long until the next FTL
drop? What's the atmosphere on that planet?" By late game, it's a command
interface. You're managing Destiny's power grid, deploying Kino scouts ahead of
you, scanning alien tech, and the device that once confused you now feels like
an extension of your hand.

This serves **Pillar 3 (Earned Discovery)**: the Kino Remote doesn't hand you
information — you earn access to it through exploration and learning. It also
serves **Pillar 1 (The Ship IS the World)**: the device connects you to Destiny's
systems, making the ship feel real and responsive to your growing understanding.

## Detailed Design

### Core Rules

1. **Two access modes**:
   - **Quick-check** (tap Kino Remote key): Eli holds up the device. A small
     overlay appears showing urgent info (active timer, top scarcity warning,
     current objective). Gameplay continues — player can walk while glancing.
     Dismissed by releasing the key or after `QUICK_CHECK_TIMEOUT` seconds.
   - **Full mode** (hold Kino Remote key): Full-screen Ancient UI opens. The
     system publishes `game:paused` on the Event Bus (freezing all timers via
     Timer system's universal pause). Publishes `game:resumed` on close.
     Tabbed navigation between screens. Dismissed by pressing the key again
     or pressing Escape.

2. **Screen catalog**: The Kino Remote has the following screens, each unlocked
   through progression:

   | Screen | Data Source | Unlocked By | Available From |
   |--------|-----------|-------------|----------------|
   | **Kino Control** | Kino Drone system | Default (device's original purpose) | Episode 1 |
   | **Ship Map** | Ship State (sections) | Default (basic schematic) | Episode 1 |
   | **Timers** | Timer & Pressure | Default | Episode 1 |
   | **Resources** | Resource & Inventory | Default | Episode 1 |
   | **System Status** | Ship State (ship-wide systems) | Connecting to bridge console | Early S1 |
   | **Power Grid** | Ship State (power distribution) | Connecting to power console | Early-Mid S1 |
   | **Planet Scans** | Stargate & Planetary Runs | Connecting to sensor console | Mid S1 |
   | **Crew** | Crew Dialogue & Choice | Knowledge tier 2+ | Mid S1 |
   | **Objectives** | Episode Narrative | Default (basic) | Episode 1 |
   | *Future screens* | Various | Console connections + knowledge | S2+ |

3. **Console integration**: Ship consoles around Destiny are interactable objects.
   When Eli connects the Kino Remote to a console (radial menu "Link to Kino
   Remote"), a new screen or data feed unlocks permanently. Each console type
   adds specific capability:
   - Bridge main console → System Status overview
   - Power distribution console → Power Grid screen with priority management
   - Sensor array console → Planet Scan screen with detailed readouts
   - Communications console → (future) Earth contact features
   - Weapons console → (future) targeting data
   - Console connections are story items — tracked by the Resource & Inventory
     system as permanent unlocks.

4. **Ancient knowledge integration**: Text labels on the Kino Remote display in
   Ancient script. As Eli's knowledge tier (from Ship Exploration) increases:
   - **Tier 0**: Numbers readable (FTL countdown), icons recognizable, most text
     is Ancient glyphs
   - **Tier 1**: Basic labels translate (section names, resource names)
   - **Tier 2**: Detailed descriptions translate (system explanations, hazard warnings)
   - **Tier 3**: Full readability (advanced diagnostics, hidden data revealed)
   - **Tier 4-5**: Master-level (Ancient log access, encrypted data, hidden screens)
   - Untranslated text shows as stylized Ancient glyphs — not gibberish, but
     clearly a language the player can't yet read.

5. **Ship map**: The centerpiece screen. Displays Destiny's full schematic:
   - All sections shown (including unexplored — greyed out)
   - Color coding: green = powered/accessible, amber = low power, red flash =
     compromised, grey = unexplored
   - Selecting a section shows detail: atmosphere, power level, structural
     integrity, subsystem list
   - Objective waypoints displayed on the map (diegetic quest markers)
   - Labels in Ancient script → translate with knowledge tiers

6. **Power priority management**: On the Power Grid screen, the player can
   drag-to-reorder the 8 ship-wide system priorities. Changes take effect
   immediately (Ship State recomputes power distribution). Visual feedback
   shows power flow adjusting.

7. **Quick-check content**: The quick-check overlay shows (in priority order):
   - Most urgent active timer (countdown with label)
   - Highest-severity resource warning (if any at Low or Critical)
   - Current objective text (from Episode system)
   - Nothing else — it's a glance, not a deep dive

8. **Navigation**: Full mode uses tabbed navigation at the top of the screen.
   Tabs are horizontal, selectable via mouse/keyboard. Active tab highlighted
   with Ancient glow. Locked tabs show a lock icon and Ancient text (reveals
   what it will be when unlocked at the right knowledge tier).

9. **Visual style**: The Kino Remote UI uses an **Ancient aesthetic**:
   - Dark background with subtle grid pattern
   - Cyan/teal accent color for active elements
   - Amber for warnings, red for critical
   - Thin geometric borders, no rounded corners
   - Text in a custom "Ancient" font that transitions to readable text per
     knowledge tier
   - Subtle scan-line or holographic flicker effect (optional, tunable)

### States and Transitions

| State | Entry Condition | Exit Conditions | Behavior |
|-------|----------------|-----------------|----------|
| **Closed** | Default / dismissed | Tap key → Quick-Check. Hold key → Full Mode. | No UI visible. Gameplay active. |
| **Quick-Check** | Tap Kino Remote key | Release key or timeout → Closed. Hold key → Full Mode. | Small overlay, gameplay continues, timers tick. |
| **Full Mode** | Hold key, or transition from Quick-Check | Tap key or Escape → Closed. | Full-screen UI, game paused, tabbed navigation active. |
| **Screen: [Active Tab]** | User selects a tab in Full Mode | Switch tab → different Screen. Close → Closed. | Content of selected screen displayed. Interactive elements available (power priority drag, planet selection, etc.). |

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Ship State** | Inbound (read) + Outbound (write) | Reads: section map data, system conditions, power distribution. Writes: power priority changes via drag-reorder. |
| **Resource & Inventory** | Inbound (read) | Reads: resource quantities, scarcity thresholds, story item list. Displays on Resources screen. |
| **Timer & Pressure** | Inbound (read) | Reads: all active/visible timers for Timer screen. Quick-check shows most urgent timer. |
| **Ship Exploration** | Inbound (read) | Reads: Ancient knowledge tier for label translation. Section discovery state for map detail. |
| **Stargate & Planetary Runs** | Inbound (read) | Reads: planet scan data for Planet Scans screen. Planet selection interaction. Post-run summary data. |
| **Crew Dialogue & Choice** | Inbound (read) | Reads: crew relationship values and romance levels for Crew screen. |
| **Episode Narrative** *(undesigned)* | Inbound (read) | Reads: current objectives for Objectives screen and quick-check. |
| **Player Controller** | Inbound (trigger) | Kino Remote key binding. Quick-check vs full mode determined by tap/hold. |
| **Camera System** | Outbound (mode) | Quick-check: camera stays in exploration mode. Full mode: camera may shift to show Eli holding device (optional). |
| **Event Bus** | Inbound (subscribe) | Subscribes to `ship:*`, `resource:*`, `timer:*` for real-time updates on open screens. |
| **Save/Load** *(undesigned)* | Outbound (serialization) | Serializes: unlocked screens, console connections, last-viewed tab. |
| **Three.js Scene Mgmt** | Reads | UI renders as an overlay on the current `THREE.Scene`. |

## Formulas

### Label Translation

```
label_readable = knowledge_tier >= label.required_tier
display_text = label_readable ? label.translated : label.ancient_glyphs
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `knowledge_tier` | int | 0-5 | Ship Exploration | Eli's current Ancient knowledge level |
| `label.required_tier` | int | 0-5 | per-label config | Tier needed to read this label |

### Screen Unlock

```
screen_available = screen.unlock_condition.evaluate(game_state)
```

Unlock conditions are boolean predicates — same condition system as dialogue
trees. Examples: `{ type: "console_linked", console: "bridge" }`,
`{ type: "knowledge_tier", min: 2 }`.

No complex math — the Kino Remote is a display system, not a calculation system.
All values it displays are computed by their owning systems (Ship State computes
power, Resource computes quantities, Timer computes remaining time).

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Open Kino Remote during dialogue** | Blocked — Kino Remote key does nothing during active dialogue. | Dialogue owns the screen. |
| **Open during cinematic** | Blocked — cinematics have full screen control. | Don't break cinematics. |
| **Quick-check while sprinting** | Allowed — overlay appears, sprint continues. Player multitasks. | Quick-check shouldn't interrupt movement. |
| **No timers active** | Quick-check timer slot shows "No active timers" or is hidden. Timer screen shows empty state. | Clean empty state, not an error. |
| **All screens locked** | Only default screens (Kino Control, Ship Map basic, Timers, Resources, Objectives) show. Locked tabs visible with lock icon. | Player always has minimum functionality. |
| **Console linked while Kino Remote is open** | New screen tab appears immediately with unlock animation. | Instant feedback on progression. |
| **Power priority changed during crisis** | Change applies immediately. Ship State recomputes. If this causes life support to lose power, system warns. | Player has full control but faces consequences. |
| **Open on a planet** | Works normally. Ship Map shows Destiny (remote). Planet-specific data (timer, resources gathered) emphasized. | Kino Remote works anywhere. |
| **Knowledge tier increases while viewing a screen** | Labels that now meet the threshold transition from Ancient to translated with a subtle animation. | Visible progression feedback. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Ship State | Hard | Section map, system conditions, power grid data, power priority write-back |
| Resource & Inventory | Hard | Resource quantities, scarcity warnings, story items (console connections) |
| Three.js Scene Mgmt | Soft | Renders as overlay on current `THREE.Scene` |
| Event Bus | Hard | Subscribes to state-change events for real-time updates |
| Ship Exploration | Hard | Knowledge tier for label translation (core feature — labels unreadable without it) |
| Timer & Pressure | Hard | Active timer list for Timer screen and quick-check |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Stargate & Planetary Runs | Hard | Planet selection screen, planet scan display |
| Player Controller | Soft | Kino Remote key binding integration |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `QUICK_CHECK_TIMEOUT` | 5s | 2-10s | Quick-check stays longer. | Disappears faster. |
| `QUICK_CHECK_KEY` | Tab | — | Key binding for Kino Remote access. | — |
| `FULL_MODE_HOLD_THRESHOLD` | 0.4s | 0.2-0.8s | Longer hold before full mode. Less accidental opens. | Faster full mode access. |
| `TAB_TRANSITION_SPEED` | 0.2s | 0.1-0.5s | Slower tab switches. More cinematic. | Snappier navigation. |
| `ANCIENT_LABEL_TRANSITION_SPEED` | 1.0s | 0.3-2.0s | Slower reveal when labels become readable. | Faster translation animation. |
| `SCAN_LINE_INTENSITY` | 0.15 | 0-0.5 | More visible holographic effect. | Cleaner, less stylized. 0 = off. |
| `MAP_ZOOM_MIN` | 0.5 | 0.2-0.8 | Can zoom out further on ship map. | Less zoom range. |
| `MAP_ZOOM_MAX` | 3.0 | 1.5-5.0 | Can zoom in closer on details. | Less detail view. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Quick-check open | Small device overlay slides up, holographic glow | Soft activation chime, Ancient tech hum | High |
| Full mode open | Full-screen UI fades in with Ancient boot sequence | Tech activation sound, ambient hum loop | High |
| Tab switch | Content cross-fades, tab highlight slides | Soft click/swipe | Medium |
| Screen unlocked | New tab appears with glow pulse, "NEW" indicator briefly | Discovery chime (same as Ancient tech discovery) | High |
| Ancient text translating | Glyphs morph/fade into readable text | Subtle decode/shimmer sound | Medium |
| Resource warning on quick-check | Amber/red pulse on the relevant readout | Warning ping | High |
| Power priority changed | Power flow lines animate to new distribution | Mechanical adjustment sound | Medium |
| Close Kino Remote | UI fades out, returns to gameplay | Deactivation chirp | Low |

**Visual style**: Ancient aesthetic — dark backgrounds (#0a0a18), cyan/teal accents
(#44ddcc), thin geometric borders, subtle holographic scan-line effect. Custom
Ancient font for untranslated labels. The device feels like alien technology that
Eli is learning to master.

## UI Requirements

| Screen | Content | Interactive Elements |
|--------|---------|---------------------|
| **Kino Control** | Kino drone camera feed (when deployed), deploy/recall button | Deploy Kino, switch to Kino camera, recall |
| **Ship Map** | Full schematic, color-coded sections, objective markers | Zoom, pan, select section for detail, set waypoint |
| **Timers** | All active timers (countdowns + cooldowns), sorted by urgency | Time skip button (blocked during crisis), timer details on select |
| **Resources** | Resource quantities with bars, scarcity indicators, story items list | Select resource for consumption details |
| **System Status** | 8 ship-wide systems with condition bars and powered status | Select system for subsystem breakdown |
| **Power Grid** | Priority list (1-8), power flow visualization | Drag-to-reorder priorities |
| **Planet Scans** | Available planets with atmosphere, resources, hazards | Select planet to view details, confirm for gate dial |
| **Crew** | Crew member list with affinity indicators, relationship status | Select crew member for detail, romance status |
| **Objectives** | Current episode objectives, completed/incomplete checklist | Select objective for map waypoint |

## Acceptance Criteria

- [ ] **Quick-check**: Tap opens small overlay showing timer + warning + objective. Gameplay continues. Releases on key-up or timeout.
- [ ] **Full mode**: Hold opens full-screen UI. Game pauses. All tabs navigable.
- [ ] **Screen unlocks**: Console connections add new tabs. Knowledge tier reveals hidden screens. Unlock animation plays.
- [ ] **Ship map**: All sections displayed with correct color coding. Selection shows detail panel. Zoom/pan works.
- [ ] **Power management**: Drag-to-reorder priorities. Ship State updates immediately. Power flow visual adjusts.
- [ ] **Ancient labels**: Text displays in Ancient glyphs below required tier. Translates when tier reached. Animation on transition.
- [ ] **Planet selection**: Planet Scans screen shows available planets during FTL Drop. Detail level matches sensor condition. Selection feeds into gate dial.
- [ ] **Timer display**: All visible timers shown sorted by urgency. Time skip accessible (blocked during crisis).
- [ ] **Resource display**: All resource types shown with quantities and scarcity color coding. Story items listed.
- [ ] **Real-time updates**: Open screens update when underlying data changes (resource consumed, power changed, timer ticks — via Event Bus).
- [ ] **Blocked during dialogue/cinematic**: Kino Remote key does nothing during active dialogue or cinematics.
- [ ] **Works on planets**: Full functionality while off-ship. Ship data shows remote Destiny state.
- [ ] **Serialization**: Unlocked screens, console connections, and last-viewed tab persist across save/load.
- [ ] **Performance**: Full mode UI renders in < 2ms. No frame drops on open/close transitions.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Should the Kino Remote have a physical 3D model visible in Eli's hand during quick-check? Adds immersion but costs dev time. | Art Director | Before production | — |
| How does Kino drone camera feed display? Picture-in-picture on the Kino Control screen, or does it replace the main view? | Game Designer | Before Kino Drone GDD | — |
| Should there be a notification system (badge icons on tabs when something changes)? Useful but potentially distracting. | UX Designer | During prototype | — |
| Can the Kino Remote interface with alien technology found on planets? If yes, what screens/data does that provide? | Creative Director | Before S2 design | — |
| Should crew members be contactable via Kino Remote (comms feature), or only in person? | Game Designer | Before Crew AI GDD | — |
| How many console connection points total on Destiny? Each is a progression moment and level design requirement. | Level Designer | Before content planning | — |
