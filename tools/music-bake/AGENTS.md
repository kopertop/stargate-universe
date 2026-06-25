# tools/music-bake — composable SGU music-stem baker

Generates the **isolated, seamlessly-looping** music stems the runtime mixer
(`scripts/music_director.gd`) layers into moods. Sister tool to `../tts-bake`
(same job-JSON → baker → `godot --import` shape).

## Why stems (not finished tracks)
ElevenLabs `text_to_sound_effects.convert(loop=True)` makes ONE seamless texture you can
stack — a stem. `music.compose()` makes a fully-mixed track you can't pull stems from, so
it's reserved for `kind: bed` standalone pieces. The composable library is all `loop`/`oneshot`.

## Files
| File | Role |
|---|---|
| `palette.py` | The SGU stem registry — one dict, `id → {layer, kind, duration_s, prompt, prompt_influence, mood_tags}`. Edit prompts HERE. |
| `jobs/sgu_sample.json` | Audition batch (1 per layer) — bake + vet before spending on the full set. |
| `jobs/sgu_full.json` | The full 18-stem library. |
| `bake.py` | Reads a job, calls the right API per `kind`, mp3 → `ffmpeg` → `sounds/music/loops/<id>.ogg`, writes `bake_report_<job>.json`. |
| `build_index.py` | `out/index.html` audition page, grouped by layer, with the free Kenney loops as a fidelity reference. |
| `run.sh` | `uv` env + bake + `godot --headless --import` + build index. |

## Usage
```bash
export ELEVENLABS_API_KEY=...
./run.sh                 # bake the audition batch -> open out/index.html
./run.sh sgu_full        # bake the full library once the palette is approved
SKIP_IMPORT=1 ./run.sh   # skip the godot import pass
```

## Gotchas
- **`.import` sidecars are mandatory** — without `godot --headless --import` the `.ogg`s
  load as null in-game (same trap as PNG/WAV). `run.sh` does this for you.
- **Looping is set at runtime**, not in the asset/import — MusicDirector sets
  `stream.loop = true` on load (robust across Godot OGG-import defaults).
- `kind`: `loop` (sustained stem), `oneshot` (sting), `bed` (full mixed piece, rare).
- Mood → stem composition is data in `../../data/music_moods.json`, NOT here.

See `../../CLAUDE.md`, `../../sounds/AGENTS.md`, and the `music`/`sound-effects` skills.
