# Dynamic Voice Dialogue (TTS)

Generate **spoken dialogue at runtime** in the engine — any line, including
player names and unplanned conditions — using **pre-computed character voices**.
Voices are fixed; only the text is dynamic.

Architecture: the engine calls a resident **LuxTTS sidecar** over HTTP. The
sidecar keeps the model warm and tokenizes arbitrary text with the real espeak
phonemizer (which is why dynamic text "just works" at full quality).

```
Godot (TTSClient → HTTPRequest) ──GET /synthesize?voice=rush&text=…──► tts_server.py (model resident, MPS)
        ◄───────────────────── 48 kHz WAV bytes ───────────────────────┘
   AudioStreamWAV.load_from_buffer() → AudioStreamPlayer / AudioStreamPlayer3D
```

> Why a sidecar (not in-engine ONNX)? Arbitrary runtime text needs espeak-ng,
> a C library that can't be ported to GDScript. The sidecar already has it. The
> all-native GDExtension route is documented in `tools/tts-onnx-poc/` for later.

## 1. Start the sidecar

```bash
tools/tts-onnx-poc/run_server.sh           # http://127.0.0.1:8765, uses committed voices/
```

First launch loads the model (~10 s). After that each line is ~1.8 s on Apple
Silicon (MPS). Health check:

```bash
curl -s http://127.0.0.1:8765/health
# {"status":"ok","device":"mps","voices":["chloe","eli","greer","jack",...]}
```

The sidecar requires the LuxTTS runtime (`~/.cache/luxtts/.venv`). If it's
missing, run the `/tts` skill's `setup.sh` once.

## 2. Available voices

Pre-computed embeddings live in `tools/tts-onnx-poc/voices/<name>.voice.pt`
(committed). Current cast:

`chloe`, `default`, `eli`, `greer`, `jack`, `marine`, `narrator`, `rush`,
`scott`, `telford`, `tj`, `wray`, `young`

`/health` always returns the live list. To add/replace a voice, see §5.

## 3. Speak a line in-engine (`TTSClient`)

`scripts/tts_client.gd` (`class_name TTSClient`). Add it to a scene, connect
`line_ready`, call `say()`:

```gdscript
@onready var _player := $AudioStreamPlayer    # or AudioStreamPlayer3D for positional
var _tts: TTSClient

func _ready() -> void:
	_tts = TTSClient.new()
	add_child(_tts)
	_tts.line_ready.connect(func(stream: AudioStreamWAV) -> void:
		_player.stream = stream
		_player.play())
	_tts.line_failed.connect(func(reason: String) -> void:
		push_warning("TTS failed: %s" % reason))

func greet(player_name: String) -> void:
	# Dynamic text — player name injected at runtime, spoken in Rush's voice.
	_tts.say("rush", "Ah, %s. Try to keep up." % player_name)
```

API:
- `say(voice: String, text: String, seed: int = -1)` — `seed >= 0` makes prosody
  reproducible; `-1` lets it vary naturally per call.
- `signal line_ready(stream: AudioStreamWAV)` — decoded, ready to assign + `play()`.
- `signal line_failed(reason: String)` — server down, unknown voice, decode error.
- `@export var server_url := "http://127.0.0.1:8765"` — override if remote.

## 4. Latency, threading, caching

- ~1.8 s for a ~4.5 s line (model warm). It's an async HTTP call, so it won't
  block the frame — but the audio isn't instant. Design for it: have the NPC
  pause/emote, then play on `line_ready`.
- **Cache repeated lines.** For non-dynamic or recurring lines, save the stream
  to `user://voice_cache/<hash>.wav` on first generation and reuse — bake-on-demand.
- One sidecar serves the whole game; start it once (a launcher autoload that
  spawns/health-checks it, or run it alongside the editor during development).

## 5. Add or replace a voice

Enroll from a clean 5–10 s reference clip (single speaker, no music/SFX):

```bash
# many at once (one model load):
~/.cache/luxtts/.venv/bin/python tools/tts-onnx-poc/batch_enroll.py --src <dir-of-wavs>
# or one via the /tts skill:
/tts enroll voice=path/to/clip.wav name=<character>
```

Then copy the resulting `~/.cache/luxtts/voices/<name>.voice.pt` into
`tools/tts-onnx-poc/voices/` and commit it. Restart the sidecar to pick it up.

## 6. Dev preview (no engine)

Quick listen while writing dialogue:

```bash
curl -s "http://127.0.0.1:8765/synthesize?voice=rush&text=Hello%20there." -o /tmp/line.wav && afplay /tmp/line.wav
```

