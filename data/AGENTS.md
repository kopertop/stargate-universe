# data/

Runtime JSON the game loads (`src/main.js`, `src/rpg.js`, `src/quest.js`). Edit these before touching generation code.

- `ship_layout.json` — deck rooms: `id`, `name`, `type`, `floor`, `startX/endX/startY/endY` (1 unit = 0.05 m; JSON X → world −Z,
  JSON Y → world X), optional `key_room`, optional `props` (component specs `{type,u,v,ry,anchor,loot,style}` from `src/components.js`;
  crates: `loot: [{id, n}]`, `style: 'ancient' | 'pelican'` — default ancient when the loot holds a fuse).
- `room_connections.json` — `room_id → [{dir, to, plaque}]`, one direction; doors are cut on every shared edge.
- `chapters.json` — episodes: declarative steps (`id`, `label`, `objective`, `target{room,anchor}`, `complete_when` flag,
  `xp`, `on_enter`/`on_exit` triggers) plus an optional per-chapter planet (biome, atmosphere, resource with optional `refined` item,
  `window_seconds` for the FTL jump window). Trigger types: `subtitle`, `radio`, `toast`, `ftl_drop`, `dial`,
  `countdown {seconds,label,cause}` (expiry knocks the player out with a `knockout_lines.json` cause and re-arms), `countdown_stop`.
  Step-id prefixes the autoplay understands without code: `talk_`, `find_`, `restore_` (seat parts + hotwire), `repair_` (flow panel),
  `balance_` (flow panel at the target console), `reach_` (walk to RoomCenter), plus `travel`, `mine`, `dial_home`, `give_brody`, `ride_up`.
- `items.json` — item catalog (id, name, category, slot, description). `src/rpg.js` adds web-only items.
- `planets.json`, `biomes.json`, `characters.json`, `music_moods.json`, `power_grid.json`, `quests.json`, `room_types.json`,
  `consumption.json` — design-era table, not yet loaded by the web game. `knockout_lines.json` — TJ's recovery lines per knockout cause (loaded by `main.js`).

The in-game level editor (`` ` `` → `leveledit`) writes `ship_layout.json`, `room_connections.json` and `chapters.json` through
`tools/edit_server.py` (PUT, localhost only). The server preserves indentation and ASCII escaping so diffs stay clean.
