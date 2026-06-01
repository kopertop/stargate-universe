# data/

JSON content tables loaded by autoloads. The canonical source of truth for
ship layout and room graph — modify these before touching room generation
code.

## Contents

- `ship_layout.json` — Array of room records. Loaded by `scripts/ship_layout.gd`
  (autoload `ShipLayout`). Each row: `id`, `name`, `floor` (0 or 1), `width`,
  `height`, `startX`, `endX`, `startY`, `endY`, `template_id`, `type`, plus
  state booleans (`found`, `locked`, `explored`, `discovered`).
- `room_connections.json` — Dictionary of `room_id -> Array[{dir, to, plaque}]`.
  Connections are listed in ONE direction; consumers mirror reverse edges (see
  `scripts/room.gd::_setup_doors` and `scripts/ship_layout.gd::_load_connections`).
- `characters.json` — Per-character static metadata used by NPC scripts.
- `planets.json` — Off-ship planet definitions (lime planet etc.). Legacy rows
  are normalized into a desert `PlanetSpec` by `scripts/planet_generator.gd`.
- `biomes.json` — Per-biome parameter blocks (terrain shaping, ground palette,
  prop set, walkability, hazard) keyed by biome id (`desert`, `jungle`, `toxic`,
  `urban`, `alien_tech`). Read by `PlanetGenerator.biome_params()`; consumed via
  a `PlanetSpec` `{ seed, biome, resource_table, hazard_params }`. Authorable
  without code edits — keep terrain `height`/`frequency` low so generated slopes
  stay walkable (no jump required).

## Conventions

- **Coordinate system**: JSON X/Y grid units. `1 JSON unit = 0.05 m`
  (`ShipLayout.SCALE`). JSON Y maps to Godot world Z (the ship's floor plan).
- **Floor 0** = main deck (gate room level). **Floor 1** = upper deck
  (hydroponics, crew quarters).
- **Direction enum** (`dir` in connections): `+x`, `-x`, `+z`, `-z`, `elevator`.
  Elevator entries are physically detached pairs across floors.
- New rooms must add an entry to BOTH `ship_layout.json` (geometry) AND
  `room_connections.json` (graph) or the scene smoke test will fail.

## Cross-references

- Project rules: `../CLAUDE.md`
- GDD: `../design/gdd/ship-exploration.md`
- Loader: `../scripts/ship_layout.gd` (autoload `ShipLayout`)
- BFS over the graph: `ShipLayout.path_through_rooms`, `next_room_toward`
- Reachability smoke check: `../tests/smoke/scene_boot.gd`
