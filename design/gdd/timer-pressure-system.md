# Timer & Pressure System

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-31
> **Implements Pillar**: Pillar 2 (Survival with Purpose)

## Overview

The Timer & Pressure System is a universal countdown and scheduling service that
any game system can use to create, query, halt, resume, and cancel time-limited
events. When Destiny drops out of FTL and the Stargate activates, this system runs
the planetary departure countdown. When the power grid fails, it tracks the
emergency battery's 30-minute window. When an episode triggers a crisis — hull
breach, CO2 buildup, alien approach — this system counts down the deadline and
broadcasts warnings at configurable thresholds.

Each timer has a **completion event** (the Event Bus event it fires on expiry),
optional **warning events** at configurable thresholds, and optional **cancel
conditions** (Event Bus events that cancel the timer early — e.g., a CO2 buildup
timer cancels when lime is added to the scrubbers). Multiple timers run
concurrently, and each can be individually halted and resumed. The system also
supports **cooldown timers** — timers that count *toward* readiness rather than
toward a deadline (e.g., FTL drive cooldown: the drive becomes available after the
timer completes, but there is no penalty for waiting longer).

The player never interacts with the Timer system directly — they see its effects
through diegetic cues: alarm lighting, Eli's urgency, and automatic consequences
(like gate return on planet timer expiry). All active timers are visible on a
**dedicated Kino Remote screen**, giving the player a single place to see every
countdown and cooldown currently running. All timers respect universal pause — when
the game is paused, every timer freezes exactly.

## Player Fantasy

The Timer & Pressure System serves the fantasy of **living on a ship where
something is always happening.** There's always a clock running somewhere — an FTL
cooldown ticking toward the next jump window, a planetary departure countdown
during supply runs, a repair deadline before a system degrades past the point of
no return. But these clocks don't create dread — they create **excitement**. Every
timer is a promise that something is about to change.

When Destiny drops out of FTL and the gate activates, the countdown isn't a
punishment — it's a challenge: "How much can I accomplish before time's up?" When
the FTL cooldown finishes and the drive hums to readiness, it's not relief from
pressure — it's a new opportunity: "Where do we go next?" The timers create the
rhythm of life aboard Destiny — the heartbeat of a ship that never stops moving.

This serves **Pillar 2 (Survival with Purpose)**: timers exist because the story
demands urgency, not because the game needs artificial difficulty. Every countdown
has a narrative reason. The planet timer exists because Destiny *will* jump to FTL
— it doesn't wait for you. The crisis timer exists because the CO2 *is* building
up. The excitement comes from understanding *why* the clock is ticking and knowing
your actions can change the outcome.

## Detailed Design

### Core Rules

1. **Timer data shape**: Each timer is an object with:
   - `id`: string (unique, e.g., `"planet-departure"`, `"co2-crisis"`, `"ftl-cooldown"`)
   - `type`: enum — `Countdown` (time remaining until consequence) or `Cooldown` (time remaining until ready)
   - `duration`: float (total time in game-seconds)
   - `remaining`: float (current time left, decremented each tick)
   - `state`: enum — `Pending`, `Running`, `Halted`, `Expired`, `Cancelled`, `Ready` (cooldown complete)
   - `completion_event`: string (Event Bus event to fire on expiry/readiness)
   - `completion_payload`: object (data sent with completion event)
   - `warnings`: array of `{ threshold: float, event: string, payload: object, fired: boolean }` — warning events fire when `remaining` crosses the threshold (in seconds remaining)
   - `start_conditions`: array of Event Bus event names — timer starts (or restarts) when any of these fire. If provided, timer is created in `Pending` state instead of `Running`.
   - `pause_conditions`: array of Event Bus event names — timer halts when any of these fire
   - `resume_conditions`: array of Event Bus event names — timer resumes when any of these fire
   - `cancel_conditions`: array of Event Bus event names — timer is cancelled when any of these fire
   - `dilation_threshold`: float (optional — seconds remaining at which auto-dilation kicks in)
   - `dilation_scale`: float (optional — time scale applied when below dilation_threshold; default 1.0)
   - `tags`: string[] (for filtering/querying — e.g., `["planet"]`, `["crisis", "life-support"]`)
   - `visible`: boolean (whether this timer appears on the Kino Remote timer screen)

