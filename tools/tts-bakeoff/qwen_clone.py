#!/usr/bin/env python3
"""Qwen3-TTS Base-model CLONE baker (Design→Clone step 2). Renders game-ready lines by
cloning the per-mode VoiceDesign reference clips minted by make_qwen_refs.py.

Each job line = {id, char, mode, text}. ref_audio = refs_qwen/<char>_<mode>.wav,
ref_text = REF_TEXT[char] (what that reference clip says). Output: out/qwen3_clone/<id>.wav.

Run:
  PHONEMIZER_ESPEAK_LIBRARY=$(brew --prefix espeak)/lib/libespeak.dylib \
  uv run --python-preference only-managed --with mlx-audio --with soundfile --with phonemizer \
    --prerelease=allow python tools/tts-bakeoff/qwen_clone.py [job]   # default job: cold_open
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf
from mlx_audio.tts.utils import load_model

from make_qwen_refs import REF_TEXT

HERE = Path(__file__).resolve().parent
REFS = HERE / "refs_qwen"
OUT = HERE / "out" / "qwen3_clone"
MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"


def main() -> int:
	job_name = sys.argv[1] if len(sys.argv) > 1 else "cold_open"
	job = json.loads((HERE / "jobs_qwen" / f"{job_name}.json").read_text())
	OUT.mkdir(parents=True, exist_ok=True)

	# Validate refs up front so a typo fails before the slow model load.
	plan = []
	for ln in job["lines"]:
		ref = REFS / f"{ln['char']}_{ln['mode']}.wav"
		if not ref.is_file():
			print(f"ERROR: line {ln['id']} -> missing ref {ref.name}", file=sys.stderr)
			return 1
		if ln["char"] not in REF_TEXT:
			print(f"ERROR: line {ln['id']} -> no REF_TEXT for char '{ln['char']}'", file=sys.stderr)
			return 1
		plan.append((ln, str(ref), REF_TEXT[ln["char"]]))
	print(f"[clone] job '{job_name}': {len(plan)} lines -> {OUT.relative_to(HERE.parent.parent)}")

	model = load_model(MODEL)
	ok = 0
	for ln, ref_path, ref_text in plan:
		dst = OUT / f"{ln['id']}.wav"
		try:
			t0 = time.time()
			results = list(model.generate(
				text=ln["text"], ref_audio=ref_path, ref_text=ref_text,
			))
			audio = np.array(results[0].audio)
			sf.write(str(dst), audio, 24000)
			ok += 1
			print(f"[clone] {ln['id']:<22} {ln['char']:<6} {ln['mode']:<9} {round(time.time() - t0, 1)}s")
		except Exception as e:  # noqa: BLE001
			print(f"[clone] FAIL {ln['id']}: {e}", file=sys.stderr)
	print(f"[clone] done: {ok}/{len(plan)} ok -> {OUT.relative_to(HERE.parent.parent)}")
	return 0 if ok == len(plan) else 2


if __name__ == "__main__":
	raise SystemExit(main())
