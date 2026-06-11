---
name: speak-voice
description: "Speak a line in a pre-computed character voice via the LuxTTS dialogue sidecar, and wire runtime voiced dialogue into the Godot game with TTSClient. Use when the user says 'speak as <character>', '/speak <voice> <text>', 'have <character> say ...', 'preview a voice line', 'add voiced dialogue', or wants an NPC/character to speak a dynamic line at runtime. Handles: starting/health-checking the sidecar, previewing a line (synthesize + play), listing available voices, and the TTSClient GDScript integration pattern for dynamic in-engine dialogue."
argument-hint: "[voice] [text to speak]  (e.g. /speak rush Try to keep up.)"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
model: sonnet
---

# Speak Voice

Runtime text-to-speech for **dynamic dialogue** in pre-computed character voices.
Full reference: **`docs/tts-dialogue.md`** (read it for the complete API + caching
+ adding voices). This skill is the operational shortcut.

Voices are fixed `.voice.pt` embeddings in `tools/tts-onnx-poc/voices/`; only the
text is dynamic (player names, conditions). The engine calls a resident sidecar.

## When invoked as `/speak <voice> <text>` — preview a line

1. **Ensure the sidecar is up** (idempotent):
   ```bash
   curl -s --max-time 3 http://127.0.0.1:8765/health || \
     (nohup tools/tts-onnx-poc/run_server.sh >/tmp/tts_server.log 2>&1 & \
      until curl -s --max-time 2 http://127.0.0.1:8765/health >/dev/null; do sleep 1; done)
   ```
   First start loads the model (~10 s); subsequent lines ~1.8 s (MPS).
2. **Validate the voice** against `/health`'s list. If unknown, tell the user the
   available voices (don't guess a substitute).
3. **Synthesize + play** (URL-encode the text):
   ```bash
   curl -s "http://127.0.0.1:8765/synthesize?voice=<voice>&text=<urlencoded>" -o /tmp/speak.wav && afplay /tmp/speak.wav
   ```
   Add `&seed=<n>` for reproducible prosody. To save for review, write to
   `~/Desktop/<voice>_<slug>.wav` instead of /tmp.

If no voice is given, default to listing voices and asking which to use.

## When the user wants voiced dialogue IN the game

Wire `scripts/tts_client.gd` (`TTSClient`). The pattern (see `docs/tts-dialogue.md` §3):

```gdscript
var tts := TTSClient.new()
add_child(tts)
tts.line_ready.connect(func(s): $AudioStreamPlayer.stream = s; $AudioStreamPlayer.play())
tts.say("rush", "Ah, %s. Try to keep up." % player_name)   # dynamic text
```

- `say(voice, text, seed := -1)` → `line_ready(stream)` / `line_failed(reason)`.
- Design for ~1.8 s latency (emote/pause, then play on `line_ready`).
- Cache recurring/non-dynamic lines to `user://voice_cache/` (bake-on-demand).
- The sidecar must be running for playback — see `docs/tts-dialogue.md` §1.

## Available voices

`chloe eli greer jack marine narrator rush scott telford tj wray young default`
(authoritative list = `/health`). Add/replace voices with `batch_enroll.py` or
`/tts enroll` (`docs/tts-dialogue.md` §5).

## Related

- `/tts` — render a voice line to an audio FILE (CLI), and enroll new voices.
- `docs/tts-dialogue.md` — full integration guide.
- `tools/tts-onnx-poc/` — sidecar, server, torch-free ONNX POC, native plan.
