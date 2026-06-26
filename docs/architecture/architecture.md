# Stargate Universe — Master Architecture

## Document Status
- Version: 1.0
- Last Updated: 2026-06-26
- Engine: Godot 4.6 (Forward+ renderer), GDScript, typed everywhere
- GDDs Covered: all 16 in `design/gdd/`
- ADRs Referenced: ADR-001 (engine), ADR-002 (physics), ADR-003 (renderer), ADR-004 (VRM models)
- Companion index: `docs/architecture/codebase-dependency-graph.md`

> This is the whole-system blueprint. It was reverse-documented from the shipping
> Godot codebase (the project is in Production, not pre-production), so it
> describes the architecture **as built**, then names the gaps. ADRs record point
> decisions; this document gives them context.

## Architecture Principles

1. **Autoload singletons are the backbone.** Cross-scene state and services live in
   ~26 autoloads registered in `project.godot`. Scenes are thin; the singletons own
   the durable state. Every stateful autoload either calls
   `SaveManager.register_system(...)` or declares `# @no-save: <reason>` (enforced by
   `tests/lint/check_save_registration.sh`).
2. **Data-driven content over hand-authored scenes.** Rooms, ship topology, quests,
   characters, set-dressing, and music moods are JSON/Resource data
   (`data/*.json`) interpreted by generic scripts (`room.gd`, `procedural_ship.gd`,
   `quest_log.gd`). `gate_room.tscn` is the deliberate artisan exception.
3. **Signals over polling.** Systems communicate through `GameState` signals
   (`objective_changed`, `dialog_action`, `current_room_changed`, …), not per-frame
   queries. `GameState` doubles as the project's event bus (see `design/gdd/event-bus.md`).
4. **One collection per set of like things.** Items, discovered rooms, sealed
   breaches, unlocks live behind ONE registry + add/enumerate API, never scattered
   per-instance bools (enforced by `tests/lint/check_collection_forks.sh`).
5. **Headless-verifiable by construction.** Every system must be exercisable from a
   `SceneTree` smoke test under `instant_mode` (no frame pumping). Cinematics
   early-return on `SceneRouter.instant_mode`; `class_name` is avoided in favour of
   `preload` consts because registration lags in `-s` runs.

## System Layer Map

```
┌───────────────────────────────────────────────────────────────────────┐
│ PRESENTATION   Audio · HUD · DialogScreen · KinoRemote · Cinematic ·    │
│                PauseMenu · CharacterPanel · CrewViewer · EpisodeWrap ·   │
│                GamepadConfigDialog · MusicDirector                      │
├───────────────────────────────────────────────────────────────────────┤
│ FEATURE        QuestLog · Inventory · ConsumptionManager · FtlLoop ·    │
│                RepairRobot · room.gd / gate_room.gd content · NPCs ·    │
│                KinoDrone · planet/biome generation                      │
├───────────────────────────────────────────────────────────────────────┤
│ CORE           player.gd (CharacterBody3D) · door.gd · Interactable ·   │
│                GameClock · RoomBuilder · ProceduralShip                  │
├───────────────────────────────────────────────────────────────────────┤
│ FOUNDATION     GameState (state + event bus) · SaveManager · NPCState · │
│                SceneRouter · ShipLayout · Settings · Gamepad            │
├───────────────────────────────────────────────────────────────────────┤
│ PLATFORM       Godot 4.6 Forward+ · built-in 3D physics · OS/input ·    │
│                addons/vrm                                                │
└───────────────────────────────────────────────────────────────────────┘
DEV/TOOLING (not shipped, # @no-save): TestCapture · TrailerCapture · KinoMapCapture
```

## Module Ownership

### Foundation Layer

