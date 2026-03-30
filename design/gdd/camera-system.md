# Camera System (Third-Person)

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-30
> **Implements Pillar**: Pillar 1 (The Ship IS the World), Pillar 3 (Earned Discovery)

## Overview

The Camera System provides the player's viewpoint into the game world, handling
third-person follow behavior during exploration and cinematic framing during
scripted moments. During gameplay, the camera is smooth and stable with full
player rotation control (mouse / right stick), augmented by subtle auto-framing
that drifts toward points of interest and adjusts height in tight spaces — the
player can always override these suggestions. During scripted moments (dialogue,
crises, traversals, story beats), the camera transitions to SGU-style documentary
cinematography with handheld sway, intimate framing, and authored angles. The
camera reads the Player Controller's position, rotation, and velocity directly
each frame, and its facing direction determines interactable targeting (raycasts
originate from camera center). The system must handle Destiny's tight corridors,
open planet exteriors, and transitions between them without clipping through walls
or losing sight of Eli.

## Player Fantasy

The camera is **Eli's awareness made visible**. Where you look is what Eli
notices. The camera doesn't feel like a separate entity filming a character —
it feels like being inside Eli's head, seeing the world through his attention.
When you explore a dark corridor, the camera follows your gaze with the
responsiveness of your own eyes. When something interesting is nearby, the camera
subtly suggests it — a gentle drift, a slight reframe — the way your attention
would naturally be drawn in real life. You can always override it, because Eli's
attention belongs to you.

This creates an intimate connection between player and character that serves
**Pillar 1 (The Ship IS the World)**: Destiny feels vast because *you* experience
its scale through Eli's eyes. When the camera auto-adjusts in a tight corridor
versus an open observation deck, you feel the architecture. It also serves
**Pillar 3 (Earned Discovery)**: the auto-framing hints at points of interest
without markers or UI — the camera notices things before you consciously do,
just like Eli would.

During scripted moments (dialogue, story beats, crises), the camera shifts to
authored cinematic angles. This contrast is intentional — when the camera moves
in a way you don't control, it signals "something important is happening." The
shift from player-awareness to cinematic framing *is* the storytelling.

## Detailed Design

### Core Rules

1. **Camera rig**: The camera is a virtual rig with three components: a **pivot**
   (attached to Eli's position at shoulder height), an **arm** (extending behind
   and above the pivot), and the **camera** (at the arm's end, looking at the
   pivot). The player controls the pivot's yaw (horizontal) and pitch (vertical).
2. **Player control**: Mouse movement (PC) or right analog stick (gamepad)
   rotates the camera pivot. Horizontal movement controls yaw (unlimited).
   Vertical movement controls pitch (clamped to -60° to +70°). Sensitivity is
   configurable. Input is always responsive — no acceleration curve that adds lag.
3. **Follow behavior**: The camera follows Eli with smooth interpolation
   (`lerp`). Position follows at a configurable smoothing rate (default 0.15).
   The camera never teleports (except on scene transitions) — all movement is
   interpolated.
4. **Arm length and collision**: Default arm length is 3.5m. When the arm would
   clip through geometry, the camera pulls in closer to Eli along the arm
   direction via a spherecast. In very tight spaces (arm compressed below 1.0m),
   the camera transitions to a near-over-the-shoulder view. When space opens up,
   the arm extends back to default length with smooth interpolation (slower than
   compression — extending feels unhurried, compression is instant to prevent
   clipping).
5. **Auto-framing (offset)**: When a point of interest (POI) is nearby, Eli's
   screen position shifts to create negative space toward the POI. The camera
   does not rotate — only the follow target offset changes. This leads the
   player's eye without taking control. The offset is small (max 15% of screen
   width) and blends in/out smoothly. Player camera movement cancels the offset
   instantly.
