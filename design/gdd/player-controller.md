# Player Controller (Third-Person)

> **⚠️ Engine mapping updated — Three.js web era (2026-09-08 re-pivot)**
>
> Engine-specific sections have been updated from the old framework
> (removed in `abfb5ed`) to Three.js equivalents: `THREE.Raycaster` /
> manual collision replaces the old Physics kinematic body,
> `requestAnimationFrame` replaces the old Gameplay Runtime system
> registration, and `THREE.AnimationMixer` replaces the old
> animation pipeline. The movement/interaction controller design (walk,
> sprint, squeeze/duck/climb, contextual traversal rules) remains reference
> until implemented in the web codebase (`src/*.js` + `index.html`, built
> via `build.sh`).

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-30
> **Implements Pillar**: Pillar 1 (The Ship IS the World), Pillar 3 (Earned Discovery)

## Overview

The Player Controller governs Eli Wallace's physical presence and interaction with
the game world. It handles third-person movement (walk, sprint), collision with the
environment via Crashcat physics, contextual traversals (squeeze, duck, climb), and
a context-sensitive interaction
system that lets the player examine, use, and talk to objects and crew members in
the world. Movement is light and responsive — Eli isn't a soldier, but the controls
should feel good to navigate, not sluggish. Interaction uses a radial menu: tap the
interact key for the default action on the nearest interactable, or hold it to open
a small radial wheel when multiple actions are available (e.g., an Ancient console
might offer "Examine", "Activate", or "Deploy Kino"). The controller operates in
both ship interiors (tight corridors, rooms, doors) and planet exteriors (open
terrain, environmental hazards) with identical movement parameters — environmental
differences are delivered through level design, audio, and lighting. It publishes
events to the Event Bus (`player:interact`,
`player:entered:section`, `player:kino:deployed`) so other systems can react to
the player's actions without direct coupling.

## Player Fantasy

The Player Controller serves the fantasy of **becoming Eli Wallace** — not the
confident genius he'll be, but the overwhelmed kid he starts as. Eli's
relationship with his own body in this world mirrors his character arc across the
show: he begins vulnerable, lost, and uncertain, and gradually grows into someone
who owns every corridor of Destiny.