| Module | Owns | Exposes | Consumes |
|---|---|---|---|
| `GameState` | E1 story/progression state, objectives, health/oxygen, logs, dialog events; serialization of its own state | mutators (`damage`, `discover_room`, …), signals (`objective_changed`, `dialog_action`, `dialog_started/closed/release`, `current_room_changed`, `episode_completed`) | `SaveManager` (registers), `ShipLayout` |
| `SaveManager` | Save/load pipeline, slot/profile orchestration, registered-system capture | `register_system(id, node)`, save/load/slot APIs | every registered autoload's `serialize`/`deserialize` |
| `NPCState` | Persisted NPC position/dialogue **keyed by node name** | per-node save/restore | `SaveManager` |
| `SceneRouter` | Fade transitions, scene switching, spawn placement, post-transition orientation; `instant_mode` flag | `change_to(scene, spawn)`, `instant_mode` | `GameState`, `ShipLayout` |
| `ShipLayout` | `data/ship_layout.json` topology, scaled room dims (read-only) | room lookup, `SCALE` | — (`# @no-save`: static) |
| `Settings` / `Gamepad` | user preferences (`user://settings.cfg`), controller mapping | volume/difficulty/binding getters | persisted independently |

### Core Layer

| Module | Owns | Exposes | Consumes |
|---|---|---|---|
| `player.gd` | player CharacterBody3D, movement, interact ray (chest-height 1.1 m), input lock, cinematic dash/auto-walk | `cinematic_dash_to`, `auto_walk_to`, `set_input_locked` | `View` (camera yaw), `Audio` |
| `door.gd` | door visuals + routing behaviour, walk-blocker/curtain colliders | interact → `SceneRouter.change_to` | `GameState`, `SceneRouter`, `ShipLayout` |
| `Interactable` | interact collision layer (4), prompt, `interacted` signal | `interact()`, `_on_interact()` | player ray |
| `ProceduralShip` / `RoomBuilder` | infinite-bounded floor/room generation over `ShipLayout` | floor/room build APIs | `ShipLayout`, `data/room_types.json` |
| `GameClock` | tick/time base | tick signal | — |

### Feature Layer

| Module | Owns | Exposes | Consumes |
|---|---|---|---|
| `QuestLog` | data-driven quest tracker (predicate + event advance), quest save round-trip | quest state, `quest_target` | `GameState` signals |
| `Inventory` | item registry (kino remote, orbs, fuses, rations) — ONE collection | `add`/`has`/enumerate | `GameState` |
| `ConsumptionManager` | resource consumption tick (air/power) | consumption state | `GameState`, `GameClock` |
| `FtlLoop` | FTL jump loop + air-crisis timer pressure (gate-window recall) | `_armed`, jump API | `GameState`, `SceneRouter` |
| `RepairRobot` | autonomous repair sim (durable state lives in `GameState`) | dispatch API | `GameState` (`# @no-save`) |
| `room.gd` content | per-room interactables, NPC spawns, hull-breach geometry; standoff delegated to `RushStandoffDirector` | data-driven spawners | `ShipLayout`, `RoomBuilder`, `CharacterFactory`, `data/room_connections.json` |
| `KinoDrone` | recon drone flythrough/auto-explore (deliberately NOT in group "player") | pilot/recall | `GameState`, `ShipLayout` |

### Presentation Layer

| Module | Owns | Exposes | Consumes |
|---|---|---|---|
| `Audio` | pooled one-shot SFX bus | `play(path)`, `play_ui_hover`, `attach_ui_hover` | `sounds/*.ogg` (`# @no-save`) |
| `HUD` / `DialogScreen` | persistent unit-frame + action-bar HUD (WoW model), Fable-style dialog cinema | renders on `GameState.dialogue_shown`/`dialog_*` | `GameState`, `data/characters.json` |
| `KinoRemote` | pause overlay: map/status/objectives/inventory pages | toggle overlay | `GameState`, `ShipLayout` (`# @no-save`: transient) |
| `MusicDirector` | layered background music, mood crossfades | mood API | `data/music_moods.json`, `sounds/` stems (`# @no-save`) |
| `Cinematic`, `PauseMenu`, `CharacterPanel`, `CrewViewer`, `EpisodeWrap`, `GamepadConfigDialog` | their respective overlays | open/close | `GameState` (`# @no-save`: UI overlays) |

### Dependency direction

```
PRESENTATION ──reads/listens──▶ GameState ◀──mutates── FEATURE
     │                            ▲                       │
     └──────────▶ SceneRouter ────┘                       ▼
CORE (player/door/Interactable) ──▶ GameState        FOUNDATION (SaveManager
                                                      captures all registered)
```
All layers depend **downward** onto Foundation (chiefly `GameState`); Foundation
depends on nothing above Platform. No upward dependencies.

## Data Flow