2. **Timer creation**: Any system creates a timer by calling the Timer system's
   public API: `createTimer(config)`. The Timer system registers it and begins
   ticking (or enters `Pending` state if `start_conditions` are defined). A
   `timer:created` event is published with the timer's ID and tags.

3. **Tick processing**: Each game tick (60 FPS), all `Running` timers decrement
   `remaining` by `delta`. When `remaining` crosses a warning threshold, the
   warning event fires (once — `fired` flag prevents repeats). When `remaining`
   reaches 0, the `completion_event` fires and the timer transitions to `Expired`
   (countdown) or `Ready` (cooldown).

4. **Halt and resume**: Any system can halt a specific timer by ID
   (`haltTimer(id)`) — the timer stops decrementing but remains registered.
   `resumeTimer(id)` resumes ticking from where it left off. Events:
   `timer:halted`, `timer:resumed`.

5. **Event-driven lifecycle**: Timers can be fully controlled through Event Bus
   events, making them declarative:
   - `start_conditions` → transitions from `Pending` to `Running` (or restarts
     from `Expired`/`Ready` by resetting `remaining` to `duration`)
   - `pause_conditions` → transitions from `Running` to `Halted`
   - `resume_conditions` → transitions from `Halted` to `Running`
   - `cancel_conditions` → transitions to `Cancelled` from any active state
   - Manual API calls (`haltTimer`, `resumeTimer`, `cancelTimer`) work alongside
     event-driven control — either can trigger the transition.

6. **Cancellation**: Cancelled timers publish `timer:cancelled` with the timer's
   ID, tags, and remaining time (so systems know how much time was left). Cancelled
   timers are removed from the active set after the event is published.

7. **Concurrent timers**: No limit on concurrent active timers. Each ticks
   independently. The Kino Remote timer screen shows all visible timers sorted
   by urgency (least remaining time first).

8. **Universal pause**: When the game enters paused state (`game:paused`), ALL
   timers freeze — `delta` is not applied. On `game:resumed`, all timers resume
   exactly. This is handled at the tick level, not per-timer.

9. **Countdown consequences**: The Timer system only fires events — it does NOT
   implement consequences. The planet departure timer fires
   `timer:planet:expired`; the Stargate system hears that and triggers the
   auto-return. The CO2 crisis timer fires `timer:co2:expired`; the Episode
   system hears that and triggers the crisis. This keeps the Timer system
   generic.

