# Stargate Universe — Destiny (browser game)

A third-person RPG aboard the Ancient ship *Destiny*, written in plain Three.js (0.180 via import map, ES modules, no
bundler). Two playable episodes (Air, Water), gate travel to procedural planets, Kino drone, RPG layer, in-game level
editor. This is the only game in the repo: the earlier Vite/ggez and Godot stacks were removed on 2026-09-08.

## Run / verify

- Dev: `python3 tools/edit_server.py 8090` → http://localhost:8090/ (or the `game` entry in `.claude/launch.json`).
  The server serves the repo root, accepts `PUT /data/*.json` from the level editor and pipes recorder frames into ffmpeg.
- Smoke: open `/?autoplay`, click New Game, run `window.__auto.run()`; `__auto.report` lists each chapter with `ok` and seconds.
- Video proof: `/?autoplay&record`, `__rec.start('name')` … `__rec.stop()` → `~/Desktop/name.mp4` at a constant 30 fps.
- Ship: `./build.sh` → `dist/sgu-destiny-html5.zip` for itch.io (HTML project, index.html at zip root).
- Pre-commit: `git config core.hooksPath .githooks` (node --check on staged `src/*.js`, JSON validation). CI does the same plus a build.

## Key paths

| Path | Role |
|---|---|
| `src/main.js` | wiring: worlds, audio, interactables, quest triggers, save/load, game loop (rAF; timer + sub-steps when hidden; fixed step while recording) |
| `src/ship.js` | deck generated from `data/ship_layout.json` + `room_connections.json`; SGU doors; lights (nearest 6 live); merged static walls |
| `src/components.js` | prop registry `{type,u,v,ry,anchor,loot}` with meshes + colliders (console, relay, crate, scrubber, …) — the editor places these |
| `src/quest.js` + `data/chapters.json` | declarative steps advance on flags; triggers on enter/exit |
| `src/rpg.js`, `src/ui.js` | inventory/equipment/talents; HUD + Kino Remote; icons from `assets/items/` |
| `src/hotwire.js` | wire-matching repair mini-game (power relay) |
| `src/player.js` | Quaternius UAL rig; gait clips locked to ground speed; footsteps from foot plants |
| `src/leveledit.js`, `src/console.js` | `` ` `` dev console; `leveledit` = first-person map builder in the live scene |
| `src/autoplay.js`, `src/recorder.js` | hands-free chapter driver (sim clock, per-frame waits); frame-pipe recorder |
| `tools/music-bake`, `tools/tts-bake` | ElevenLabs/TTS bake pipelines for `sounds/music/loops` and `sounds/dialog` |
| `design/gdd/` | engine-agnostic design docs — source of intent |
| `.ai/learnings/` | one lesson per file; read the relevant ones before extending a system |

## Conventions

- Tabs, `const`, arrow functions, async/await, 120 cols, kebab-case files. Data-driven: content in `data/*.json`, not code.
- Components: `ry` is the direction the prop FACES; its anchor (where the player stands) lies along `ry`.
- Coordinates: JSON units × 0.05 m; JSON X → world −Z, JSON Y → world X. Gate at the −Z end of the gate room.
- Never add lights casually: every visible PointLight recompiles into shader cost; `ship.js` keeps only the nearest 6 live.
- Any hidden-tab / timing work: read `.ai/learnings/hidden-tab-throttling-kills-raf-loops.md` and
  `record-fixed-step-frames-not-mediarecorder.md` first.
- Feature branches only (`feature/*`, `fix/*`, `chore/*`); commit + push before moving on; never force-push.
- One learning per file in `.ai/learnings/<lesson>.md` whenever something non-obvious is discovered.

## Directory cheatsheets

Each content directory has an `AGENTS.md` (data, sounds, sprites, design, docs, production, tools/music-bake). Read the local
one when entering a directory.
