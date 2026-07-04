# TTS-in-engine POC — torch-free ONNX LuxTTS

**Goal:** prove LuxTTS (ZipVoice) voice-cloning TTS can run *inside the game at
runtime* — generating dialogue audio **as needed** — instead of pre-baking every
WAV. Chosen path: **native ONNX in-engine** (no Python/torch sidecar).

**Status: keystone PROVEN.** The entire text→audio synthesis runs with **only
numpy + onnxruntime + soundfile — zero torch** (verified by synthesizing valid
48 kHz speech with `torch` imports forcibly blocked). That's exactly the compute
a Godot onnxruntime GDExtension (+ GDScript for the sampler arithmetic) performs.

## Why your "commit the embeddings" insight unlocked this

A pre-computed character voice embedding (`voices/<name>.voice.pt`, ~185 KB)
removes the two heaviest, least-portable runtime pieces — **Whisper** (prompt
transcription) and the **librosa** feature pipeline — because they only run at
*enroll* time. The runtime then needs just: tokenizer → text encoder → sampler →
flow-matching decoder → vocoder.

## What runs torch-free (this POC)

```
text tokens ─┐
             ▼
     text_encoder.onnx ──► text_condition (B, frames, 100)
             │
             ▼   flow-matching sampler loop (pure numpy, num_steps×)
     fm_decoder.onnx  ◄── x_t, t, guidance, speech_condition(=padded voice mel)
             │
             ▼
        mel features (B, 100, frames)
             │
             ▼
        vocos.onnx ──► waveform (B, T) @ 48 kHz
```

- **Sampler** (`infer_onnx.py`): `get_time_steps` + the ODE update are ~10 lines
  of arithmetic — trivially portable to GDScript.
