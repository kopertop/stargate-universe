# Stargate Universe — Destiny

A browser RPG set aboard the Ancient seed ship *Destiny* (Stargate Universe). Third-person exploration of the deck,
gate travel to procedurally dressed planets, resource runs, a Kino drone, an RPG layer (inventory, gear, talents) and a
declarative chapter/quest engine. Two episodes ship: **Air** and **Water**.

Plain Three.js (0.180 via import map) + ES modules — no bundler, no framework.

## Run

```sh
python3 tools/edit_server.py 8090      # then open http://localhost:8090/
```

The dev server also accepts `PUT /data/*.json` from the in-game level editor and streams recorder frames into ffmpeg.
Or use the `game` entry in `.claude/launch.json`.

## Controls

WASD move · Shift run · Space jump · E interact (hold to dig) · mouse look (click to capture) · TAB Kino Remote
(quests, character, inventory, talents, ship map, gate, Kino, settings) · K launch Kino · V camera · F fullscreen.

Hidden dev console: **`** (backquote). Commands: `leveledit` (in-game first-person map builder), `noclip`, `power`,
`tp x z`, `flag`, `give`, `chapter`, `help`.

## URL flags

- `?autoplay` — hands-free chapter driver / smoke test: `window.__auto.run()`, results in `__auto.report`.
- `?record` — fixed-step recorder: `window.__rec.start('name')` / `stop()` → `~/Desktop/name.mp4` at a constant 30 fps.
- `?layout=live` — play the level editor's working copy from localStorage.

## Layout

| Path | Contents |
|---|---|
| `index.html`, `src/` | The game (`main.js` wires everything; `ship.js` builds the deck from data; `components.js` is the prop registry) |
| `data/` | `ship_layout.json` + `room_connections.json` (deck), `chapters.json` (episodes), `items.json`, planet/biome tables |
| `assets/items/` | 160 px inventory icons (sources in `sprites/ui/items`) |
| `models/quaternius/` | CC0 rig + animation libraries (UAL1/UAL2) and modular character parts |
| `sounds/` | SFX, composable music stems (`music/loops`), baked dialogue (`dialog/`) |
| `tools/` | dev server, music/TTS bake pipelines, gate SFX generator |
| `design/`, `docs/`, `production/` | GDDs, concept art, HUD reference, narrative scripts, sprint history |
| `.ai/learnings/` | one lesson per file — read before extending a system |

## Build for itch.io

```sh
./build.sh            # → dist/sgu-destiny-html5.zip (vendors three, bundles the assets the game loads)
```

## History

The project pivoted twice: a Vite/ggez browser stack, then Godot 4.6. Both were removed in September 2026; this
Three.js build is the only game. Design documents in `design/gdd/` predate it and remain the source of intent.
