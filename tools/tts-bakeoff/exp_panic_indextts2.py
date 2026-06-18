#!/usr/bin/env python3
"""IndexTTS-2 panic version of TJ's triage line, for the panic A/B. Clones TJ timbre
from refs/tj.wav; pushes emotion via a strong natural-language emo_text. Output ->
out/panic_test/tj-triage-indextts2.wav.

Run: uv run --python-preference only-managed --python 3.11 \\
       --with "git+https://github.com/index-tts/index-tts" --with huggingface_hub --with soundfile python exp_panic_indextts2.py
"""
from __future__ import annotations

import os
from pathlib import Path

import common

REF = str(common.HERE / "refs" / "tj.wav")
TEXT = "Stay with me! I need a hand over here, now!"
EMO = "screaming in panic, terrified, shouting at the top of her lungs, frantic and breathless"


def main() -> int:
	out = common.engine_dir("panic_test")
	env = os.environ.get("INDEXTTS2_DIR")
	if env and Path(env).is_dir():
		ckpt = Path(env)
	else:
		from huggingface_hub import snapshot_download
		ckpt = Path(snapshot_download(repo_id="IndexTeam/IndexTTS-2"))
	from indextts.infer_v2 import IndexTTS2
	tts = IndexTTS2(cfg_path=str(ckpt / "config.yaml"), model_dir=str(ckpt), use_fp16=True)
	dst = str(out / "tj-triage-indextts2.wav")
	# emo_alpha cranks the emotion strength if the signature supports it.
	try:
		tts.infer(spk_audio_prompt=REF, text=TEXT, output_path=dst,
		          emo_text=EMO, use_emo_text=True, emo_alpha=1.0, verbose=False)
	except TypeError:
		tts.infer(spk_audio_prompt=REF, text=TEXT, output_path=dst,
		          emo_text=EMO, use_emo_text=True, verbose=False)
	print("wrote", dst)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