- **Vocoder** (`export_vocos.py` + `onnx_istft.py`): the LuxTTS Vocos vocoder is
  torch-only on disk (`vocos.bin`). We export it to ONNX. Two things had to be
  solved: (1) `ScatterND` indices patched int32→int64; (2) `torch.istft` (which
  doesn't lower to ONNX — broadcast bug across opsets 17–21) replaced with an
  explicit overlap-add iSTFT (irfft-as-MatMul + ConvTranspose1d OLA + NOLA norm).
  Matches `torch.istft` to 3.6e-5 rel; full vocoder ONNX matches torch to MAE 3e-8.
- **Dropped:** the dual-path Linkwitz-Riley crossover (a phase-polish post-step).
  Single 48 kHz head only. Re-addable in numpy/GDScript later if the quality
  delta matters (rfft → static mask → irfft).
- **Tokenizer:** the one piece NOT yet ported. It does grapheme→phoneme via
  espeak (`piper_phonemize`). `precompute_tokens.py` sidesteps it: tokenize
  authored dialogue at dev time and ship the int token arrays. (A true
  "speak arbitrary runtime text" feature would need espeak-ng native in-engine.)

## Runtime footprint (what you'd ship)

| Component | Size |
|---|---|
| `text_encoder_int8.onnx` | 5 MB |
| `fm_decoder_int8.onnx` | 119 MB |
| `vocos.onnx` | ~70 MB |
| `voices/*.npz` (per character) | ~185 KB each |
| onnxruntime native lib | ~50–200 MB (platform) |
| **Total model** | **~195 MB** + onnxruntime |

No torch (~2 GB) and no Whisper (281 MB) at runtime. Desktop-shippable; mobile
plausible; web not without onnxruntime-web work.

**Latency:** model resident → short line ≈ 1–2 s. "Dynamic" = NPC pauses a beat,
then speaks. Not instant; keep the session warm (don't reload per line).

## Run it (dev machine, LuxTTS venv at ~/.cache/luxtts/.venv)

```bash
PY=~/.cache/luxtts/.venv/bin/python
SNAP=$(find ~/.cache/huggingface/hub/models--YatharthS--LuxTTS/snapshots -mindepth 1 -maxdepth 1 -type d | head -1)

# one-time exports
$PY export_vocos.py                                              # -> artifacts/vocos.onnx
$PY export_voice.py --in ~/.cache/luxtts/voices/eli.voice.pt --out artifacts/eli.npz
$PY precompute_tokens.py --text "Your line here." --out artifacts/tokens.json

# torch-free synthesis
$PY infer_onnx.py --voice artifacts/eli.npz --tokens artifacts/tokens.json \
    --models "$SNAP" --vocos artifacts/vocos.onnx --out artifacts/onnx_out.wav
```

`artifacts/` is git-ignored (large model blobs). Enroll voices with the `/tts`
skill (`--enroll`), then `export_voice.py` to the portable `.npz`.

## Godot integration plan (next stage)

The compute is proven portable. Remaining work is engine plumbing:

1. **ONNX runtime in Godot** via a GDExtension. Maintained options:
   - [joemarshall/godot_onnx_extension](https://github.com/joemarshall/godot_onnx_extension) — `model.run(PackedFloat32Array)` (flatten inputs).
   - [mat490/Godot-ONNX-AI-Models-Loaders](https://github.com/mat490/Godot-ONNX-AI-Models-Loaders) — `ONNXLoader` node, `predict(Array)`.
   - [kaiidams/NeMoOnnxGodot](https://github.com/kaiidams/NeMoOnnxGodot) — precedent: a NeMo+ONNX **speech** engine in Godot ([asset lib](https://godotengine.org/asset-library/asset/2298)). C# path (NeMoOnnxSharp) is viable too.
2. **Port the sampler** to GDScript — see `godot/tts_onnx.gd` (the ODE loop +
   `get_time_steps`; arithmetic only, no ML).
3. **Ship artifacts** as Godot resources: the three `.onnx` files + per-character
   `.npz` (convert to `PackedFloat32Array` / a `.tres`).
4. **Dialogue authoring**: store precomputed token arrays alongside each line
   (extend the dialogue data), or add espeak-ng native for arbitrary text.
5. **Threading**: run inference on a worker thread; stream the resulting
   `PackedFloat32Array` into an `AudioStreamGenerator`. Cache to `user://` for
   bake-on-demand (generate once, reuse forever).

## Sidecar architecture (dynamic lines in-engine, shipping NOW)

For **fully dynamic runtime text** (player names, unplanned conditions) with
**pre-computed voices**, the engine calls a resident LuxTTS sidecar over HTTP.
This works today — no native build — and uses the real espeak tokenizer, so any
text synthesizes at full quality. Voices are fixed `.voice.pt` embeddings.

```
Godot (TTSClient, HTTPRequest) ──GET /synthesize?voice=rush&text=…──► tts_server.py (model resident)
        ◄────────────────── 48kHz WAV bytes ──────────────────────────┘
   AudioStreamWAV.load_from_buffer() → AudioStreamPlayer
```

- **Server:** `tts_server.py` — loads LuxTTS once, caches voice embeddings,
  `/health` + `/synthesize`. Launch: `./run_server.sh` (uses committed `voices/`).
- **Client:** `scripts/tts_client.gd` (`TTSClient` node) — `say(voice, text, seed)`,
  emits `line_ready(stream)` / `line_failed(reason)`.
- **Latency:** ~1.8 s for a ~4.5 s line on MPS, model warm. Run on a worker so
  the game doesn't block; cache results to `user://` for replays.

### Run the round-trip (proves Godot drives it end-to-end)

```bash
# 1) start the sidecar
tools/tts-onnx-poc/run_server.sh
# 2) headless Godot round-trip (set GODOT_BIN if 'godot' isn't on PATH)
GODOT_BIN=/path/to/Godot
"$GODOT_BIN" --headless --path . \
    --script res://tools/tts-onnx-poc/godot/test_tts_roundtrip.gd
```

Server side is verified (curl + audible output, ~1.8 s warm). The headless Godot
test was **not run here** — Godot isn't installed on this machine (the
`/Applications/Godot.app` alias is stale) — but `tts_client.gd` +
`test_tts_roundtrip.gd` are ready to run once `GODOT_BIN` points at a Godot 4.6+.

### Productionizing the sidecar (later)

- Ship the venv+model with desktop builds, or convert the server to the torch-free
  ONNX pipeline (smaller). Launch it from Godot on game start; health-check before use.
- Desktop-only. For other platforms, the all-native GDExtension path (linking
  onnxruntime + espeak-ng) is the eventual answer — see commit history / the
  GDScript scaffold for that route.

## Open items / honest gaps

- Tokenizer not ported (dev-time precompute used instead).
- Crossover phase-polish dropped (single-head vocoder).
- Godot extension not yet integrated — this POC validates the *pipeline*, the
  artifacts, and the math; engine wiring is the next milestone.