6. **Cinematic mode**: During scripted moments (dialogue, traversals, story
   beats), the camera transitions to authored positions and angles. Cinematic
   cameras are defined per-scene in the level editor. Transitions use smooth
   ease-in/ease-out blends (configurable duration, default 0.6s). Player camera
   input is disabled during cinematic mode. Cinematic mode supports SGU-style
   handheld procedural sway (subtle position/rotation noise) for documentary
   feel.
7. **Dialogue framing**: When the Player Controller enters Dialogue state, the
   camera transitions to a two-shot or over-the-shoulder angle framing Eli and
   the NPC. Each dialogue node can specify a camera angle (default: two-shot).
   Camera cuts between angles are instantaneous (no blend) to mimic TV editing.
8. **Traversal camera**: During contextual traversals, the camera may reposition
   to an authored angle that shows the traversal clearly (e.g., side view of a
   squeeze-through). If no authored angle exists, the camera holds its current
   position and tracks Eli through the traversal.
9. **Sprint offset**: When Eli sprints, the camera arm extends slightly (+0.5m)
   and lowers pitch slightly (-3°), creating a sense of speed. Reverts smoothly
   when sprint ends.
10. **Universal pause**: The game can be paused at any time, in any camera state
    (exploration, cinematic, dialogue, traversal). On pause, the camera freezes
    in its exact current position and rotation. On unpause, the camera resumes
    from exactly where it was — no snapping or re-interpolation. Cinematic
    timelines pause and resume in sync.
11. **Scene transitions**: On scene load, the camera snaps to the default
    position behind Eli at the spawn point. No interpolation from the previous
    scene's camera position.
12. **Vertical tracking**: The camera pivot height adjusts smoothly based on
    Eli's state: standing (shoulder height), crouching during traversals
    (lower), falling (tracks with slight delay for dramatic effect).

### States and Transitions

| State | Entry Condition | Exit Condition | Behavior |
|-------|----------------|----------------|----------|
| **Exploration** | Default state. Player Controller in Idle/Walking/Sprinting. | Controller enters Dialogue, Traversing, or cinematic trigger. | Full player camera control. Arm collision active. Auto-framing offset active. Sprint offset when sprinting. |
| **Cinematic** | Scripted trigger (story beat, crisis, cutscene). | Script ends or is skipped. | Authored camera positions. SGU handheld sway. Player input disabled. Smooth blend in, instant or blend out. Pausable. |
| **Dialogue** | Player Controller enters Dialogue state. | Dialogue ends, controller returns to Idle. | Two-shot or OTS framing. Cuts between angles on dialogue node changes. Player input disabled. Pausable. |
| **Traversal** | Player Controller enters Traversing state. | Traversal animation completes. | If authored angle exists: smooth blend to authored position, track Eli. If none: hold current position, track Eli. Player input disabled. |
| **Paused** | Pause input (any state). | Unpause input. | Camera frozen. All interpolation, sway, and timeline stopped. Resumes to previous state exactly on unpause. |

**Valid transitions:**
- Exploration → Dialogue (dialogue initiated)
- Exploration → Traversal (traversal started)
- Exploration → Cinematic (scripted trigger)
- Dialogue → Exploration (dialogue ends)
- Traversal → Exploration (traversal completes)
- Cinematic → Exploration (script ends)
- Any state → Paused → previous state (universal pause)

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Player Controller** | Inbound (read) | Reads `getPosition()`, `getRotation()`, `getVelocity()` each frame. Receives state signals: Dialogue entered/exited, Traversing entered/exited, sprint started/stopped. |
| **ggez Physics (Crashcat)** | Inbound (collision) | Spherecast along camera arm to detect wall collisions. Used for arm compression to prevent clipping. |
| **ggez Gameplay Runtime** | Inbound (lifecycle) | Registers as a system. Receives `update(delta)` each frame. Updates after Player Controller in system execution order. |
| **Event Bus** | Inbound (subscribe) | Subscribes to `episode:crisis:triggered` and similar narrative events to trigger cinematic camera transitions. |
| **Ship Exploration** *(downstream, undesigned)* | Outbound (read) | Ship Exploration may read camera position/direction for section visibility. Camera provides `getPosition()` and `getForward()`. |
| **Crew Dialogue & Choice** *(downstream, undesigned)* | Inbound (framing data) | Dialogue system provides: NPC position for framing, camera angle per dialogue node (two-shot, OTS-left, OTS-right, close-up). |
| **Kino Drone** *(downstream, undesigned)* | Bidirectional | On Kino view, Camera System stores exploration state and hands rendering to Kino's first-person camera. On recall, resumes exploration state. |
| **Interactable Detection** (Player Controller subsystem) | Outbound (facing) | Camera forward direction is the raycast origin for interactable detection. Camera facing = what Eli can target. |

