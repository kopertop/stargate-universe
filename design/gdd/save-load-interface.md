# Save/Load Interface Contract

> **Status**: Implemented (Godot slot system, issue #44) — TS interface below
> is the engine-agnostic origin; the Godot mapping is in "Slot model" first.
> **Author**: User + Claude
> **Last Updated**: 2026-05-30

## Slot model (Godot, issue #44)

The shipped Godot implementation uses **save slots**: one directory per slot
under a `saves_root`, each holding the snapshot, its rotating backups, and a
lightweight metadata sidecar.

- **Slots:** `autosave` + `quicksave` + N manual slots (`manual_1..manual_N`,
  `SaveStore.MANUAL_SLOT_COUNT = 3`). Autosave triggers write `autosave`; F5
  writes `quicksave`; the pause-menu picker writes a `manual_N`.
- **Layout per slot:** `save.json` (primary), `save.bak.1..3.json` (3-deep
  rotation, 1 = newest), `meta.json` (sidecar), `save.json.tmp` (transient).
- **Metadata sidecar (`meta.json`):** written alongside every payload, read on
  its own so the load menu never deserializes a full save. Contract:
  `{ version, timestamp, playtime_seconds, scene_path, room_id, objective,
  slot_id }` — `playtime_seconds` ← `GameClock.elapsed_seconds`, `room_id` /
  `objective` ← `GameState`.
- **Saves root selection (loss fix):** `SaveManager._ready` picks the root —
  real (windowed) play → `user://saves/`; **headless** runs, an explicit
  `--save-root=<path>` user arg, or the `SGU_SAVE_ROOT` env var → a sandbox
  root. Isolation is the DEFAULT for non-player sessions, so screenshot/test/
  tool runs can never overwrite the player's slots.
- **Persistence split:** all pure file/path/slot/meta I/O lives in `SaveStore`
  (`RefCounted`, no autoload deps) so the headless CLI tools
  (`tests/tools/save_inspect.gd`, `save_edit.gd`) reuse the exact same code
  without the `SaveManager` autoload. `SaveManager` keeps orchestration.
- **Migration:** a pre-slots single `user://save.json` (+ backups) is moved
  into the `autosave` slot on first launch via `SaveStore.migrate_legacy()`
  (idempotent), deriving its meta from the snapshot.
- **Debug CLI:** `tests/tools/save.sh list|dump|validate|set|clone|scenario`
  inspects and mutates slots so a tester can stage any scene/room/quest step
  and hit Continue to land there. See `tests/README.md`.

---

> **Below: original engine-agnostic interface (TS-era).**

## Purpose

This document defines the `ISaveableSystem` interface that all MVP systems
implement for serialization. The full Save/Load system (file management, slots,
migration) is a Vertical Slice feature, but the interface contract must exist
now so MVP systems can be built with serialization in mind.

## Interface Definition

```typescript
interface ISaveableSystem {
   /** Unique ID for this system's save data block */
   readonly saveId: string;

   /** Return a JSON-serializable snapshot of all persistent state */
   serialize(): Record<string, unknown>;

   /** Restore state from a previously serialized snapshot */
   deserialize(data: Record<string, unknown>, version: number): void;
}
```

## Contract Rules

1. `serialize()` must return a plain JSON-serializable object (no classes,
   functions, circular references, or `undefined` values).
2. `deserialize()` must handle missing fields gracefully (use defaults for
   any field not present in `data` — enables forward compatibility).
3. The `version` parameter enables migration: if the save was created with an
   older schema, the system must fill in defaults for new fields.
4. Each system's `saveId` must be unique (e.g., `"ship-state"`, `"resources"`,
   `"timers"`, `"crew-dialogue"`).
5. `serialize()` must be fast — called on every save. Target < 1ms per system.
6. `deserialize()` must restore state exactly — a round-trip of
   `deserialize(serialize())` must produce identical game state.

## Systems Implementing This Interface

| System | saveId | Key Data |
|--------|--------|----------|
| Ship State | `"ship-state"` | All three tiers: systems, sections, subsystems with conditions |
| Resource & Inventory | `"resources"` | Resource quantities + story item flags |
| Timer & Pressure | `"timers"` | Active timers with remaining time, state, fired flags |
| Crew Dialogue & Choice | `"crew-dialogue"` | Affinities, romance values, choice history, narrative flags |
| Stargate & Planetary Runs | `"stargate"` | Gate state, on-planet progress, planet health |
| Ship Exploration | `"exploration"` | Discovery state, knowledge tier, barrier status |
| Kino Remote | `"kino-remote"` | Unlocked screens, console connections |
