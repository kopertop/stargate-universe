#!/usr/bin/env python3
"""IndexTTS-2 — timbre⊥emotion disentanglement: clone Scott's voice from the reference
clip AND steer emotion independently via a plain-English instruction (tags.indextts2()).
This is the only candidate that does BOTH at once, which is exactly the requirement.

Heavy: pulls the index-tts package + several-GB checkpoints from HuggingFace on first
run, and may not build cleanly on macOS. Logged-and-skipped on failure (not fatal).

Run via:
  uv run --with "git+https://github.com/index-tts/index-tts" \\
         --with huggingface_hub --with soundfile python gen_indextts2.py

Set INDEXTTS2_DIR to a pre-downloaded checkpoint dir to skip the HF pull.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import common
import tags

HF_REPO = "IndexTeam/IndexTTS-2"


def _ensure_checkpoints() -> Path:
	env = os.environ.get("INDEXTTS2_DIR")
	if env and Path(env).is_dir():
		return Path(env)
	from huggingface_hub import snapshot_download
	return Path(snapshot_download(repo_id=HF_REPO))


def main() -> int:
	data = common.load_lines()
	ref = str(common.ref_wav())
	out = common.engine_dir("indextts2")

	try:
		ckpt = _ensure_checkpoints()
		from indextts.infer_v2 import IndexTTS2
		cfg = ckpt / "config.yaml"
		tts = IndexTTS2(cfg_path=str(cfg), model_dir=str(ckpt), use_fp16=True)
	except Exception as e:  # noqa: BLE001
		common.write_meta("indextts2", device="n/a", model="IndexTTS-2",
		                  entries=[], note=f"load/build failed on this host: {e}")
		print(f"[indextts2] unavailable: {e}", file=sys.stderr)
		return 0

	entries: list[dict] = []
	for line in data["lines"]:
		emo = tags.indextts2(line["tags"])  # plain-English emotion instruction
		fname = common.out_name(line)
		dst = str(out / fname)
		e = {"id": line["id"], "mood": line["mood"], "file": fname,
		     "text": line["text"], "emo_text": emo, "ok": False}
		try:
			with common.Timer() as t:
				# spk_audio_prompt = timbre (Scott); emo_text = independent emotion.
				tts.infer(spk_audio_prompt=ref, text=line["text"], output_path=dst,
				          emo_text=emo, use_emo_text=True, verbose=False)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
			print(f"[indextts2] {line['id']}: {ex}", file=sys.stderr)
		entries.append(e)

	common.write_meta("indextts2", device="auto", model="IndexTTS-2",
	                  entries=entries, note="Scott timbre cloned; emotion via emo_text instruction.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
