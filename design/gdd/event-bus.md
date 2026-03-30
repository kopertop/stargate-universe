# Event Bus

> **Status**: Designed
> **Author**: User + Claude
> **Last Updated**: 2026-03-29
> **Implements Pillar**: All (infrastructure enabling system communication)

## Overview

The Event Bus is a centralized publish-subscribe messaging system that enables
decoupled communication between all game systems. Systems publish typed events
(e.g., `ship:power:changed`, `gate:activated`, `crew:dialogue:choice-made`) and
other systems subscribe to events they care about. No system needs to import or
reference another directly — the Event Bus is the only shared dependency.

Players never interact with the Event Bus directly. It is invisible
infrastructure. Its quality is measured by what it enables: when the player
repairs a power conduit, the lights brighten, the ambient hum changes, the crew
reacts, and the Kino Remote updates — all because one `ship:power:restored`
event rippled through every subscribed system.

## Player Fantasy

The Event Bus serves the fantasy of a **living, reactive ship**. When something
happens on Destiny, the entire ship responds. Fix the water recycler and crew
members visibly relax, the rationing UI updates, and the ambient dripping sound
stops. Trigger an alert and lights shift to red, the ship groans, crew runs to
stations, and the Kino Remote flashes warnings.

This system serves **Pillar 1: The Ship IS the World** — Destiny feels alive
because every change propagates realistically through interconnected systems,
just like a real ship. It also serves **Pillar 3: Earned Discovery** — the
player sees the *consequences* of their actions ripple through the world,
reinforcing that their exploration and repairs matter.

## Detailed Design

### Core Rules

1. The Event Bus is a singleton `mitt` instance wrapped in a typed `GameEventBus`
   module that provides the public API
