#!/usr/bin/env python3
"""Mint per-mode Qwen clone REFERENCE clips from the picked VoiceDesign takes.

Chris picked a seed per character (some per-mode). This copies the chosen
out/qwen3_voicedesign/<char>-<mode>-seed<n>.wav into a clean, named reference set
out/../refs_qwen/<char>_<mode>.wav  (e.g. eli_standard.wav, eli_panic.wav, ...),
which the Base-model clone baker (qwen_clone.py) uses as ref_audio per (char, mode).

Run:  python tools/tts-bakeoff/make_qwen_refs.py
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "out" / "qwen3_voicedesign"
DST = HERE / "refs_qwen"

MODES = ["standard", "barked", "panic", "whisper"]

# Picked seed per (char, mode). Greer/Eli/Rush use one seed across all modes;
# Scott/Young/TJ are per-mode. Scott's non-panic modes default to 777 (his panic
# pick) until Chris picks otherwise.
PICKS: dict[str, dict[str, int]] = {
	"scott": {"standard": 777, "barked": 777, "panic": 777, "whisper": 777},
	"greer": {"standard": 42, "barked": 42, "panic": 42, "whisper": 42},
	"eli":   {"standard": 1337, "barked": 1337, "panic": 1337, "whisper": 1337},
	"rush":  {"standard": 2024, "barked": 2024, "panic": 2024, "whisper": 2024},
	"young": {"standard": 777, "barked": 2024, "panic": 2024, "whisper": 2024},
	"tj":    {"standard": 1337, "barked": 1337, "panic": 777, "whisper": 777},
	# Cold-open named extras (full-auto seed picks).
	"wray":    {"standard": 777, "barked": 777, "panic": 777, "whisper": 777},
	"chloe":   {"standard": 1337, "barked": 1337, "panic": 1337, "whisper": 1337},
	"senator": {"standard": 2024, "barked": 2024, "panic": 2024, "whisper": 2024},
	"marine":  {"standard": 42, "barked": 42, "panic": 42, "whisper": 42},
	"civ":     {"standard": 777, "barked": 777, "panic": 777, "whisper": 777},
}

# What each character's VoiceDesign reference clip actually SAYS (= ref_text for cloning).
REF_TEXT: dict[str, str] = {
	"scott": "This is Scott. Slow down the evac — we're coming in too hot!",
	"greer": "Clear! Keep 'em moving!",
	"eli": "Okay... what is this place?",
	"rush": "This ship could be the most important discovery mankind has ever made.",
	"young": "This is my ship. We do this my way.",
	"tj": "Stay with me. You're gonna be okay.",
	"wray": "Where are we? Why didn't we come through to Earth?",
	"chloe": "Are you okay?",
	"senator": "Where the hell are we?",
	"marine": "I need a medic!",
	"civ": "I think my arm is broken.",
}


def main() -> int:
	DST.mkdir(parents=True, exist_ok=True)
	missing, n = [], 0
	for char, modes in PICKS.items():
		for mode in MODES:
			seed = modes[mode]
			src = SRC / f"{char}-{mode}-seed{seed}.wav"
			if not src.is_file():
				missing.append(src.name)
				continue
			shutil.copy2(src, DST / f"{char}_{mode}.wav")
			n += 1
			print(f"[refs] {char}_{mode}.wav  <- {src.name}")
	if missing:
		print("MISSING:", ", ".join(missing), file=sys.stderr)
		return 1
	print(f"[refs] done: {n} reference clips -> {DST.relative_to(HERE.parent.parent)}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
