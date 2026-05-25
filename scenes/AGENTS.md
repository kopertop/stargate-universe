# scenes/

Top-level `.tscn` gameplay scenes. Each one is a self-contained level/screen;
prefabs they instance live in `../objects/`.

## Contents

- `main.tscn` — Root scene chosen as the project's "Main Scene". Boots into
  `title.tscn` unless a debug entry point overrides.
- `title.tscn` — Title screen + settings overlay. New game / continue / exit.
- `gate_room.tscn` — Hand-authored hero scene (Destiny's gate hall). Backed
  by `../scripts/gate_room.gd`. Includes the procedural ExitDoor + Lt Scott.
- `room.tscn` — Generic data-driven room. Backed by `../scripts/room.gd`;
  reads `next_room_id` from GameState and dispatches to `room_builder.gd` +
  per-room interactable spawners.
- `planet.tscn` — Off-ship planet scene (lime planet).
- `*.tres` — Environment + lighting resources used by the scenes.

## Conventions

- Every scene with a player must declare `script = ExtResource(...)` for an
  owning script and include a `Player` (`group=player`) + `View` rig.
- Adding a new scene = update `tests/smoke/scene_boot.gd` to assert its
  critical nodes load.
- The gate room is the only artisan room; all other rooms reuse `room.tscn`
  + their `data/ship_layout.json` row.

## Cross-references

- Project rules: `../CLAUDE.md`
- Scene transitions: `../scripts/scene_router.gd` (autoload `SceneRouter`).
  Note: `change_scene_to_file` is deferred — see memory
  `[[feedback_godot_change_scene_async]]`.
- Procedural room geometry: `../scripts/room_builder.gd`
- Smoke test: `../tests/smoke/scene_boot.gd`