2. Event names use namespaced colon-separated strings: `domain:subject:action`
3. All event types and their payloads are defined in a single `GameEvents`
   TypeScript type map (mitt's generic parameter), providing compile-time safety
4. Systems subscribe during initialization and unsubscribe during cleanup
5. Events fire synchronously (mitt's default) — handlers execute immediately in
   subscription order
6. The wildcard `'*'` handler receives ALL events (useful for debugging, logging,
   and the Save/Load system's state tracking)

### Event Naming Convention

| Domain | Examples | Owner System |
|--------|----------|-------------|
| `ship` | `ship:power:changed`, `ship:section:unlocked`, `ship:lifesupport:critical` | Ship State |
| `gate` | `gate:dial:started`, `gate:activated`, `gate:closed` | Stargate & Planetary Runs |
| `resource` | `resource:collected`, `resource:consumed`, `resource:depleted` | Resource & Inventory |
| `crew` | `crew:dialogue:started`, `crew:choice:made`, `crew:morale:changed` | Crew Dialogue & Choice |
| `episode` | `episode:started`, `episode:crisis:triggered`, `episode:completed` | Episode Narrative |
| `timer` | `timer:planet:warning`, `timer:planet:expired`, `timer:emergency:started` | Timer & Pressure |
| `player` | `player:interact`, `player:entered:section`, `player:kino:deployed` | Player Controller |
| `puzzle` | `puzzle:started`, `puzzle:solved`, `puzzle:failed` | Ancient Tech Puzzles |

### States and Transitions

N/A — the Event Bus is stateless. It routes messages; it holds no state of its own.

### Interactions with Other Systems

| System | Direction | Events | Purpose |
|--------|-----------|--------|---------|
| All 17 systems | Inbound (subscribe) | Various | React to game state changes |
| All 17 systems | Outbound (publish) | Various | Announce game state changes |
| Save/Load | Inbound (wildcard) | `*` | Track state-changing events for save serialization |
| Ship Atmosphere | Inbound | `ship:*` | Adjust lighting/fog when ship state changes |
| Audio & Ambience | Inbound | `ship:*`, `gate:*`, `timer:*` | Trigger sound effects and music changes |
| Kino Remote | Inbound | `ship:*`, `resource:*`, `episode:*` | Update diegetic UI displays |

## Formulas

N/A — the Event Bus performs no calculations. It is a message routing system.
All game math lives in the systems that publish and consume events.

## Edge Cases

| Edge Case | What Happens | Resolution |
|-----------|-------------|------------|
| **Handler throws an error** | One subscriber's error could prevent subsequent subscribers from receiving the event | Wrap each handler invocation in try/catch. Log the error but continue dispatching to remaining subscribers. Never let one broken system silence the bus. |
| **Event published with no subscribers** | Event fires into the void | This is fine and expected. New systems subscribe as they initialize. No warning needed. |
| **Subscriber registers twice for same event** | Duplicate handler fires twice per event | mitt allows this by default. Document that systems must track their own subscriptions and call `off()` during cleanup. |
| **Subscriber forgets to unsubscribe on scene unload** | Memory leak; stale handlers fire on destroyed objects | Provide a `scopedBus(cleanup)` helper that auto-unsubscribes all listeners when a cleanup function is called (tied to ggez scene dispose lifecycle). |
| **Circular event chains** | System A publishes event X, System B hears it and publishes event Y, System A hears Y and publishes X again — infinite loop | Set a max re-entry depth (default: 8). If an event publish triggers a chain deeper than the limit, log an error and drop the event. This catches bugs during development without crashing the game. |
| **High-frequency events (e.g., player position)** | Publishing every frame generates thousands of events per second | Do NOT use the event bus for per-frame data. Per-frame values (player position, camera angle) should be read directly from the owning system. The event bus is for *state changes*, not continuous streams. |

## Dependencies

**Upstream (this system depends on):** None. The Event Bus is the foundation
layer — it has zero dependencies and is the first system initialized.

**Downstream (depends on this system):**

| System | Dependency Type | Interface |
|--------|----------------|-----------|
| Ship State | Hard | Publishes `ship:*` events on state changes. Subscribes to `resource:*` for supply updates. |
| Resource & Inventory | Hard | Publishes `resource:*` events. Subscribes to `player:interact` for item pickup. |
| Timer & Pressure | Hard | Publishes `timer:*` events. Subscribes to `gate:activated` to start countdowns. |
| Crew Dialogue & Choice | Hard | Publishes `crew:*` events. Subscribes to `episode:*` for dialogue triggers. |
| Crew AI & Schedule | Hard | Subscribes to `ship:*`, `episode:*` to adjust NPC behavior. |
| Episode Narrative | Hard | Publishes `episode:*` events. Subscribes to `crew:choice:made`, `ship:*`, `timer:*` for story triggers. |
| Audio & Ambience | Soft | Subscribes to `ship:*`, `gate:*`, `timer:*` for reactive audio. Functions without (just silent). |
| Ship Atmosphere & Lighting | Soft | Subscribes to `ship:*` for dynamic lighting. Functions without (just static). |
| Save/Load | Hard | Uses wildcard `*` to track all state-changing events. |
| Kino Remote | Soft | Subscribes to `ship:*`, `resource:*`, `episode:*` for UI updates. |

**Library dependency:** `mitt` (npm package, ~200 bytes)

## Tuning Knobs

| Knob | Default | Safe Range | Effect if Too High | Effect if Too Low |
|------|---------|------------|--------------------|--------------------|
| `MAX_REENTRY_DEPTH` | 8 | 4-16 | Allows longer event chains (potentially masking bugs) | Legitimate chains get cut short |
| `DEBUG_LOG_EVENTS` | `false` | boolean | Logs every event to console — useful for dev, devastating for prod performance | No event logging — harder to debug |
| `DEBUG_LOG_FILTER` | `'*'` | string pattern | When debug logging is on, only log events matching this pattern (e.g., `'ship:*'`) | N/A |

## Visual/Audio Requirements

N/A — invisible infrastructure. Visual and audio systems subscribe to events
but the Event Bus itself has no visual or audio output.

## UI Requirements

N/A — no player-facing UI. The debug event logger (when `DEBUG_LOG_EVENTS` is
enabled) outputs to the browser console, not the game UI.

## Acceptance Criteria

1. **Typed events compile**: Publishing an event with the wrong payload type
   produces a TypeScript compile error
2. **Subscribe and receive**: A system subscribes to `ship:power:changed` and
   receives the event when another system publishes it, with the correct payload
3. **Wildcard works**: A `'*'` subscriber receives events from all domains
4. **Unsubscribe stops delivery**: After calling `off()`, a handler no longer
   receives events
5. **Scoped cleanup**: When a scene unloads and calls its cleanup function, all
   subscriptions registered through `scopedBus()` are removed (no stale handlers)
6. **Error isolation**: If a handler throws, subsequent handlers for the same
   event still fire, and the error is logged
7. **Re-entry protection**: A circular event chain exceeding `MAX_REENTRY_DEPTH`
   logs an error and stops without crashing
8. **Performance**: Publishing an event with 10 subscribers completes in < 0.1ms
   (well within the 16.6ms frame budget)
9. **No per-frame abuse**: No system publishes events every frame in the shipping
   game (enforced by code review, not runtime)

## Open Questions

- **Event history / replay**: Should the Event Bus keep a rolling buffer of
  recent events for debugging? Useful during development but adds memory
  overhead. Decide during implementation.
- **Save/Load contract**: The Save/Load system will use wildcard subscription to
  track state. The exact serialization interface (which events are
  "state-changing" vs. transient) needs to be defined when Save/Load is designed.
  For now, all events are available; filtering is the consumer's responsibility.
