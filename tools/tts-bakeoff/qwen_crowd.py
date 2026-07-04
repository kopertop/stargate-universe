#!/usr/bin/env python3
"""One-shot VoiceDesign bakes for the cold-open CROWD lines (marine / civilian / officer)
that aren't one of our designed principals. With the no_vocals bed (voices stripped),
every caption needs a voice — these fill the generic background barks. VoiceDesign drift
between one-off lines is irrelevant for crowd, so no clone step. Output → sounds/dialog/prologue/.

Run:
  PHONEMIZER_ESPEAK_LIBRARY=$(brew --prefix espeak)/lib/libespeak.dylib \
  uv run --python-preference only-managed --with mlx-audio --with soundfile --with phonemizer \
    --prerelease=allow python tools/tts-bakeoff/qwen_crowd.py
"""
from __future__ import annotations

import time
from pathlib import Path

import mlx.core as mx
import numpy as np
import soundfile as sf
from mlx_audio.tts.utils import load_model

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "sounds" / "dialog" / "prologue"
MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

# (id, seed, instruct, text)
LINES = [
	("open-marine-clearway", 777,
	 "A male US marine soldier, gruff, shouting a fast urgent order over chaos.",
	 "Get out of the way!"),
	("open-crowd-where", 777,
	 "A frightened young American man, civilian, disoriented and breathless.",
	 "Where are we?"),
	("open-crowd-what", 1337,
	 "A frightened young American woman, civilian, confused and shaky.",
	 "What's going on?"),
	("open-wounded-broken", 2024,
	 "A young American man wincing in pain, strained, weak.",
	 "I think it's broken."),
	("open-marine-leaveit", 42,
	 "A male US marine sergeant, hard and commanding, fast.",
	 "Leave it — there'll be more coming through."),
	("open-marine-clear", 777,
	 "A male US marine shouting a sharp status call.",
	 "Clear!"),
	("open-officer-idontknow", 2024,
	 "A young American male junior officer, tense and apologetic under pressure.",
	 "I don't know, sir."),
	("open-crew-whatwasthat", 1337,
	 "A young American man, awed and breathless, disbelief.",
	 "What the hell was that?"),
]


def main() -> int:
	OUT.mkdir(parents=True, exist_ok=True)
	model = load_model(MODEL)
	ok = 0
	for vid, seed, instruct, text in LINES:
		mx.random.seed(seed)
		t0 = time.time()
		results = list(model.generate_voice_design(
			text=text, instruct=instruct, language="English", temperature=0.5,
		))
		sf.write(str(OUT / f"{vid}.wav"), np.array(results[0].audio), 24000)
		ok += 1
		print(f"[crowd] {vid:<24} {round(time.time() - t0, 1)}s")
	print(f"[crowd] done: {ok}/{len(LINES)} -> {OUT.relative_to(REPO)}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