**Provisional contracts:**
- Kino Drone: camera state save/restore protocol TBD
- Dialogue: exact camera angle enum and framing offsets TBD

## Formulas

### Arm Collision Compression

```
effective_arm_length = min(default_arm_length,
                          spherecast_hit_distance - camera_radius)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `default_arm_length` | float | 3.5 m | config | Ideal camera distance behind Eli |
| `spherecast_hit_distance` | float | 0-∞ m | physics | Distance to nearest wall behind camera |
| `camera_radius` | float | 0.2 m | config | Spherecast radius (prevents surface clipping) |

**Expected output range**: 0.5m (tight corridor) to 3.5m (open space)

### Follow Smoothing

```
camera_position = lerp(camera_position, target_position, 1 - smoothing^delta)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `smoothing` | float | 0.01-0.3 | config | Lower = snappier. Default 0.15 |
| `delta` | float | ~0.0167 s | runtime | Frame delta time |
| `target_position` | vec3 | world space | player controller | Eli's position + pivot offset |

### Arm Extension Smoothing

```
arm_extend_rate = compression ? instant : lerp_rate * delta
arm_compress_rate = instant (no interpolation on compression)
```

Compression is instant to prevent clipping. Extension uses `lerp_rate`
(default: 2.0 m/s) for unhurried feel.

### Auto-Frame Offset

