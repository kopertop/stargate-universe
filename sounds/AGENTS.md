# sounds/

Audio the game loads (see `SFX_FILES` and the music table in `src/main.js`; `build.sh` copies the same list into the itch zip).

- Gate: `stargate_chevron_incom.mp3`, `gate_kawoosh.wav`, `gate_active_hum.wav`, `ftl-dropout.ogg`.
- Doors / UI: `impact_metal_heavy_000.ogg`, `impact_metal_000.ogg`, `terminal_boot.ogg`, `menu_open.ogg`, `menu_close.ogg`, `radio_click.ogg`.
- Discovery stingers: `discovery_stinger.ogg` (rooms), `discovery_stinger_key.ogg` (key rooms).
- Footsteps: `footstep_01..10.ogg` (deck), `footstep_desert_00..03.ogg` (sand); dirt/water/swamp sets reserved for future biomes.
- `music/loops/*.ogg` — composable stems baked by `tools/music-bake`; `src/music.js` layers them into moods and crossfades.
  `music/sgu_main_theme.mp3` is the title bed.
- `dialog/` — baked voice lines from `tools/tts-bake` (not yet wired into the web game).

Everything else here is CC0 (Kenney) or generated in-repo. Add a file to `SFX_FILES` **and** `build.sh` when the game starts using it.