Or the `/speak` skill (`/speak rush Hello there.`), or the `/tts` skill to render
a file. See `tools/tts-onnx-poc/README.md` for the full POC + the torch-free ONNX
pipeline and the all-native GDExtension plan.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `line_failed: result/http` | Sidecar not running → `run_server.sh`; check `/health`. |
| `unknown voice 'x'` | Not in `voices/`; check `/health` list, enroll it (§5). |
| `Failed to decode WAV` | Need Godot **4.4+** (`AudioStreamWAV.load_from_buffer`). |
| First line very slow | Cold model load (~10 s); subsequent lines ~1.8 s. |
| `HTTPRequest ... ERR_UNCONFIGURED` in a `-s` SceneTree test | Node not in tree yet — `await process_frame` after `add_child` before `say()`. In-game (normal nodes) this isn't needed. |

> **Verified** (2026-06-11): Godot 4.6.3 → sidecar → decoded a 4.52 s dynamic
> line in-engine (`tools/tts-onnx-poc/godot/test_tts_roundtrip.gd`).

## File map

| File | Role |
|---|---|
| `scripts/tts_client.gd` | Runtime client node (`TTSClient`). |
| `tools/tts-onnx-poc/tts_server.py` | Resident sidecar (HTTP). |
| `tools/tts-onnx-poc/run_server.sh` | Launcher (uses committed voices). |
| `tools/tts-onnx-poc/voices/*.voice.pt` | Pre-computed character voices. |
| `tools/tts-onnx-poc/godot/test_tts_roundtrip.gd` | Headless round-trip test. |
| `tools/tts-onnx-poc/README.md` | POC details + native path. |

## P3 TTS Dialogue Integration

The TTSClient is now integrated into `dialog_screen.gd` (the Fable-style
conversation screen). Every spoken dialogue line is voiced through the
TTSClient when the sidecar is available.

### Per-character voice profiles

`data/characters.json` now includes a `tts_voice` field for each character,
mapping their display name to a pre-computed voice embedding:

| Character | Voice | Default emotion |
|---|---|---|
| Eli / Eli Wallace | `eli` | curious |
| Lt Scott | `scott` | determined |
| Dr Rush | `rush` | calm |
| Colonel Young | `young` | determined |
| Chloe Armstrong | `chloe` | neutral |
| Sgt Greer | `greer` | determined |
| Camile Wray | `wray` | calm |
| TJ / Lt James / Dr James / TJ Johansen | `tj` | calm |
| Soldier | `marine` | neutral |
| Others (Brody, Park, Volker, Varro) | `default` | neutral |

`TTSClient.voice_for(speaker)` resolves any display name to its TTS voice
(statically, without an instance). `TTSClient.emotion_for(speaker)` returns
the character's default emotion.

### Emotional inflection

Dialogue tree nodes may carry an optional `emotion` key:

```gdscript
{"speaker": "Dr Rush", "text": "We need to leave NOW.", "emotion": "urgent"}
```

Valid emotions: `neutral`, `urgent`, `calm`, `angry`, `afraid`, `sad`,
`curious`, `determined`. The emotion is passed as a query parameter to the
sidecar (the server may ignore it if it doesn't support emotion steering yet).
If not specified, the character's `default_emotion` from characters.json is
used.

### Ancient language TTS

Dialogue tree nodes may carry `"ancient": true` for Ancient-language lines.
These use the `ancient_voice` (default: `narrator`) with a pitch shift
(default: 0.85, making the voice sound deeper/otherworldly):

```gdscript
{"speaker": "Dr Rush", "text": "The database reveals the ship's mission.", "ancient": true}
```

### Subtitle + voice

The subtitle text is always displayed immediately (the existing Fable-style
bottom-centre subtitle). When the TTS stream arrives (~1.8s), it plays on the
`Voice` audio bus on top of the subtitle. The player sees the text right away
and hears the voice a moment later — no blocking, no wait.

### Text-only fallback

If the TTS sidecar is unreachable or `enable_tts` is false:
- `line_failed` fires silently (logged as a warning).
- The subtitle text alone is the full presentation — no audio plays.
- No crash, no visible error to the player.

### In-memory caching

The TTSClient caches synthesized streams by `(voice, text, seed, emotion, ancient)`
composite key. Repeated lines (e.g. re-reading the same NPC) reuse the cached
stream without a network round-trip. `clear_cache()` flushes it.

### Voice audio bus

A new `Voice` bus was added to `default_bus_layout.tres` (route: Voice → Master).
The Settings autoload has a `voice_volume` property (0.0–1.0) that persists
to `user://settings.cfg` and applies to the Voice bus on boot.

### High-level API

```gdscript
# Low-level: specify voice directly
tts.say("rush", "Lieutenant, report to the gate room.")

# High-level: resolve voice + emotion from speaker name
tts.say_line("Dr Rush", "Ah, Eli. Try to keep up.")

# With emotion override
tts.say_line("Dr Rush", "We need to leave NOW.", "urgent")

# Ancient language mode (narrator voice + pitch shift)
tts.say_line("Dr Rush", "The ship's mission is revealed.", "", true)
```
