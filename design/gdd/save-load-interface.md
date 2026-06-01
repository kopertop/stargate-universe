# Save/Load Interface Contract

> **Status**: Implemented — profile/checkpoint model (issues #77/#79/#80/#81/#82)
> layered over the original Godot slot system (#44). The TS interface at the
> bottom is the engine-agnostic origin; the Godot mapping is in "Profile +
> checkpoint model" first, then the legacy "Slot model" it builds on.
> **Author**: User + Claude
> **Last Updated**: 2026-06-01

## Profile + checkpoint model (Godot, issues #77/#79/#80/#81/#82)

The shipped save system groups saves under named **profiles** (one per
playthrough). Each profile owns a **checkpoint timeline** — the player never
manages numbered slots; the system writes the right *kind* of checkpoint for
each trigger.

### On-disk layout

```
<saves_root>/
  active.json                              { "active_profile": "<id>" }  ← per-root pointer
  profiles/<profile_id>/
    profile.json                           id, display_name, created, last_played, active_checkpoint
    checkpoints/
      autosave_<unix_ts>/                  rolling ring — newest 3 kept
      quicksave/                           single rolling slot (F5)
      episode_<id>/                        permanent, one per episode boundary
      manual_<unix_ts>/                    permanent, unlimited
```

Each checkpoint dir reuses the **exact same on-disk shape as a flat slot**
(`save.json` primary + `save.bak.1..3.json` rotation + `meta.json` sidecar +
`save.json.tmp`), so the atomic-write / backup-chain / corrupt-fallback
primitives are shared across both layouts.

### Checkpoint kinds & permanence

| Kind | Id form | Trigger | Rolling? |
|---|---|---|---|
| `autosave` | `autosave_<ts>` | `GameState.objective_changed` / `current_room_changed` | **Yes** — ring of `SaveStore.AUTOSAVE_RING_KEEP = 3`, oldest evicted |
| `quicksave` | `quicksave` | F5 | **Yes** — single slot, overwritten |
| `manual` | `manual_<ts>` | in-game "Save" action | **No — permanent** |
| `episode` | `episode_<id>` | `GameState.episode_completed` (idempotent per episode) | **No — permanent** |

Permanence is **data, not code structure**: `meta.permanent` is derived from
`SaveStore.PERMANENT_KINDS = [manual, episode]` at write time. There are **no
per-kind boolean flags** scattered across scripts — profiles and checkpoints
are each ONE collection behind ONE add/enumerate API
(`create_profile`/`list_profiles`, `write_checkpoint`/`list_checkpoints`), and
the kind lives in the checkpoint's meta. `delete_checkpoint` refuses to remove
a permanent checkpoint; `prune_autosaves` only evicts `autosave`-kind dirs.

### Active-profile pointer & lazy Default

`active.json` (per saves-root) tracks which profile is active. A fresh install
has none; the first write (`_ensure_active_profile`) mints a **Default**
profile so autosaves always land in a real timeline without New Game ceremony.
New Game (`start_new_game(display_name)`) mints a *fresh* profile so its ring +
permanent checkpoints never mingle with a prior run's.

### Two-level Load browser (#80)

The title-screen Load Game UI is two levels: **profiles** (only those with at
least one checkpoint) → **checkpoints** of the selected profile. Permanent
(episode + manual) checkpoints are sectioned above rolling (autosave +
quicksave); all 3 autosaves list individually (the ring, not one slot).
Selecting a checkpoint calls `load_and_resume_checkpoint(profile, checkpoint)`;
**Continue** calls `load_and_resume("")` → most-recent checkpoint of the active
(or newest) profile.

### Migration (#82)

Two idempotent, run-once migrations execute in `SaveManager._ready`, both
**lossless and source-preserving** (the source is never deleted — a partial
migration can always fall back to the original layout):

1. `migrate_legacy()` — a pre-slots single `user://save.json` (+ backups) moves
   into the `autosave` flat slot.
2. `migrate_flat_to_profile()` — an existing FLAT slot layout folds into the
   **Default** profile: the `autosave` primary + backups become the autosave
   **ring** (newest first, capped at 3), `quicksave` → a quicksave checkpoint,
   `manual_N` → permanent manual checkpoints. Refuses to run if Default already
   exists (idempotent); reads (never wipes) the flat slots, so the original
   layout survives intact and the migrated profile is validated by a real
   `load_and_resume` before any cleanup would ever be considered.

### Permanence / ordering invariants (locked by tests)

- The autosave ring is **always capped at 3**, even under sustained pressure,
  and even alongside permanent checkpoints.
- A migrated permanent manual must **never outrank** the real most-recent
  autosave in `most_recent_checkpoint()` (manuals are stamped strictly older
  than the migrated ring), so Continue resumes the player's actual last state,
  not a permanent bookmark.
- Resume is **checkpoint-targeted**, not "most recent" — `load_and_resume_*`
  restores the requested checkpoint even when newer ones exist.

### Test coverage (issue #82 capstone)

| Suite | Proves |
|---|---|
| `tests/save/save_store_test.gd` | Pure `SaveStore` units: slot/checkpoint round-trip, ring eviction, permanence, delete-refusal, flat→profile migration + idempotency, the headless-isolation loss regression |
| `tests/save/profile_orchestration.tscn` | `SaveManager` orchestration over live autoloads: ring, manual, episode (idempotent), permanence under pressure, targeted + Continue resume |
| `tests/save/load_browser.tscn` | Two-level title browser populate/sections/ring/resume/back/delete against the real `title.gd` |
| `tests/save/ingame_ui.tscn` | In-game save + profile-management UI |
| `tests/save/integration.tscn` | **End-to-end across a simulated restart**: New Game → ring rolls → manual → episode → "quit" (re-resolve from disk) → two-level browse → targeted + Continue resume; plus **migration safety** (lossless, source-preserved, idempotent, validated-by-resume) |

Run all of them with `tests/run.sh save` (or `tests/run.sh save-integration`
for just the capstone suite).

---

## Slot model (Godot, issue #44 — legacy layer the profiles model builds on)

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