```
offset = direction_to_poi * max_offset * proximity_weight
proximity_weight = 1 - clamp(distance_to_poi / poi_range, 0, 1)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `max_offset` | float | 0.5 m | config | Max screen-space offset (~15% screen width) |
| `poi_range` | float | 8.0 m | POI config | Distance at which POI starts influencing framing |
| `proximity_weight` | float | 0-1 | calculated | Stronger offset when closer to POI |

### Cinematic Handheld Sway

```
sway_offset = perlin_noise(time * sway_frequency) * sway_amplitude
sway_rotation = perlin_noise((time + seed) * sway_frequency)
             * sway_rotation_amplitude
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `sway_frequency` | float | 0.3-0.8 Hz | config | Speed of camera sway |
| `sway_amplitude` | float | 0.02-0.05 m | config | Position displacement |
| `sway_rotation_amplitude` | float | 0.3°-0.8° | config | Rotation wobble |

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Camera clips through thin wall** | Spherecast detects and compresses arm. If geometry thinner than camera radius, camera pops to Eli's shoulder (minimum distance). | Clipping breaks immersion more than anything. |
| **Player spins camera 360° rapidly** | Camera follows instantly. Smoothing applies to position only, never to player-driven rotation. | Input lag on rotation causes nausea. |
| **Eli walks through a doorway (tight → open)** | Arm compresses through doorframe, slowly extends as space opens. Extension deliberately slower than compression. | Sudden camera jumps on exit are jarring. |
| **Multiple POIs in auto-frame range** | Nearest POI wins. If equidistant, closest to camera center wins. Only one offset active at a time. | Competing offsets cause jitter. |
| **Player moves camera during auto-frame** | Offset cancels instantly. Does not resume until player stops camera input for 2s. | Player control always wins. |
| **Cinematic triggered while compressed** | Camera blends from current compressed position to cinematic position. No snap to default first. | Smooth transitions from any state. |
| **Pause during cinematic blend** | Blend freezes mid-interpolation. Resumes from exact point. | Universal pause freezes everything. |
| **Eli falls during cinematic** | Cinematic takes priority — authored path, not Eli's fall. Falls during cinematics are always scripted. | Cinematics override all behavior. |
| **Scene transition during cinematic** | Cinematic cancelled. Camera snaps to new scene spawn. | Clean scene boundaries. |
| **Camera at minimum + Eli in corner** | Holds at 0.5m minimum. If even that clips, moves to Eli's head position (first-person fallback). | Last-resort to prevent seeing through walls. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Player Controller | Hard | Reads position, rotation, velocity each frame. Receives state change signals (dialogue, traversal, sprint). |
| ggez Physics (Crashcat) | Hard | Spherecast for arm collision detection against scene geometry. |
| ggez Gameplay Runtime | Hard | System registration, update loop, scene lifecycle. Must update after Player Controller. |
| Event Bus | Soft | Subscribes to narrative events for cinematic triggers. Functions without (just no auto-cinematics). |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Player Controller (interactable detection) | Hard | Camera forward direction for interaction raycasts. |
| Ship Exploration | Soft | Camera position/forward for visibility queries. |
| Kino Drone | Hard | Camera state save/restore when switching to Kino first-person view. |
| Ship Atmosphere & Lighting | Soft | Camera position for fog/lighting calculations. |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `DEFAULT_ARM_LENGTH` | 3.5 m | 2.0-5.0 | Camera further from Eli. More spatial awareness. Above 5.0 Eli feels tiny. | Camera closer. More intimate. Below 2.0 feels claustrophobic in open spaces. |
| `MIN_ARM_LENGTH` | 0.5 m | 0.3-1.0 | Camera stays further in tight spaces. May clip more. | Camera gets very close. Below 0.3 effectively first-person. |
| `FOLLOW_SMOOTHING` | 0.15 | 0.01-0.3 | Floatier follow, cinematic lag. Above 0.3 feels disconnected. | Snappier, more responsive. Below 0.01 effectively instant. |
| `ARM_EXTEND_RATE` | 2.0 m/s | 1.0-4.0 | Camera returns to default faster after tight spaces. | Slower return. Below 1.0 feels like camera is stuck. |
| `PITCH_MIN` | -60° | -80° to -40° | Can look further down. | Can't look as far down. |
| `PITCH_MAX` | +70° | +50° to +85° | Can look further up. Above 85° has gimbal issues. | Can't look as far up. |
| `CAMERA_SENSITIVITY_X` | 1.0 | 0.3-3.0 | Faster horizontal rotation. | Slower horizontal rotation. |
| `CAMERA_SENSITIVITY_Y` | 0.8 | 0.3-3.0 | Faster vertical rotation. | Slower vertical rotation. |
| `SPRINT_ARM_EXTEND` | +0.5 m | 0-1.0 | More noticeable sprint camera pull. Above 1.0 is dramatic. | Less pull. At 0, sprint doesn't affect camera distance. |
| `SPRINT_PITCH_OFFSET` | -3° | -8° to 0° | Camera dips more on sprint. | Less or no pitch change on sprint. |
| `AUTO_FRAME_MAX_OFFSET` | 0.5 m | 0.2-1.0 | Stronger framing suggestion. Above 1.0 Eli moves too far off-center. | Subtler offset. Below 0.2 barely noticeable. |
| `AUTO_FRAME_POI_RANGE` | 8.0 m | 4.0-15.0 | POIs influence framing from further away. | Must be closer before framing kicks in. |
| `AUTO_FRAME_RESUME_DELAY` | 2.0 s | 0.5-5.0 | Longer before auto-framing re-engages after player input. | Re-engages quickly. Below 0.5 fights with player. |
| `CINEMATIC_BLEND_DURATION` | 0.6 s | 0.2-1.5 | Slower cinematic transitions. Above 1.5 feels sluggish. | Faster transitions. Below 0.2 feels like a cut. |
| `SWAY_FREQUENCY` | 0.5 Hz | 0.3-0.8 | Faster sway (anxious). | Slower sway (calm). |
| `SWAY_AMPLITUDE` | 0.03 m | 0.02-0.05 | More visible shake. Above 0.05 is distracting. | Subtler. Below 0.02 nearly imperceptible. |
| `SPHERECAST_RADIUS` | 0.2 m | 0.1-0.4 | Larger collision buffer. More conservative, fewer clips. | Tighter, may clip thin edges. |

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Cinematic transition | Smooth camera blend to authored angle | None (audio is handled by the scene/narrative system) | High |
| Dialogue framing | Instant cuts between angles | None | High |
| Handheld sway (cinematic) | Subtle position/rotation noise | None | Medium |
| Auto-frame offset | Eli shifts in frame, barely noticeable | None | Low |