10. **Time scale (drama time)**: The Timer system supports a global `timeScale`
    modifier (default 1.0) that multiplies the `delta` applied to all Running
    timers. A `timeScale` of 0.5 makes all timers tick at half speed ("bullet
    time"); 2.0 makes them tick double speed. Time scale is controlled via:
    - **Event-driven**: `timer:timescale:set` event with `{ scale: float }` payload
    - **API**: `setTimeScale(scale)` / `getTimeScale()`
    - **Auto-dilation**: Timers can define a `dilation_threshold` — when
      `remaining` drops below this threshold, the Timer system automatically
      applies a per-timer `dilation_scale` (e.g., final 30 seconds of a crisis
      timer tick at 0.5x, giving the player more real-world time to act).
    Time scale stacks: `effective_delta = delta * globalTimeScale * timerDilationScale`.
    Global time scale does NOT affect game pause — pause is absolute.

11. **Time skip / acceleration**: The player can accelerate time to fast-forward
    through downtime (e.g., waiting for FTL cooldown, waiting for the next gate
    window). Two modes:
    - **Accelerate**: `setTimeScale(N)` with N > 1 (e.g., 4x, 8x, 16x). All
      timers tick faster. Game simulation ticks faster (consumption, degradation).
      The Kino Remote shows a fast-forward indicator. The player can cancel
      acceleration at any time by pressing any input.
    - **Skip to event**: `skipToTimer(id)` — instantly sets `remaining` to 0 for
      the target timer AND advances all other running timers by the same elapsed
      amount. **Full simulation advance**: all systems that tick with game time
      (resource consumption, ship degradation, NPC schedules, ambient events)
      also advance by the skipped duration. Warning events that would have fired
      during the skip are batched and fired in order.
    - **Skip restrictions**: Time skip is blocked when any `Countdown`-type timer
      with tag `"crisis"` or `"urgent"` is active. You cannot skip through a
      crisis. The Kino Remote shows "Cannot skip — active crisis" when blocked.
    - **Acceleration access**: Context-dependent — available from the Kino Remote
      Timer screen OR when Eli is idle (sitting, standing still). Blocked during
      active gameplay (traversals, dialogue, combat).
    - **Auto-cancel acceleration**: If a warning event fires during acceleration
      (e.g., resource drops to Low), acceleration automatically drops back to 1x
      and an alert is shown.

12. **Timer queries**: Systems can query active timers:
    - `getTimer(id)` — returns timer state
    - `getTimersByTag(tag)` — returns all timers with a given tag
    - `getActiveTimers()` — returns all Running timers
    - `getRemainingTime(id)` — shorthand for remaining seconds

### States and Transitions

| State | Entry Condition | Exit Conditions | Behavior |
|-------|----------------|-----------------|----------|
| **Pending** | Created with `start_conditions` defined | `start_conditions` event fires → Running. `cancel_conditions` event → Cancelled. | Timer exists but is not ticking. Visible on Kino Remote as "Waiting..." if `visible`. |
| **Running** | Created without `start_conditions`, or `start_conditions` event fires, or `resumeTimer()` called | `remaining` reaches 0 → Expired/Ready. `pause_conditions` event or `haltTimer()` → Halted. `cancel_conditions` event or `cancelTimer()` → Cancelled. | Timer is actively decrementing. Warning events fire at thresholds. |
| **Halted** | `pause_conditions` event fires or `haltTimer()` called while Running | `resume_conditions` event or `resumeTimer()` → Running. `cancel_conditions` event → Cancelled. | Timer frozen at current `remaining`. Displayed as paused on Kino Remote. |
| **Expired** | Countdown timer `remaining` reaches 0 | `start_conditions` event → Running (restart). Removal after expiry handling. | `completion_event` fires. Timer remains briefly for query, then removed. |
| **Ready** | Cooldown timer `remaining` reaches 0 | `start_conditions` event → Running (restart). Explicit removal. | `completion_event` fires. Timer stays in `Ready` state (queryable as "available") until restarted or removed. |
| **Cancelled** | `cancel_conditions` event fires or `cancelTimer()` called | Removed from active set. | `timer:cancelled` event fires. Timer removed. |

**Key transitions:**
- `Pending → Running → Expired/Ready` is the normal lifecycle
- `Running ↔ Halted` is pause/resume
- Any active state → `Cancelled` is abort
- `Expired/Ready → Running` is restart (via `start_conditions`)

### Interactions with Other Systems

| System | Direction | Interface |
|--------|-----------|-----------|
| **Event Bus** | Hard dependency | Publishes: `timer:created`, `timer:halted`, `timer:resumed`, `timer:cancelled`, plus all per-timer `completion_event` and `warning` events. Subscribes: `game:paused`, `game:resumed` (universal pause), plus all `start_conditions`, `pause_conditions`, `resume_conditions`, `cancel_conditions` from registered timers. |
| **Stargate & Planetary Runs** *(undesigned)* | Inbound (creator) | Creates the planet departure countdown timer. Subscribes to `timer:planet:warning` and `timer:planet:expired` to trigger warnings and auto-return. |
| **Ship State** | Inbound (creator) | Creates the emergency battery timer on total power failure (30-minute countdown). May create degradation deadline timers for critical systems. |
| **Resource & Inventory** | Inbound (cancel source) | Resource events (e.g., lime added) can serve as `cancel_conditions` for crisis timers (e.g., CO2 buildup cancelled by resupply). |
| **Episode Narrative** *(undesigned)* | Bidirectional | Episodes create crisis timers with narrative deadlines. Episode system subscribes to timer warnings/expiry to trigger story beats. May halt/resume timers during cinematics. |
| **Kino Remote** *(undesigned)* | Outbound (read) | Reads all visible timers for the dedicated timer screen. Queries `getActiveTimers()` filtered by `visible: true`. |
| **Crew Dialogue & Choice** *(undesigned)* | Outbound (context) | Dialogue system may query timer state for urgency-contextual dialogue (e.g., Eli speaks faster when planet timer is under 60 seconds). |
| **Ship Atmosphere & Lighting** *(undesigned)* | Outbound (events) | Subscribes to timer warning events to trigger alarm lighting when deadlines approach. |
| **Audio & Ambience** *(undesigned)* | Outbound (events) | Subscribes to timer events for urgency audio cues (alarm klaxons, countdown beeps, heartbeat sounds). |
| **Save/Load** *(undesigned)* | Outbound (serialization) | All active timers serialize as part of save state. On load, timers restore with correct `remaining` values. |

**Provisional contracts:**
- Stargate & Planetary Runs: exact planet timer duration and warning thresholds TBD
- Episode Narrative: crisis timer creation API and story-beat trigger protocol TBD

## Formulas

### Timer Tick (with time scale)

```
timer_dilation = (remaining <= dilation_threshold) ? dilation_scale : 1.0
effective_delta = delta * globalTimeScale * timer_dilation
remaining = max(0, remaining - effective_delta)
```

| Variable | Type | Range | Source | Description |
|----------|------|-------|--------|-------------|
| `remaining` | float | 0 – `duration` | timer state | Seconds left |
| `delta` | float | ~0.0167 | ggez runtime | Frame delta in seconds (1/60 at 60 FPS) |
| `globalTimeScale` | float | 0.1 – 3.0 | Timer system | Global speed modifier for all timers |
| `timer_dilation` | float | 0.1 – 3.0 | per-timer config | Auto-dilation when below threshold |

### Warning Threshold Check

```
for each warning in timer.warnings:
   if !warning.fired && remaining <= warning.threshold:
      emit(warning.event, warning.payload)
      warning.fired = true
```

### Progress Ratio (for Kino Remote display)

```
progress = 1.0 - (remaining / duration)       // Countdown: 0→1 as time runs out
progress = 1.0 - (remaining / duration)       // Cooldown: 0→1 as readiness approaches
```

No complex scaling or curves — timers are linear by design. If a system needs
non-linear urgency (e.g., CO2 buildup accelerating), that system owns the curve
and uses the Timer system only for the deadline.

## Edge Cases

| Scenario | Expected Behavior | Rationale |
|----------|------------------|-----------|
| **Timer created with 0 duration** | Immediately transitions to Expired/Ready and fires completion event on next tick. | Valid use case — "fire this event next frame." |
| **Multiple timers expire on same frame** | All completion events fire in creation order. No priority system between timers. | Deterministic ordering prevents race conditions. |
| **Cancel condition fires for a Halted timer** | Timer transitions to Cancelled. Halted timers are still listening for cancel events. | A paused crisis can still be resolved — e.g., lime added while CO2 timer is halted during a cinematic. |
| **Start condition fires for an already-Running timer** | Timer restarts — `remaining` resets to `duration`, all warning `fired` flags reset. | Restart semantics. Allows repeating timers (FTL cooldown restarts each jump). |
| **Warning threshold set beyond duration** | Warning never fires (remaining will never be that high). Silently ignored. | Misconfiguration shouldn't crash. Log a dev warning. |
| **Timer halted, then game paused, then game resumed** | Timer stays Halted. Game pause/resume doesn't override per-timer halt state. | Per-timer halt is independent from global pause. |
| **All timers cancelled at once (e.g., scene transition)** | `cancelAllTimers()` API cancels everything. Each fires `timer:cancelled`. | Scene unload needs a clean slate. |
| **Save/Load while timers are Running** | Serialize all active timers with current `remaining`, state, and fired flags. On load, timers resume from saved state — no time lost or gained. | Timer continuity across saves is essential for planet timers and crisis deadlines. |
| **Duplicate timer ID** | New timer replaces old. Old timer is silently cancelled (no cancel event). Dev warning logged. | Prevent accumulating stale timers from repeated creation. |
| **Cancel condition event has a payload filter** | Cancel conditions match on event name only, not payload. If payload-based cancellation is needed, the owning system should call `cancelTimer(id)` explicitly. | Keeps the Timer system simple. Payload filtering is business logic that belongs in the consumer. |
| **Skip to event while multiple timers running** | All timers advance by the same elapsed amount. Some may expire during the skip — their completion events fire in chronological order. | Consistent time advancement across all systems. |
| **Skip requested during a crisis** | Skip rejected. Kino Remote shows "Cannot skip — active crisis." Player must resolve or wait out the crisis. | Prevents skipping past dramatic tension. |
| **Acceleration running when crisis timer starts** | Auto-cancel acceleration immediately. Drop to 1x. Alert the player. | New crisis overrides convenience fast-forward. |

## Dependencies

**Upstream (this system depends on):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Event Bus | Hard | Publishes all `timer:*` events. Subscribes to lifecycle condition events and `game:paused`/`game:resumed`. |
| Save/Load (interface only) | Hard (contract) | `serialize()`/`deserialize()` for active timer state. Full implementation deferred to VS tier. |

**Downstream (depends on this system):**

| System | Dependency Type | What They Need |
|--------|----------------|----------------|
| Stargate & Planetary Runs | Hard | Planet departure countdown, warning/expiry events |
| Episode Narrative | Hard | Crisis timer creation, deadline events for story triggers |
| Kino Remote | Soft | Active timer list for dedicated timer screen display |
| Crew Dialogue & Choice | Soft | Timer queries for urgency-contextual dialogue |
| Ship Atmosphere & Lighting | Soft | Warning events for alarm lighting |
| Audio & Ambience | Soft | Timer events for urgency audio cues |
| Ship State | Soft | Creates emergency battery timer; reads remaining time |
| Resource & Inventory | Soft | Resource events serve as cancel conditions for crisis timers |

## Tuning Knobs

| Parameter | Default | Safe Range | Effect of Increase | Effect of Decrease |
|-----------|---------|------------|-------------------|-------------------|
| `PLANET_TIMER_DURATION` | 900s (15 min) | 300-1800s | More time on planets. Less pressure, more exploration. | Tighter runs. More exciting but less time to scavenge. |
| `PLANET_WARNING_THRESHOLD` | 120s (2 min) | 30-300s | Earlier warning. More time to react. | Later warning. More surprise urgency. |
| `PLANET_FINAL_WARNING` | 30s | 10-60s | Earlier final warning. | Tighter final warning window. |
| `FTL_COOLDOWN_DURATION` | 1800s (30 min) | 600-3600s | Longer between jump windows. More time at each stop. | Faster travel. Less time at each location. |
| `EMERGENCY_BATTERY_DURATION` | 1800s (30 min) | 600-3600s | More time during power failure. Less urgent. | Tighter deadline. More pressure. |
| `EXPIRED_TIMER_LINGER_SECONDS` | 2.0s | 0.5-5.0 | Expired timers queryable longer. | Quicker cleanup. |
| `MAX_CONCURRENT_TIMERS` | 32 | 16-64 | More timers allowed. | Fewer — forces systems to be economical. |
| `DEFAULT_TIME_SCALE` | 1.0 | 0.1-3.0 | Global timer speed. 1.0 = real-time. | Slow-mo baseline. |
| `CRISIS_DILATION_SCALE` | 0.5 | 0.2-0.8 | How much crisis final moments slow down. Lower = more bullet time. | Less dilation. Final moments feel faster. |
| `CRISIS_DILATION_THRESHOLD` | 30s | 10-60s | When auto-dilation kicks in. Higher = longer drama window. | Shorter drama window. |
| `MAX_ACCELERATION_SCALE` | 16.0 | 4.0-32.0 | Max fast-forward speed. Higher = faster skip. | Slower max skip speed. |
| `SKIP_BLOCKED_TAGS` | `["crisis", "urgent"]` | string[] | Timer tags that block time skip. | — |

Note: Most timer durations are NOT tuning knobs on the Timer system — they're
defined by the systems that create the timers (Stargate defines planet timer
duration, Ship State defines battery duration). The values above are **suggested
defaults** that will live in those systems' configs. The Timer system itself only
tunes `EXPIRED_TIMER_LINGER_SECONDS` and `MAX_CONCURRENT_TIMERS`.

## Visual/Audio Requirements

| Event | Visual Feedback | Audio Feedback | Priority |
|-------|----------------|---------------|----------|
| Timer warning (first threshold) | Kino Remote timer turns amber. Subtle corridor light shift. | Warning chime. Ambient tension increases. | High |
| Timer final warning | Kino Remote timer flashes red. Emergency lighting in relevant areas. | Urgent alarm tone. Eli verbal cue ("We need to go!"). | High |
| Timer expired | Kino Remote timer shows "EXPIRED". | Alarm klaxon or consequence-specific sound. | High |
| Cooldown ready | Kino Remote timer turns green with "READY" label. | Satisfying ready chime (like a microwave ding, but Ancient). | Medium |
| FTL jump final minute | **Ship-wide red lighting** — all corridor and room lights shift red. | Low pulsing alarm. Ship vibration rumble. | High |
| FTL countdown (active) | **Above-doorway displays** show FTL timer throughout the ship. Ancient-styled countdown visible at every doorway. | — | High |
| Time acceleration active | Fast-forward visual indicator (HUD overlay). Motion blur or slight visual speed effect. | Ambient sounds pitch-shifted higher. Time-lapse audio effect. | Medium |
| Time skip | Brief transition/wipe effect. | Whoosh/temporal shift sound. | Medium |
| Timer cancelled | Timer fades from Kino Remote display. | Quiet resolution tone. | Low |

**Drama-time dilation visuals**: Full bullet-time visual treatment — vignette,
desaturated edges, heartbeat audio layer. BUT characters move at **normal speed**.
The clock slows, not the world — the player genuinely gets more done in dilated
time. This is not cinematic slow-motion; it's extra time to act.

**Doorway displays**: FTL jump and cooldown timers are shown on Ancient displays
above every doorway in the ship. These are **diegetic** — part of Destiny's own
status system, not a HUD element. FTL countdown symbols are readable at **knowledge
tier 0** (immediately) — Eli recognizes Ancient numerals because he solved the
Ancient equation to join the Stargate program. He's the first to notice the
countdown: *"Uhh guys, why is that counting down?"* — a discovery moment that
establishes the FTL cycle mechanic through character, not tutorial. Only FTL timers
appear on doorway displays; all other timers are Kino Remote only.

## UI Requirements

| Information | Display Location | Update Trigger | Condition |
|-------------|-----------------|----------------|-----------|
| All active timers | Kino Remote — dedicated Timer screen | `timer:created`, `timer:cancelled`, each tick | Always available |
| Timer progress bars | Kino Remote Timer screen | Each tick (60 FPS) | Per visible timer |
| Countdown/cooldown labels | Kino Remote Timer screen | On creation | Type-specific label (e.g., "Gate Window", "FTL Cooldown") |
| FTL timer (ship priority) | **Above-doorway Ancient displays** throughout ship | Each tick | When FTL jump or FTL cooldown timer is active |
| Crisis timer (most urgent) | Kino Remote — main screen alert | Warning threshold crossed | When crisis-tagged timer < warning threshold |
| Time skip availability | Kino Remote Timer screen | On timer state change | "Skip" button greyed out when crisis active |
| Fast-forward indicator | Screen overlay (non-diegetic exception) | On acceleration start/stop | During time acceleration only |

Note: The fast-forward indicator and above-doorway FTL displays are the only
non-Kino-Remote timer UI. The doorway displays are diegetic (part of the ship).
The fast-forward indicator is non-diegetic (screen overlay) because the player
needs to see it without opening Kino Remote.

## Acceptance Criteria

- [ ] **Timer creation**: `createTimer(config)` registers a timer and publishes `timer:created`. Timer begins in `Running` or `Pending` state based on config.
- [ ] **Countdown expiry**: A countdown timer reaching 0 fires its `completion_event` and transitions to `Expired`.
- [ ] **Cooldown readiness**: A cooldown timer reaching 0 fires its `completion_event` and transitions to `Ready`.
- [ ] **Warning events**: Warnings fire exactly once when `remaining` crosses each threshold. Warnings fire in descending order as time decreases.
- [ ] **Halt/Resume**: `haltTimer(id)` stops ticking; `resumeTimer(id)` resumes from exact remaining time. Events published for each.
- [ ] **Event-driven lifecycle**: `start_conditions`, `pause_conditions`, `resume_conditions`, `cancel_conditions` all trigger correct state transitions when their events fire.
- [ ] **Cancellation**: Cancelled timers fire `timer:cancelled` with remaining time in payload, then are removed.
- [ ] **Concurrent timers**: 10+ timers running simultaneously with independent state. No crosstalk.
- [ ] **Universal pause**: `game:paused` freezes all Running timers. `game:resumed` resumes them. Per-timer Halted state is independent from global pause.
- [ ] **Time scale (global)**: `setTimeScale(0.5)` causes all Running timers to tick at half speed. `setTimeScale(2.0)` doubles tick speed. Affects all timers equally.
- [ ] **Auto-dilation**: A timer with `dilation_threshold: 30` and `dilation_scale: 0.5` ticks at half speed when `remaining` drops below 30 seconds. Dilation stacks with global time scale.
- [ ] **Timer queries**: `getTimer`, `getTimersByTag`, `getActiveTimers`, `getRemainingTime` return correct data.
- [ ] **Duplicate ID handling**: Creating a timer with an existing ID replaces the old timer. Dev warning logged.
- [ ] **Serialization**: All active timers serialize/deserialize correctly — remaining time, state, fired flags, and current time scale all preserved.
- [ ] **Performance**: Ticking 32 concurrent timers completes in < 0.1ms per frame. Timer operations are O(1) by ID, O(n) for tag queries.
- [ ] **Time acceleration**: Player can set time scale > 1 for fast-forward. All timers and game simulation advance proportionally. Any input cancels acceleration back to 1x.
- [ ] **Skip to event**: `skipToTimer(id)` advances all timers by the target's remaining time. Warning events batch-fire in order. Other systems (consumption, degradation) advance by the same elapsed time.
- [ ] **Skip blocked by crisis**: Time skip is rejected when a countdown timer with `"crisis"` or `"urgent"` tag is Running. UI feedback shown.
- [ ] **Auto-cancel acceleration**: Acceleration drops to 1x when a warning event fires during fast-forward.
- [ ] **No consequence logic**: Timer system fires events only — never directly modifies game state (no auto-return, no crisis trigger).

## Open Questions

All open questions have been resolved:

| Question | Resolution |
|----------|-----------|
| Should time skip advance the full game simulation? | **Yes — full simulation advance.** NPC schedules, resource consumption, ship degradation, and ambient events all tick forward during time skip. |
| What's the right planet timer duration? | **Varies by story point, 10-20 min default.** Simple resource runs (lime only) get shorter windows. Multi-objective missions (food + research) get longer. Exact values need playtesting. |
| Should the player see exact seconds remaining? | **Yes — exact countdown (3:42).** Precise numbers on Kino Remote and doorway displays. Player can make informed decisions. |
| Can time acceleration be initiated from anywhere? | **Context-dependent.** Available from Kino Remote OR when Eli is idle (sitting, standing still). Blocked during active gameplay (traversals, dialogue, combat). |
| How should drama-time dilation feel? | **Full bullet-time visuals (vignette, desaturated edges, heartbeat audio) BUT characters move at normal speed.** The clock slows, not the world — player genuinely gets more done in dilated time. |
| Which timers appear on doorway displays? | **FTL only.** FTL jump and cooldown timers on doorway Ancient displays. All other timers are Kino Remote only. |
| At what knowledge tier do doorway FTL displays become readable? | **Tier 0 (immediate).** FTL countdown symbols are recognizable without Ancient knowledge — safety-critical information is always readable. |
