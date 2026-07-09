# data/

JSON content tables loaded by autoloads. The canonical source of truth for
ship layout and room graph — modify these before touching room generation
code.

## Contents

- `ship_layout.json` — Array of room records. Loaded by `scripts/ship_layout.gd`
  (autoload `ShipLayout`). Each row: `id`, `name`, `floor` (0 or 1), `width`,
  `height`, `startX`, `endX`, `startY`, `endY`, `template_id`, `type`, plus
  state booleans (`found`, `locked`, `explored`, `discovered`).

  > ### ⚠️ KEY ROOMS — coordination note (read if you own key-room definitions)
  > A "key room" (Control Interface Room, Kino Room, …) plays a special
  > **magical** discovery cue (`sounds/discovery_stinger_key.ogg`) instead of
  > the normal one. The room-discovery audio reads this through ONE function:
  > **`ShipLayout.is_key_room(room_id)`** (`scripts/ship_layout.gd`).
  >
  > **The intended canonical definition is a per-room flag here:**
  > `{ "id": "...", ..., "key_room": true }`. `is_key_room()` already reads it,
  > so adding the flag is all that's needed — no audio/code change.
  >
  > Until those flags exist, `is_key_room()` falls back to a TEMPORARY hardcoded
  > list (`_KEY_ROOMS_FALLBACK` in `ship_layout.gd`: `control_interface_room`,
  > `eli_quarters`). When you land the `key_room` flags, **delete that fallback
  > list** so this JSON is the single source of truth (no duplicate key-room
  > lists — project anti-pattern). If your definitions live elsewhere instead,
  > point `is_key_room()` at them and keep it the only key-room query.

- `room_modules.json` — Build-mode module catalog (hydroponics unit, quarters,
  research lab, machine shop, ...). Loaded by `scripts/ship_state.gd`
  (autoload `ShipState`); consumed by the room consoles' BuildPanel. See
  `../design/gdd/ship-building-mode.md`.
- `room_connections.json` — Dictionary of `room_id -> Array[{dir, to, plaque}]`.
  Connections are listed in ONE direction; consumers mirror reverse edges (see
  `scripts/room.gd::_setup_doors` and `scripts/ship_layout.gd::_load_connections`).
- `characters.json` — Per-character static metadata used by NPC scripts.
- `planets.json` — Off-ship planet definitions (lime planet etc.). Legacy rows
  are normalized into a desert `PlanetSpec` by `scripts/planet_generator.gd`.
- `biomes.json` — Per-biome parameter blocks (terrain shaping, ground/sky
  palette, prop set, walkability, hazard) keyed by biome id (`desert`,
  `temperate`, `jungle`, `toxic`, `urban`, `alien_tech`). Read by
  `PlanetGenerator.biome_params()`; consumed via a `PlanetSpec`
  `{ seed, biome, resource_table, hazard_params }`. Authorable without code edits
  — keep terrain `height`/`frequency` low so generated slopes stay walkable (no
  jump required). The `hazard` block carries the gate window + water drain plus
  biome-specific sub-blocks: `traps` (jungle damage zones), `sensors` (alien-tech
  alarms), `oxygen_drain`/`breathable`/`suit_drain_multiplier` (toxic), and
  `settlement`/`negotiation` (urban). A biome whose `hazard.requires_flag` is set
  (toxic → `pressure_suits_found`) is EXCLUDED from the dial-time selection pool
  until that GameState flag is true. The dial flow that ties it together is
  `GameState.build_next_planet_spec()` (biome roll + scarcity-targeted resource
  table + hazard block, persisted + reproducible per `planets_dialed`); the Kino
  scan summary is `GameState.planet_scan_profile()`. See
  `../design/gdd/stargate-planetary-runs.md` → Procedural Generation.

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