The camera system itself produces no audio. Visual effects (motion blur, depth
of field) may be applied by the render pipeline based on camera state, but are
not owned by this system.

## UI Requirements

No UI elements. The camera system is entirely invisible to the player. Camera
sensitivity settings are exposed through the game's options/settings menu (owned
by the UI system, reading from camera config).

## Acceptance Criteria

- [ ] **Basic follow**: Camera follows Eli smoothly at default arm length. No jitter at 60 FPS.
- [ ] **Player rotation**: Mouse/right stick rotates camera. Yaw unlimited, pitch clamped. No input lag.
- [ ] **Arm collision**: Camera pulls in when walls are behind it. No clipping through geometry in standard Destiny corridors.
- [ ] **Tight corridor behavior**: Camera compresses to near-over-the-shoulder in corridors < 2m wide. Returns to default when space opens.
- [ ] **Compression instant, extension smooth**: Arm compresses instantly to prevent clipping. Arm extends at `ARM_EXTEND_RATE`, not instant.
- [ ] **First-person fallback**: In extreme corner cases (Eli backed into corner), camera moves to head position rather than clipping.
- [ ] **Auto-frame offset**: Eli shifts in frame when near a POI. Offset is subtle (max 15% screen width). Player input cancels it instantly.
- [ ] **Cinematic transitions**: Camera blends smoothly to authored positions on cinematic trigger. Blend duration matches config.
- [ ] **Dialogue framing**: Camera frames two-shot on dialogue start. Cuts between angles on node changes (instant, no blend).
- [ ] **Traversal camera**: Camera holds or transitions to authored angle during traversals. Returns to exploration on completion.
- [ ] **Sprint offset**: Camera arm extends and pitch lowers during sprint. Reverts on sprint end.
- [ ] **Universal pause**: Pause freezes camera in any state. Unpause resumes exactly. No snapping or re-interpolation.
- [ ] **Handheld sway**: Cinematic mode applies Perlin noise-based sway. Sway pauses on game pause.
- [ ] **Scene transition**: Camera snaps to spawn position on new scene load. No interpolation from previous scene.
- [ ] **Performance**: Camera update completes within 0.5ms per frame. Spherecast is the most expensive operation.
- [ ] **All tuning values externalized**: Every parameter from Tuning Knobs loaded from config.

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Should depth of field be applied during dialogue (blur background, focus on speaker)? | Art Director | Before visual polish | — |
| Should motion blur be applied during sprint or fast camera movement? | Art Director | Before visual polish | — |
| How should the Kino Drone camera work? First-person with different controls, or same third-person following the drone? | Kino Drone GDD | When Kino Drone is designed | — |
| Should cinematic cameras support letterboxing (black bars) for extra drama? | Creative Director | Before cinematic implementation | — |
| Photo mode — should we support a free camera for screenshots? | UX Designer | Alpha milestone | — |
