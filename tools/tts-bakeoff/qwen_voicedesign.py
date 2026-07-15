#!/usr/bin/env python3
"""Qwen3-TTS VoiceDesign exploration: design Scott / Greer / Eli voices from text
DESCRIPTIONS (no reference clip) in a STANDARD and a PANIC register, across a few
seeds so we can audition and pick. Step 1 of the skill's Design -> Clone workflow.

Run:
  PHONEMIZER_ESPEAK_LIBRARY=$(brew --prefix espeak)/lib/libespeak.dylib \
  uv run --with mlx-audio --with soundfile --with phonemizer --prerelease=allow \
    python tools/tts-bakeoff/qwen_voicedesign.py
"""
from __future__ import annotations

import time
from pathlib import Path

import mlx.core as mx
import numpy as np
import soundfile as sf
from mlx_audio.tts.utils import load_model

OUT = Path("tools/tts-bakeoff/out/qwen3_voicedesign")
OUT.mkdir(parents=True, exist_ok=True)

MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

# Per-character VOICE identity (timbre) + that character's representative line. Every
# character is spoken in all four MODES below so we can audition their delivery range.
CHARS = {
	"scott": ("A young American male military officer in his late twenties. Clear, mid-range voice.",
	          "This is Scott. Slow down the evac — we're coming in too hot!"),
	"greer": ("A tough African American male marine sergeant with a Deep South accent. "
	          "Low, gravelly, rough voice.",
	          "Clear! Keep 'em moving!"),
	"eli":   ("A large, heavyset young adult American male in his early twenties with a New "
	          "York City accent. Deep, full, resonant voice.",
	          "Okay... what is this place?"),
	"rush":  ("A male scientist in his forties with a British accent. Dry, clipped, "
	          "intense, intellectual voice.",
	          "This ship could be the most important discovery mankind has ever made."),
	"young": ("An older American male military colonel in his fifties. Gravelly, rough "
	          "smoker's voice. Weary, gruff, commanding.",
	          "This is my ship. We do this my way."),
	"tj":    ("A young blonde American female military medic in her late twenties. Warm, "
	          "calm, steady, clear voice.",
	          "Stay with me. You're gonna be okay."),
	# Cold-open named extras (transcript §1).
	"wray":  ("A composed American woman in her forties, a professional IOA bureaucrat. "
	          "Controlled, articulate, slightly clipped.",
	          "Where are we? Why didn't we come through to Earth?"),
	"chloe": ("A refined young American woman in her mid twenties. Clear, earnest, a little shaken.",
	          "Are you okay?"),
	"senator": ("An older American male in his late fifties, a U.S. senator. Gravelly, "
	          "authoritative, weary gravitas.",
	          "Where the hell are we?"),
	"marine": ("A young American male U.S. marine. Gruff, urgent, hard-edged.",
	          "I need a medic!"),
	"civ":   ("A frightened young American male civilian. Disoriented, breathless.",
	          "I think my arm is broken."),
}
# Delivery modifier appended to the voice description for each mode.
MODES = {
	"standard": "Even, measured, natural delivery — calm and clear.",
	"barked":   "BARKING the line at a yell — loud, hard, sharp, authoritative. "
	            "Controlled aggression: NOT panicked, NOT calm.",
	"panic":    "Shouting over chaos — fast, clipped, breathless, panicked and urgent.",
	"whisper":  "A hushed, breathy whisper — quiet, tense, low volume, urgent under the breath.",
}
MODE_ORDER = ["standard", "barked", "panic", "whisper"]
# Leave the user's chosen take byte-identical — regenerating would change the audio.
PRESERVE = {("scott", "panic")}

JOBS = []
for _c, (_voice, _line) in CHARS.items():
	for _m in MODE_ORDER:
		if (_c, _m) in PRESERVE:
			continue
		JOBS.append((_c, _m, f"{_voice} {MODES[_m]}", _line))

SEEDS = [42, 777, 2024, 1337]


def main() -> int:
	import sys
	# optional char filter: one or comma-separated, e.g. "greer" or "wray,chloe,senator"
	only = set(sys.argv[1].lower().split(",")) if len(sys.argv) > 1 else None
	model = load_model(MODEL)
	n = 0
	for char, mood, instruct, text in JOBS:
		if only and char not in only:
			continue
		for seed in SEEDS:
			mx.random.seed(seed)
			t0 = time.time()
			results = list(model.generate_voice_design(
				text=text, instruct=instruct, language="English", temperature=0.5,
			))
			audio = np.array(results[0].audio)
			dst = OUT / f"{char}-{mood}-seed{seed}.wav"
			sf.write(str(dst), audio, 24000)
			n += 1
			print(f"[vd] {dst.name:<28} {round(time.time() - t0, 1)}s")
	print(f"[vd] done: {n} files -> {OUT}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
