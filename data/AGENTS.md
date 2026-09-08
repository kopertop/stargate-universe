# data/

Runtime JSON the game loads (`src/main.js`, `src/rpg.js`, `src/quest.js`). Edit these before touching generation code.

- `ship_layout.json` — deck rooms: `id`, `name`, `type`, `floor`, `startX/endX/startY/endY` (1 unit = 0.05 m; JSON X → world −Z,
  JSON Y → world X), optional `key_room`, optional `props` (component specs `{type,u,v,ry,anchor,loot}` from `src/components.js`).
- `room_connections.json` — `room_id → [{dir, to, plaque}]`, one direction; doors are cut on every shared edge.
- `chapters.json` — episodes: declarative steps (`id`, `label`, `objective`, `target{room,anchor}`, `complete_when` flag,
  `xp`, `on_enter`/`on_exit` triggers) plus a per-chapter planet (biome, atmosphere, resource).
- `items.json` — item catalog (id, name, category, slot, description). `src/rpg.js` adds web-only items.
- `planets.json`, `biomes.json`, `characters.json`, `music_moods.json`, `power_grid.json`, `quests.json`, `room_types.json`,
  `consumption.json`, `knockout_lines.json` — design-era content tables, not yet loaded by the web game; keep as authoring reference.

The in-game level editor (`` ` `` → `leveledit`) writes `ship_layout.json`, `room_connections.json` and `chapters.json` through
`tools/edit_server.py` (PUT, localhost only). The server preserves indentation and ASCII escaping so diffs stay clean.
