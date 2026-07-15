#!/usr/bin/env python3
"""Offline IndexTTS-2 voice-line baker. Pre-renders scripted/emotional lines to WAVs the
game plays directly (the live LuxTTS sidecar still handles fast dynamic lines). IndexTTS-2
is too slow (~30-130s/line here) for runtime, but gives true timbre⊥emotion control.

Reads a job (tools/tts-bake/jobs/<name>.json): each line has voice (-> voices.json ref
clip), text, and an emotion preset (emotions.py) or free-text emo_text override. Clones
the character timbre, applies the emotion, writes <out_dir>/<id>.wav under the repo.

Run via tools/tts-bake/run.sh (handles uv py3.11 + godot --import). Direct:
  uv run --python-preference only-managed --python 3.11 \\
    --with "git+https://github.com/index-tts/index-tts" --with huggingface_hub --with soundfile \\
    python bake.py [job_name]      # default job: cold_open
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import emotions

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent  # tools/tts-bake -> tools -> repo
HF_REPO = "IndexTeam/IndexTTS-2"


def _load_index_tts():
	env = os.environ.get("INDEXTTS2_DIR")
	if env and Path(env).is_dir():
		ckpt = Path(env)
	else:
		from huggingface_hub import snapshot_download
		ckpt = Path(snapshot_download(repo_id=HF_REPO))
	from indextts.infer_v2 import IndexTTS2
	return IndexTTS2(cfg_path=str(ckpt / "config.yaml"), model_dir=str(ckpt), use_fp16=True)


def main() -> int:
	job_name = sys.argv[1] if len(sys.argv) > 1 else "cold_open"
	job = json.loads((HERE / "jobs" / f"{job_name}.json").read_text())
	voices = {k: v for k, v in json.loads((HERE / "voices.json").read_text()).items()
	          if not k.startswith("_")}
	out_dir = REPO / job.get("out_dir", "sounds/dialog/prologue")
	out_dir.mkdir(parents=True, exist_ok=True)

	# Validate refs + emotions up front so a typo fails before the slow model load.
	plan = []
	for ln in job["lines"]:
		ref = voices.get(ln["voice"])
		if ref is None:
			print(f"ERROR: line {ln['id']} uses unknown voice '{ln['voice']}'", file=sys.stderr)
			return 1
		ref_path = REPO / ref
		if not ref_path.is_file():
			print(f"ERROR: ref clip missing for {ln['id']}: {ref_path}", file=sys.stderr)
			return 1
		emo_text, emo_alpha = emotions.resolve(ln.get("emotion"), ln.get("emo_text"), ln.get("emo_alpha"))
		plan.append((ln, str(ref_path), emo_text, emo_alpha))
	print(f"[bake] job '{job_name}': {len(plan)} lines -> {out_dir.relative_to(REPO)}")

	tts = _load_index_tts()

	report = []
	for ln, ref_path, emo_text, emo_alpha in plan:
		dst = out_dir / f"{ln['id']}.wav"
		rec = {"id": ln["id"], "voice": ln["voice"], "emotion": ln.get("emotion"),
		       "emo_text": emo_text, "emo_alpha": emo_alpha, "text": ln["text"], "ok": False}
		try:
			t0 = time.time()
			# spk_audio_prompt = timbre (the character); emo_text = independent emotion.
			try:
				tts.infer(spk_audio_prompt=ref_path, text=ln["text"], output_path=str(dst),
				          emo_text=emo_text, use_emo_text=True, emo_alpha=emo_alpha, verbose=False)
			except TypeError:  # older signature without emo_alpha
				tts.infer(spk_audio_prompt=ref_path, text=ln["text"], output_path=str(dst),
				          emo_text=emo_text, use_emo_text=True, verbose=False)
			rec["ok"] = dst.is_file()
			rec["seconds"] = round(time.time() - t0, 1)
			print(f"[bake] {ln['id']:<22} {ln['voice']:<7} {ln.get('emotion','-'):<9} {rec.get('seconds')}s")
		except Exception as e:  # noqa: BLE001
			rec["error"] = str(e)
			print(f"[bake] FAIL {ln['id']}: {e}", file=sys.stderr)
		report.append(rec)

	(HERE / f"bake_report_{job_name}.json").write_text(json.dumps(report, indent=2))
	ok = sum(1 for r in report if r["ok"])
	print(f"[bake] done: {ok}/{len(report)} ok -> {out_dir.relative_to(REPO)}")
	print("[bake] NEXT: run `godot --headless --import` so the WAVs get .import sidecars "
	      "(else AudioStream load() returns null in-game).")
	return 0 if ok == len(report) else 2


if __name__ == "__main__":
	raise SystemExit(main())
