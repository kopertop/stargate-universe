# scripts/

All GDScript. Grouped by system below — file names are kebab-case, `.gd`
extension. Most have an adjacent `.uid` sidecar (Godot 4.6 resource UID).

## Index by system

### Autoloads (in `project.godot`)
- `audio.gd` — Sound bank dispatcher.
- `game_state.gd` — Persistent game state: world-state flags, resources,
  save/load, `current_room_id` signal. Quest step + objective text is
  delegated to `quest_log.gd` (back-compat shims keep `quest_step` /
  `quest_target()` / `quest_step_label()` working).
- `quest_log.gd` — Data-driven quest runtime. Loads `data/quests.json`,
  re-derives the active step on every world-state mutation via a hybrid
  predicate/event advance rule. Owns labels, objectives, anchors. The
  CONDITIONS + OBJECTIVE_FNS registries are `match`-on-string in the
  same file; adding a predicate = one `match` arm + a JSON reference.
- `scene_router.gd` — Cross-scene transitions with named spawn markers.
- `ship_layout.gd` — Room data loader + BFS pathfinding over
  `data/room_connections.json` (`path_through_rooms`, `next_room_toward`).
- `kino_remote.gd` — Pip-Boy-style pause menu (Map / Status / Objectives /
  Inventory tabs). Now with player marker, quest-target diamond, and
  click-to-set custom route.
- `test_capture.gd` — Headless screenshot harness.
- `episode_wrap.gd` — Episode completion overlay.

### Dialogue / voice
- `tts_client.gd` — `TTSClient` node for runtime voiced dialogue. `say(voice,
  text, seed)` calls the resident LuxTTS sidecar over HTTP and emits
  `line_ready(AudioStreamWAV)`. Dynamic text, pre-computed character voices.
  Full guide: `docs/tts-dialogue.md`; server lives in `tools/tts-onnx-poc/`.

### Scene scripts
- `gate_room.gd` — Hand-authored gate hall layout + arrival cinematic.
- `room.gd` — Generic data-driven room scene. Stamps doors, dispatches to
  template builders, spawns the quest waypoint.
- `room_builder.gd` — Procedural floor/walls/ceiling + per-template accents.
- `view.gd` — Third-person camera rig (mouselook, follow modes).
- `hud.gd` — Player HUD: objective, health/oxygen, log, dialog panel,
  quest-waypoint screen-edge arrow.
- `playthrough_runner.gd` — Drives the end-to-end playthrough test.

### Interactables (per-prop scripts)
- `door.gd` — Room-to-room transition door + plaque.
- `npc.gd` — Generic NPC body, dialog choice-tree handler.
- `kino_pickup.gd`, `bed.gd`, `co2_scrubber.gd`, `power_console.gd`,
  `hull_seal_switch.gd`, `gate_console.gd`, `planet_gate.gd` — One per
  story interactable.

### Waypoint + UI helpers
- `quest_waypoint.gd` — Floating diamond Sprite3D (in-world).
- `dialog_screen.gd` — Full WoW-style dialog window (instanced by HUD).

### Data helpers (`class_name`, no autoload)
- `footstep_library.gd` (`FootstepLibrary`) — per-environment footstep registry
  (issue #33): surface id → sample paths + `surface_for_spec(planet_spec)`.
  `player.gd` resolves its surface from `GameState.active_planet_spec` on spawn.
  Biome→surface mapping lives in `../data/biomes.json` (`footstep_surface`).

## Conventions

- GDScript with static typing everywhere (`func foo(x: int) -> void:`).
- Tabs for indentation (Godot default).
- Files: `snake_case`. Nodes/classes: `PascalCase`.
- Prefer Godot signals over polling for cross-node communication.
- Headless tests skip autoload `_ready` — guard with idempotent `_load()`
  helpers and call them explicitly from tests (see `ship_layout.gd`). See
  memory `[[feedback_godot_scenetree_script_gotchas]]`.

## Cross-references

- Project rules: `../CLAUDE.md`
- Tests: `../tests/AGENTS.md`
- Prefabs the scripts back: `../objects/AGENTS.md`