**Frame update:** `Input` → `player.gd` (`_physics_process`, camera-relative move) →
CharacterBody3D physics → `View` follows → HUD reads `GameState` each frame for the
compass/unit-frame.

**Event/signal:** A gameplay action (interact, objective met) calls a `GameState`
mutator → `GameState` emits a signal → HUD/QuestLog/KinoRemote/NPCs react. No system
polls another. Tree-pausing dialogs use `PROCESS_MODE_ALWAYS` actors + per-node
`"action"` cues on `dialog_action` (see `RushStandoffDirector`).

**Save/load:** autosave fires on `GameState` signals → `SaveManager` walks every
`register_system`'d node, calls `serialize()` → writes `user://save.json`. Load
reverses it. NPC transforms persist via `NPCState`, keyed by **unique node name**
(same character in two scenes needs distinct names). Non-player sessions
(screenshot/test tools) must isolate the save root or they clobber the real save.

**Initialisation order:** autoload order in `project.godot` is load order; later
autoloads see `_unhandled_input` first (reverse registration). `ShipLayout` loads
topology before any room builds; `SceneRouter.change_scene_to_file` is deferred
(`current_scene` briefly null — loop-wait in headless).

## API Boundaries

- **`GameState` mutators** are the only sanctioned way to change story state. UI never
  writes story state directly; it calls a mutator and re-renders on the resulting signal.
- **`SaveManager.register_system(id, self)`** is the contract for persistence. A new
  stateful autoload MUST register or carry `# @no-save:`. Invariant: `serialize()`
  returns a `Dictionary` of plain values; `deserialize(d)` tolerates missing keys
  (forward/backward save compat).
- **`SceneRouter.change_to(scene, spawn)`** owns all scene transitions and spawn
  placement. Callers must not set `current_scene` directly. During a transition
  `is_transitioning` is true — do NOT emit a tree-pausing dialog (black-screen deadlock).
- **`Interactable._on_interact()`** is the extension point for interactive props;
  set extra collision layers AFTER `super()` (it hard-sets layer 4). `interacted`
  fires BEFORE `_on_interact`.
- **Collections** (`Inventory`, discovered rooms, sealed breaches): add/enumerate via
  the one registry API; never add a sibling `has_X` bool.

## ADR Audit

| ADR | Engine Compat | Version | GDD Linkage | Conflicts | Valid |
|---|---|---|---|---|---|
| ADR-001 Engine choice (Godot 4.6) | ✅ | ✅ | game-concept | none | ✅ |
| ADR-002 Physics engine (Godot built-in) | ✅ | ✅ | player-controller, ship-exploration | supersedes Crashcat note | ✅ |
| ADR-003 Renderer (Forward+) | ✅ | ✅ | ship-atmosphere-lighting | none | ✅ |
| ADR-004 VRM models | ✅ | ✅ | vrm-model-integration | secondary to Quaternius modular (primary) | ⚠️ update |

ADR-004 predates the decision that **Quaternius modular characters are PRIMARY** and
VRM/VRoid secondary — it should be amended to record that.

## Required ADRs (gaps)

**Should have (systems already built without an ADR):**
- Autoload/event-bus architecture — why `GameState` is both state store and event bus.
- Save/load serialization format & `register_system` contract.
- Scene routing & spawn-placement strategy (`SceneRouter`, `instant_mode`).
- Procedural ship generation (`ProceduralShip`/`ShipLayout` topology + bounds).
- Character pipeline decision: Quaternius modular primary, VRM secondary (amend ADR-004).

**Can defer:**
- Music layering (`MusicDirector`) format.
- Quest-system data-driven numeric-step refactor (deferred post-E1 by decision).

## Open Questions

| ID | Summary | Priority | Resolution Path |
|---|---|---|---|
| QQ-01 | Player-side free travel through an open Stargate (Kino path honours two-way; player deferred) | Medium | gameplay ADR + `stargate-planetary-runs.md` |
| QQ-02 | `gate_room.gd` (4,603 lines) cinematic extraction (TD-001) | Low | `docs/tech-debt-register.md` |
| QQ-03 | Dependency graph is stale (lists 8 autoloads; 26 exist) | Low | regenerate `codebase-dependency-graph.md` |
| QQ-04 | Missing `control-manifest.md`, `design/accessibility-requirements.md` | Low | `/create-control-manifest`, `/ux-design` |
