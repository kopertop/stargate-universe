# objects/

Reusable `.tscn` prefabs + their backing scripts. Anything that's instanced
multiple times across scenes lives here.

## Contents

### Player + camera
- `player.tscn` — Player CharacterBody3D, view rig, interactable raycast.
- `dialog_screen.tscn` — Choice-tree WoW-style dialog window (instanced by
  `scripts/hud.gd` on `dialog_started`).
- `hud.tscn` / `hud.gd` is **here**; the scene is then referenced by gameplay
  scenes (gate_room.tscn, room.tscn) via an HUDLayer wrapper.

### World prefabs
- `door.tscn` — Interactable door used between rooms. Exports
  `target_room_id`, `target_spawn`, `plaque_label`, etc.
- `stargate.tscn` — The Stargate prop (rings + portal).

### Kenney starter-kit holdovers (low priority — most unused on this branch)
- `brick.tscn`, `cloud.tscn`, `coin.tscn`, `character.tscn` etc.

## Conventions

- Prefabs use composition: small `.tscn` files combined via `instance` (per
  CLAUDE.md "Dev Conventions").
- Scripts that back a prefab are sibling files (`door.gd` ↔ `door.tscn`).
  Don't relocate one without the other.
- Doors auto-derive their plaque label from the destination room's name when
  `plaque_label` is empty. The label appears via `Label3D` per memory
  `[[godot-label3d-on-procedural-mesh]]`.

## Cross-references

- Project rules: `../CLAUDE.md`
- Door routing: `door.gd` + `../scripts/room.gd::_stamp_door`
- Quest waypoint diamond is NOT here — see `../scripts/quest_waypoint.gd`
  (spawned dynamically, not a .tscn prefab).
