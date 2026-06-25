# sounds/

Audio assets — `.ogg` for music + SFX. Most are Kenney starter-kit
carry-overs; project-specific audio gets added under the same convention.

## Contents

- `break.ogg` — Reused as gate-shutdown SFX in `gate_room.tscn`.
- `coin.ogg`, `fall.ogg`, `jump.ogg`, `land.ogg` — Kenney starter-kit SFX.
  (`walking.ogg` is the old looping footstep bed — superseded by the
  `footstep_NN.ogg` set below, kept only as the scene's default stream.)
- **Footsteps — per-environment sets (issue #33).** `player.gd` plays a random
  sample every ~1.9 m of floor travel (distance-based cadence, auto-scales with
  speed) with per-step pitch jitter. The SET is chosen on spawn by
  `scripts/footstep_library.gd` (`FootstepLibrary`) from the active planet's
  biome — the ship / a bare spec = `metal`. Biome→surface mapping is the
  `footstep_surface` key in `../data/biomes.json` (fallback table in the lib).
  Sets:
  - `footstep_01.ogg` … `footstep_10.ogg` — **metal** (ship + alien-tech decks).
    Slices of the "ES Ship Footsteps" pack (silence-split, ~0.25–0.4s each).
  - `footstep_dirt_00.ogg` … `footstep_dirt_09.ogg` — **dirt** (temperate /
    jungle / urban ground). Kenney "RPG Audio" `footstepNN.ogg` (CC0).
  - `footstep_desert_00.ogg` … `_03.ogg` — **desert** sand crunch. Generated
    (CC0, filtered pink-noise transient; ElevenLabs API was unavailable).
  - `footstep_water_00.ogg` … `_03.ogg` — **water** shallow wade splash.
    Generated (CC0). Reserved for a future water biome.
  - `footstep_swamp_00.ogg` … `_03.ogg` — **swamp** mud squelch (toxic biome).
    Generated (CC0).
  > Generated samples are placeholders pending an ElevenLabs/foley pass — the
  > system is data-driven, so a higher-fidelity drop-in is a pure asset swap.
- `klaxon.ogg` — Heavy bell strike (Kenney Impact Sounds /
  impactBell_heavy_001). Played 3× by `bed.gd` on the post-sleep wake-up.
- `flicker.ogg` — Electrical glitch (Kenney Interface Sounds / glitch_002).
  Played at random 6–14s intervals by `ambient_audio.gd` while the air
  crisis is active; also fires once mid-klaxon during wake-up.
- `menu_open.ogg` — Confirmation bong (Kenney Interface Sounds / bong_001).
  Plays when Kino Remote / control terminal panel opens.
- `menu_close.ogg` — Soft close chirp (Kenney Interface Sounds / close_001).
- `menu_click.ogg` — UI tab click (Kenney Interface Sounds / click_001).
- `terminal_boot.ogg` — Computer power-on tone (Kenney Sci-Fi Sounds /
  computerNoise_001). Plays diegetically when E-ing a control console.
- `discovery_stinger.ogg` — Epic deep-string swell "Daaahhhh" played on the
  room-discovery toast for a NORMAL room (`hud.gd` DISCOVERY_STING_SOUND).
  ElevenLabs-generated (prompt: a short deep string chord), ~4s, Ogg Vorbis.
- `discovery_stinger_key.ogg` — **KEY-ROOM** discovery cue: a brighter
  "magical discovery" swell (~5.9s, ElevenLabs, Ogg Vorbis), `hud.gd`
  DISCOVERY_STING_KEY_SOUND. Played INSTEAD of the normal stinger when the
  discovered room is a "key room" (Control Interface Room, Kino Room, …).
  ⚠️ Which rooms are "key" is **owned by a separate work stream** and is read
  ONLY via `ShipLayout.is_key_room(room_id)` — see the big coordination note in
  `../scripts/ship_layout.gd` and `../data/AGENTS.md`. Do not add a second
  list of key rooms here or in hud.gd.
- `radio_click.ogg` — CB-radio static squelch (CbRadioStatic_S08TE.400,
  converted from MP3). Plays when a radio connection OPENS — Scott's
  wake-up order (bed.gd), the Rush-absent exchange (room.gd), and the
  blocked-door beat (kino_remote.gd::begin_breach_beat).
- `radio_off.ogg` — Walkie-talkie sign-off beep (WalkieTalkie_S08TE.1343,
  converted from MP3). Plays when a radio transmission CLOSES, bookending
  the static-open. Same three radio moments.

## Composable background music — `music/loops/`

- **`music/loops/<stem>.ogg`** — the composable SGU music STEM library: isolated,
  seamlessly-looping textures (drones, string pads, solo cello/violin/piano, pulses)
  plus short one-shot stings. Baked by `../tools/music-bake` (ElevenLabs SFX-loop API);
  stem prompts live in `../tools/music-bake/palette.py`.
- `scripts/music_director.gd` (autoload **MusicDirector**) layers these into MOODS
  (`../data/music_moods.json`) and crossfades on `GameState` / `FtlLoop` signals
  (room, quest step, air-crisis scrubber level, FTL phase, dialog ducking). All stems
  route through the **Music** bus.
- `music/sgu_main_theme.mp3`, `music/sgu_soundtrack.mp3` — pre-existing full menu/theme
  beds (not part of the composable stem set).
- `../scripts/ambient_hum.gd` (procedural 55 Hz drone) survives as a quiet sub-bass
  sub-layer under the MusicDirector bed in the gate room.

## Conventions

- Format: `.ogg` Vorbis (Godot's preferred web-friendly format).
- **Music stems loop at RUNTIME**, not via the `.import` flag: MusicDirector sets
  `stream.loop = true` on load (robust across Godot OGG-import defaults). Melodic stems
  stay non-looping — the director replays them with randomized rests.
- Each `.ogg` gets a `.import` sidecar generated by the Godot editor — keep
  both committed.
- Loop points + volume normalisation live in the `.import` file. Don't bake
  loops into the audio file itself.
- For new SFX, prefer the `/sound-fetch` skill (CC0 search + R2 upload +
  trigger wiring) over hand-fetching.

## Cross-references

- Project rules: `../CLAUDE.md`
- Audio dispatcher: `../scripts/audio.gd` (autoload `Audio`)
- Audio inventory + attribution: `../docs/audio-inventory.md`
- Music generation skill: `/music`
- SFX generation skill: `/sound-effects`
