# scripts/

All GDScript. Grouped by system below — file names are kebab-case, `.gd`
extension. Most have an adjacent `.uid` sidecar (Godot 4.6 resource UID).

## Index by system

### Autoloads (in `project.godot`)
- `audio.gd` — Sound bank dispatcher.
- `game_state.gd` — Persistent game state: quests, resources, save/load, the
  `QUEST_TARGETS` table for the diamond waypoint, `current_room_id` signal.
- `scene_router.gd` — Cross-scene transitions with named spawn markers.
- `ship_layout.gd` — Room data loader + BFS pathfinding over
  `data/room_connections.json` (`path_through_rooms`, `next_room_toward`).
- `kino_remote.gd` — Pip-Boy-style pause menu (Map / Status / Objectives /
  Inventory tabs). Now with player marker, quest-target diamond, and
  click-to-set custom route.
- `test_capture.gd` — Headless screenshot harness.
- `episode_wrap.gd` — Episode completion overlay.

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
