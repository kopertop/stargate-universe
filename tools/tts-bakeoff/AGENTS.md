# tools/tts-bakeoff — local TTS emotion comparison harness

Throwaway harness to pick a local TTS engine that keeps a character's voice
**consistent** while letting **emotion vary per line** (e.g. Scott yelling/panicked
vs. calm). Generates the same Scott lines across candidate engines so the audio
drives the decision. See `../../CLAUDE.md` and the LuxTTS pipeline in `../tts-onnx-poc/`.

## Run

```bash
# ZipVoice baseline needs the sidecar up first:
../tts-onnx-poc/run_server.sh &

./run_bakeoff.sh                     # all engines
./run_bakeoff.sh zipvoice chatterbox # a subset
open out/index.html                  # listen + compare
```

## Layout

| File | Role |
|---|---|
| `lines.json` | Single source of truth: reference clip + transcript, 3 panic + 2 calm Scott lines, neutral tags |
| `tags.py` | Neutral-tag → per-engine emotion adapter (the only place dialects differ) |
| `common.py` | Stdlib helpers shared by every generator (paths, timing, meta.json) |
| `gen_*.py` | One per engine; each clones `scott_clear.wav` + renders panic/calm to `out/<engine>/` |
| `run_bakeoff.sh` | Orchestrates engines (skip-on-fail) → ffmpeg normalize → build index |
| `build_index.py` | Emits `out/index.md` (afplay) + `out/index.html` (inline players) |

## Engines

`zipvoice` (baseline, no emotion — proves the gap) · `chatterbox` (MIT, exaggeration knob) ·
`indextts2` (timbre⊥emotion, best fit) · `orpheus` (inline tags, preset voice) ·
`qwen3` (native MLX, instruct emotion, preset voice).

### Chatterbox-Turbo tag test (`gen_chatterbox_turbo.py`)

Separate run: clones Scott/Eli/TJ from `refs/*.wav` (Eli/TJ minted from the sidecar)
and renders `lines_turbo.json` with inline `[gasp]/[laugh]/[sigh]/[cough]/[chuckle]`
tags → `build_index_turbo.py` → `out/index_turbo.html`. Turbo **ignores `exaggeration`**
(base Chatterbox keeps the knob but parses no tags — they're complementary). Run:
`uv run --python-preference only-managed --python 3.12 --with chatterbox-tts --with torchaudio --with torchvision python gen_chatterbox_turbo.py`

Engines that fail to load are logged and skipped — not fatal. First runs pull
multi-GB models. The winner gets wired into `tts_server.py` + `tts_client.gd` later;
this harness is disposable.