**Early game (Season 1)**: Movement feels slightly hesitant. Eli doesn't know
this ship. Dark corridors are tense — footsteps echo, the flashlight cone is
narrow, interaction prompts feel like reaching into the unknown. The player
shares Eli's disorientation because the controls reflect it: the radial menu
shows fewer options (Eli doesn't know what half this Ancient tech does yet), and
unfamiliar sections feel subtly hostile.

**Mid game (Season 2)**: Confidence is earned, not given. As the player
explores more of Destiny and the story progresses, Eli moves with growing
purpose. Powered, familiar sections feel like home — movement is fluid, the
radial menu expands with new capabilities, and Eli's animations shift from
cautious to assured. But unexplored sections still carry tension, because Eli
knows what can go wrong now.

**Late game (Season 3+)**: Eli has grown into his role. He strides through
Destiny with authority. The radial menu is a full toolkit. Planetary runs feel
like a practiced operation, not a desperate scramble. The controller reflects
a character who has realized his full potential — and the player *earned* that
transformation through hours of play.

This serves **Pillar 1 (The Ship IS the World)** — the controller makes Destiny
feel different from everywhere else because it progressively becomes home. It
serves **Pillar 3 (Earned Discovery)** — confidence is never handed to you; you
feel Eli's growth because you lived it.

## Detailed Design

### Core Rules

1. **Movement model**: The player controls Eli in third-person using WASD
   (keyboard) or left analog stick (gamepad). Movement is relative to the
   camera facing direction.
2. **Walk and sprint**: Default movement is a walk. Hold Shift (keyboard) or
   left stick click (gamepad) to sprint. Sprint has no stamina limit — it is
   always available. Sprint speed is 1.8× walk speed.
3. **No explicit crouch or crawl**: There is no crouch button. When the player
   approaches a designed traversal point (gap, collapsed section, low obstacle,
   vent), an interaction prompt appears. Pressing interact triggers a contextual
   traversal animation (squeeze through, duck under, climb over, shimmy along).
   These are authored per-location in the level editor, Jedi Outcast-style — the
   environment tells the player what Eli can do.
4. **Contextual traversal**: Each traversal point defines: entry trigger volume,
   traversal type (squeeze/duck/climb/shimmy), animation clip, duration, exit
   position. During traversal, player input is locked and the camera may
   reposition. The player can cancel most traversals by pressing the back key
   during the first 0.3 seconds.
5. **Interaction system**: The player interacts with the world through a radial
   menu system:
   - **Tap interact** (E / gamepad face button): Perform the default action on
     the nearest interactable within range
   - **Hold interact** (0.3s): Open the radial menu showing all available
     actions. The game **pauses** while the radial is open. Move mouse / right
     stick to highlight an option, release to confirm, or press cancel to close
   - Interactables in range are highlighted with a subtle outline glow. No
     floating text or icons until the player holds interact — respecting Pillar 3
     (Earned Discovery)
6. **Interaction reach**: Context-dependent. Physical objects (doors, consoles,
   items) require close proximity (1.5m). Crew dialogue can be initiated at
   medium range (3.5m). Traversal points activate at their trigger volume
   boundary.
7. **Interactable detection**: A spherical raycast from the camera center detects
   interactables. When multiple interactables are in range, the one closest to
   the camera center (screen-space) is the default target. The radial menu shows
   all in-range options.
8. **Lighting**: Eli does not manage a light source. In the rare dark
   environments that require it (certain story moments, dark planets), Eli
   automatically pulls out his phone as a light source. This is a contextual
   animation, not a player-controlled mechanic. Most ship sections have
   sufficient ambient light (emergency strips, Ancient tech glow, starlight
   through hull breaches) and do not trigger the phone light.
9. **Ledge refusal**: Eli will not walk off drops that would kill a person.
   When approaching a lethal ledge, an invisible barrier stops movement and
   Eli plays a recoil/vertigo animation (may comment aloud). The player
   cannot override this. Narrative-authored exceptions exist: specific story
   moments (e.g., escaping an explosion, jumping to a lower platform during
   a crisis) can place traversal points that allow the drop. Falls from
   non-lethal heights (catwalks, stairs, short ledges) are still possible
   and trigger the normal fall/recovery/injury system.
10. **Movement parameters are identical** across ship interiors and planet
   exteriors. Environmental differences (atmosphere, tension, scale) are
   delivered through level design, camera framing, audio, and lighting — not
   the controller.
11. **No death state**: The player controller has no death or game-over state.
    All failure is handled through narrative consequences. On planets, if the
    timer expires, Eli and the team automatically return through the gate —
    the player misses the opportunity but does not die. The only exception
    is explicitly authored story moments where the team gets stranded (and
    even then, the story continues — they get found).
12. **Eli's growth arc** affects the controller in two ways:
    - **Radial menu breadth**: Early game, Eli has fewer interaction options (he
      doesn't understand Ancient tech yet). As the story progresses and he
      learns, new radial options unlock on previously opaque objects.
    - **Animation confidence**: Eli's locomotion and interaction animations shift
      across seasons — from hesitant and uncertain (S1) to purposeful and
      assured (S3+). Same inputs, different character expression.

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **Idle** | No movement input, on ground | Movement input, interact, fall | Eli stands in place, breathing animation. After 5-8s of no input, plays a random **fidget animation** from a weighted pool: check phone (S1 — Eli's comfort object), examine Kino Remote (S2+), look around nervously (S1) or confidently (S3+), stretch, fiddle with nearby object. Fidget selection is weighted by story progression. Interactables in range are detectable. |
| **Walking** | Movement input while idle/sprinting | Stop input → Idle, Shift → Sprinting, fall → Falling, interact → context | Standard locomotion. Camera follows. Interactable detection active. |
| **Sprinting** | Shift held during Walking | Release Shift → Walking, stop → Idle, fall → Falling | Faster locomotion (1.8× walk). Same detection. Camera pulls back slightly. |
| **Interacting** | Tap interact near interactable | Animation completes or is cancelled | Brief interaction animation plays. Movement locked for duration. Publishes `player:interact` event. |
| **Radial Menu Open** | Hold interact (0.3s) | Release to confirm action, cancel to close | Game paused. Radial UI visible. Mouse/stick selects option. Confirming transitions to Interacting. |
| **Traversing** | Enter traversal trigger + interact | Animation completes, or cancel (first 0.3s) | Contextual animation plays (squeeze/duck/climb/shimmy). Input locked. Camera may reposition. Exit position defined by traversal point. |
| **Falling** | No ground contact detected | Ground contact → Landing | Gravity applied. Limited air control. No interaction. |
| **Landing** | Ground contact after Falling | Recovery complete → Idle/Walking | Brief recovery animation. Short fall = instant recovery. Long fall = stumble (Eli isn't athletic). |
| **Phone Light** | Enter dark zone (automatic) | Exit dark zone or zone gains power | Eli holds phone in off-hand. Not a separate state — an additive animation layer flag. Active during Idle, Walking, Sprinting, or Interacting. |
| **Dialogue** | Crew dialogue initiated | Dialogue ends | Camera reframes to conversation angle. Movement locked. Dialogue system takes over input. Controller resumes on exit. |

**Valid transitions:**
- Idle ↔ Walking ↔ Sprinting (standard movement cycle)
- Any grounded state → Falling (lose ground contact)
- Falling → Landing → Idle/Walking
- Idle/Walking → Interacting → Idle (tap interact)
- Idle/Walking → Radial Menu Open → Interacting → Idle (hold interact)
- Idle/Walking → Traversing → Idle (at exit position)
- Idle/Walking → Dialogue → Idle (crew conversation)
- Phone Light is an overlay flag, not a state — can be active during any
  grounded state

**Animation tooling**: All character animations (locomotion, interactions,
fidgets, traversals) use Three.js `THREE.AnimationMixer` with
`THREE.AnimationClip` and `THREE.AnimationAction` for skeletal animation
playback, blending, and layering. Animations are authored externally (Mixamo,
Blender, or motion capture) and imported as glTF/GLB. The
phone-light overlay and fidgets use additive animation layers (via
`AnimationAction.blendMode = THREE.AdditiveBlending`) so they blend
with the base locomotion state.

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Event Bus** | Outbound (publish) | Publishes: `player:interact` (payload: interactable ID, action type), `player:entered:section` (payload: section ID, first-visit flag), `player:kino:deployed` (payload: position, direction). Does NOT publish per-frame position — other systems read it directly. |
| **Three.js Raycaster** | Bidirectional | Controller manages Eli's collision via `THREE.Raycaster` for ground detection and interactable targeting. Manual velocity integration for kinematic movement. Reads ground contact and collision normals from raycast results. |
| **`requestAnimationFrame` loop** | Inbound (lifecycle) | Controller update called each frame via `requestAnimationFrame` at ~60 FPS. Initializes on scene mount, cleans up on scene dispose. |
| **`THREE.AnimationMixer`** | Outbound (drive) | Controller sets animation states (walk, sprint, idle, fidget, interact, traverse). Uses `AnimationAction` layers for additive overlays (phone light, fidgets). |
| **Camera System** *(downstream, undesigned)* | Outbound (position/rotation) | Exposes `getPosition()`, `getRotation()`, and `getVelocity()` for the Camera System to follow. Camera reads these directly each frame (not via events). During traversals and dialogue, controller signals the Camera to use authored camera positions. |
| **Ship Exploration** *(downstream, undesigned)* | Outbound (events) | `player:entered:section` triggers section discovery logic. Ship Exploration reads player position to determine which section Eli is in. |
| **Stargate & Planetary Runs** *(downstream, undesigned)* | Bidirectional | Planetary Runs system can override controller spawn position when gating to a planet. Controller publishes `player:interact` when using the Stargate. |
| **Crew Dialogue & Choice** *(downstream, undesigned)* | Outbound (trigger) | When player initiates dialogue (via radial menu on a crew member), publishes `player:interact` with action type `dialogue`. Dialogue system transitions controller to Dialogue state and takes over input. Returns control on dialogue end. |
| **Ancient Tech Puzzles** *(downstream, undesigned)* | Outbound (trigger) | When player interacts with a puzzle console, publishes `player:interact` with action type `puzzle`. Puzzle system takes over input. Returns control on puzzle exit. |
| **Kino Drone** *(downstream, undesigned)* | Outbound (deploy) | When player deploys Kino via radial menu, publishes `player:kino:deployed`. Kino Drone system spawns the drone and may transfer camera control. |

**Provisional contracts** (flagged for revision when downstream systems are
designed):
- Camera System: exact follow parameters and transition signals TBD
- Ship Exploration: section boundary detection method TBD (trigger volumes
  vs. spatial query)
- Dialogue/Puzzle handoff: exact input lock/unlock protocol TBD

## Formulas

### Movement Speed

```
actual_speed = base_speed * sprint_multiplier * surface_modifier
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `base_speed` | float | 3.0-5.0 m/s | config | Eli's walking speed |
| `sprint_multiplier` | float | 1.0 or 1.8 | controller state | 1.0 when walking, 1.8 when sprinting |
| `surface_modifier` | float | 0.5-1.0 | scene data | Surface friction (1.0 = normal, 0.7 = sand/mud, 0.5 = ice) |

**Expected output range**: 1.5 m/s (walking on ice) to 9.0 m/s (sprinting normal)

### Interactable Detection

```
is_interactable = distance <= max_reach
                  AND dot(camera_forward, to_target) >= cos(detection_cone_half_angle)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `distance` | float | 0-∞ | calculated | Distance from player to interactable center |
| `max_reach` | float | 1.5 or 3.5 m | interactable config | Close (physical) or medium (dialogue) reach |
| `camera_forward` | vec3 | unit vector | camera | Camera's forward direction |
| `to_target` | vec3 | unit vector | calculated | Normalized direction from camera to interactable |
| `detection_cone_half_angle` | float | 30° | config | How far off-center an interactable can be detected |

### Fidget Timer

```
fidget_delay = base_delay + random(0, variance)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `base_delay` | float | 5.0-8.0 s | config | Minimum idle time before first fidget |
| `variance` | float | 0-3.0 s | config | Random additional delay to feel natural |

### Fall Recovery

```
recovery_time = fall_height < safe_height ? 0.0
              : min(fall_height * recovery_scale, max_recovery)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `fall_height` | float | 0-∞ m | physics | Vertical distance fallen |
| `safe_height` | float | 1.5 m | config | Falls below this are instant recovery |
| `recovery_scale` | float | 0.15 s/m | config | Seconds of recovery per meter fallen |
| `max_recovery` | float | 1.2 s | config | Cap on recovery time (long stumble) |

**Edge case**: Falls above `injury_height` (8m) trigger an injury state —
Eli limps with reduced speed for `injury_duration` seconds. No death.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Player spams interact during traversal** | Input is locked during traversal. Interact presses are ignored. Cancel only works in first 0.3s via back key. | Prevents animation breaks and exploits. |
| **Multiple interactables at same distance** | The one closest to screen center wins as default target. Radial menu shows all options with labels. | Players naturally look at what they want to interact with. |
| **Interact pressed with nothing in range** | Nothing happens. No error sound, no feedback. | Avoids training players to expect prompts everywhere (Pillar 3). |
| **Player walks off a ledge while interacting** | Interaction is cancelled. Controller transitions to Falling. | Physics takes priority — Eli can't hover mid-air pressing buttons. |
| **Traversal exit position is blocked** | Traversal is prevented from starting (show "blocked" feedback). Level design should ensure exits are always clear, but runtime check as safety net. | Prevents Eli from getting stuck inside geometry. |
| **Player opens radial menu with only one action** | Radial still opens (single option highlighted). Teaches the player the menu exists for when multiple options appear later. | Consistency and discoverability. |
| **Approaching a lethal drop** | Eli stops at the edge and refuses to step off. Plays a recoil/vertigo animation, may comment ("No way."). The player cannot walk off drops that would be fatal unless the scenario is explicitly authored as a narrative traversal point (e.g., "jump to escape an explosion"). | No death in this game. Eli is smart enough not to walk off a cliff. Narrative-authored exceptions allow dramatic moments without giving players constant accidental deaths. |
| **Fall from extreme height (>8m, non-lethal)** | Injury state: Eli stumbles hard on landing, limps for a duration, movement speed reduced. No death — recovery is automatic. Narrative consequence only (crew comments on Eli's recklessness). | Extreme falls hurt, but the story continues. This only applies to falls from heights that are survivable but painful (8-15m range, e.g., falling from a catwalk). |
| **Sprint into a wall continuously** | Eli plays a bracing/leaning animation against the wall. Speed drops to zero. No sliding along walls. | Feels grounded and physical. Prevents wall-skating. |
| **Scene transition during movement** | Controller state resets to Idle at new scene spawn point. Velocity zeroed. | Clean state on scene boundaries prevents physics glitches. |
| **Dialogue initiated while sprinting** | Sprint cancels, Eli decelerates to stop, then enters Dialogue state. No instant freeze. | Feels natural — Eli slows to a stop before talking. |
| **Phone light activates during traversal** | Phone light does NOT activate during traversals (hands occupied). Activates after traversal completes if still in dark zone. | Physical plausibility — Eli needs his hands for squeezing/climbing. |
| **Fidget interrupted by input** | Fidget animation blends out immediately when player moves or interacts. No input delay. | Responsiveness always wins over animation polish. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| `requestAnimationFrame` loop | Hard | Provides the update loop, scene lifecycle |
| Three.js Raycaster / manual collision | Hard | Provides ground detection, raycasting, collision (replaces old Physics) |
| `THREE.AnimationMixer` | Hard | Provides skeletal animation playback, blending, additive layers (replaces old animation pipeline) |
| Three.js Render Pipeline | Soft | Provides outline glow for interactable highlighting |
| Event Bus | Hard | Publishes `player:*` events for cross-system communication |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Camera System | Hard | Player position, rotation, velocity (read directly each frame). Traversal/dialogue camera signals. |
| Ship Exploration | Hard | `player:entered:section` events. Player position for section detection. |
| Stargate & Planetary Runs | Hard | `player:interact` on Stargate. Spawn position override interface. |
| Crew Dialogue & Choice | Hard | `player:interact` with action type `dialogue`. Input lock/unlock protocol. |
| Ancient Tech Puzzles | Hard | `player:interact` with action type `puzzle`. Input lock/unlock protocol. |
| Kino Drone | Hard | `player:kino:deployed` event with position and direction. |
| Ship Atmosphere & Lighting | Soft | Player position for localized atmosphere effects (reads directly). |
| Audio & Ambience | Soft | Player position for spatial audio. Movement state for footstep selection. |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `BASE_WALK_SPEED` | 4.0 m/s | 3.0-5.0 | Eli feels faster, corridors shorter. Above 5.0 feels floaty. | Eli feels sluggish. Below 3.0 feels like wading. |
| `SPRINT_MULTIPLIER` | 1.8 | 1.4-2.2 | Sprint more distinct from walk. Above 2.2 feels like different character. | Sprint barely noticeable. Below 1.4 players won't bother. |
| `INTERACT_REACH_CLOSE` | 1.5 m | 1.0-2.5 | Interact from further. Above 2.5 feels like telekinesis. | Must stand on top of objects. Below 1.0 frustrating. |
| `INTERACT_REACH_DIALOGUE` | 3.5 m | 2.5-5.0 | Conversations across a room. Above 5.0 feels weird. | Must get uncomfortably close to NPCs. |
| `DETECTION_CONE_HALF_ANGLE` | 30° | 15°-45° | Easier peripheral targeting. Above 45° picks up too much. | Must aim precisely. Below 15° frustrating. |
| `RADIAL_HOLD_THRESHOLD` | 0.3 s | 0.15-0.5 | More deliberate hold. Above 0.5 unresponsive. | Opens too easily on quick taps. Below 0.15 interferes with tap. |
| `FIDGET_BASE_DELAY` | 6.0 s | 4.0-10.0 | Longer idle before fidgets. Above 10.0 Eli feels lifeless. | Fidgets too quickly. Below 4.0 interrupts reading. |
| `SAFE_FALL_HEIGHT` | 1.5 m | 1.0-2.5 | Shrugs off bigger falls. Above 2.5 undermines civilian feel. | Stumbles on tiny drops. Below 1.0 annoying on stairs. |
| `INJURY_FALL_HEIGHT` | 8.0 m | 5.0-12.0 | Bigger falls before injury. Above 12.0 feels superhuman. | Injury on modest falls. Below 5.0 punishing. |
| `INJURY_DURATION` | 8.0 s | 4.0-15.0 | Longer limp after extreme falls. Above 15.0 tedious. | Brief limp, minimal consequence. Below 4.0 trivial. |
| `INJURY_SPEED_MODIFIER` | 0.5 | 0.3-0.7 | Less speed penalty while injured. | Slower limp. Below 0.3 feels stuck. |
| `TRAVERSAL_CANCEL_WINDOW` | 0.3 s | 0.1-0.5 | Longer cancel window. Above 0.5 feels non-committal. | Must commit instantly. Below 0.1 effectively no cancel. |
| `SURFACE_MODIFIER_SAND` | 0.7 | 0.5-0.9 | Sand has less impact on speed. | Sand slows significantly. Affects planet pacing. |
| `SURFACE_MODIFIER_ICE` | 0.5 | 0.3-0.7 | Ice has less impact. | Ice very slow. Could frustrate on ice planets. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Walking (ship) | Eli locomotion animation, footstep dust | Metallic footsteps echoing in corridors | High |
| Walking (planet) | Eli locomotion animation, surface-appropriate particles | Terrain-specific footsteps (dirt, rock, sand, mud) | High |
| Sprinting | Faster animation cycle, subtle camera bob | Heavier, faster footsteps. Breathing sounds. | High |
| Idle fidget | Context-appropriate fidget animation | Subtle sounds (phone tap, fabric rustle) | Medium |
| Interactable in range | Subtle outline glow on target object | None (silent detection — Pillar 3) | High |
| Radial menu open | Radial UI overlay, game pauses | Soft UI open sound | High |
| Contextual traversal | Full-body authored animation (squeeze/duck/climb) | Effort sounds, surface contact sounds | High |
| Phone light activate | Phone appears in off-hand, cone of light | Phone unlock sound | Medium |
| Injury (extreme fall) | Stumble animation, limping locomotion blend | Impact sound, pained grunt, limping footsteps | Medium |
| Wall bracing | Eli puts hand against wall | Thud, fabric scrape | Low |

## UI Requirements

| Information | Display Location | Update Frequency | Condition |
|-------------|-----------------|-----------------|-----------|
| Interactable highlight | World-space outline on object | Per-frame (when in range) | Interactable within reach and detection cone |
| Radial menu | Screen-center overlay | On demand (hold interact) | Game paused, options available |
| Radial option labels | Around radial wheel | Static while open | Each available action labeled |
| Traversal prompt | World-space near trigger | Per-frame (when near trigger) | Player within traversal trigger volume |

No HUD elements for health, stamina, or status — the Player Controller has no
death state and no stamina. All player status is communicated through animation
and audio (Pillar 3: Earned Discovery — no meters, no numbers).

## Acceptance Criteria

- [ ] **Basic movement**: Player can walk in all 4 directions relative to camera. Movement is smooth at 60 FPS with no visible jitter.
- [ ] **Sprint**: Holding sprint increases speed to 1.8× walk. Releasing returns to walk speed. Transition is smooth (no instant snap).
- [ ] **Interactable detection**: Objects within reach and detection cone are highlighted with outline glow. Object closest to screen center is the default target.
- [ ] **Tap interact**: Tapping E on a single-action interactable performs the default action and publishes `player:interact` event with correct payload.
- [ ] **Radial menu**: Holding E for 0.3s opens the radial menu. Game pauses while open. Mouse/stick selects options. Release confirms. Cancel closes without acting.
- [ ] **Radial with one option**: Radial menu opens even with a single available action. Option is pre-highlighted.
- [ ] **Contextual traversal**: Approaching a traversal trigger and pressing interact plays the correct animation (squeeze/duck/climb/shimmy). Player arrives at exit position. Input is locked during traversal.
- [ ] **Traversal cancel**: Pressing back within 0.3s of traversal start cancels and returns Eli to entry position.
- [ ] **Falling and landing**: Walking off a ledge transitions to Falling. Landing plays recovery animation scaled by fall height. Falls below 1.5m have instant recovery.
- [ ] **Injury from extreme falls**: Falls above 8m trigger injury — Eli stumbles, limps, movement slowed. No death. Recovery is automatic over time.
- [ ] **Phone light**: Entering a designated dark zone automatically activates phone-light animation overlay. Exiting deactivates it. Does not activate during traversals.
- [ ] **Fidgets**: After 5-8s idle, Eli plays a fidget animation. Interrupted immediately by any player input. Fidget pool varies by story progression.
- [ ] **Dialogue handoff**: Initiating dialogue via radial transitions to Dialogue state, locks movement, returns control when dialogue ends.
- [ ] **Scene transition**: Entering a new scene resets controller to Idle at spawn point with zero velocity.
- [ ] **Event publishing**: `player:entered:section` fires on section boundary crossing. `player:kino:deployed` fires on Kino deploy via radial.
- [ ] **No wall-skating**: Sprinting into a wall plays bracing animation and stops movement. No sliding along surfaces.
- [ ] **No death state**: The player controller has no death or game-over state. All failure is handled through narrative consequences (missed resources, story changes, crew reactions).
- [ ] **Performance**: Controller update completes within 1ms per frame (within 16.6ms budget). No per-frame garbage allocation.
- [ ] **All tuning values externalized**: Every value from the Tuning Knobs table is loaded from config, not hardcoded.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Exact radial menu visual design — how many segments, icon style, Ancient aesthetic? | UX Designer | Before UI implementation | — |
| Should the radial menu be diegetic (projected from the Kino Remote) or a standard game UI overlay? | Creative Director | Before UI implementation | — |
| How does the Camera System handle traversal camera repositioning? Authored per-traversal or algorithmic? | Camera System GDD | When Camera System is designed | — |
| What triggers the "first visit" flag on `player:entered:section`? Trigger volume or proximity to a landmark? | Ship Exploration GDD | When Ship Exploration is designed | — |
| Should Eli have voiced lines for ledge refusal and fidgets, or just animations? | Creative Director | Before audio implementation | — |
| Exact animation set needed — how many fidgets, traversal types, and confidence tiers? | Art Director | Before animation authoring | — |
