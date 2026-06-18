#!/usr/bin/env python3
"""Orpheus 3B (Canopy Labs) — Apache-2.0, inline emotion tags (<sigh>/<gasp>/<laugh>).

Orpheus's strength is paralinguistic tags in the text; its zero-shot cloning is weak,
so this uses a PRESET male voice (not cloned Scott). The bake-off cell therefore tests
"how good is Orpheus's tag-driven emotion?" — accept that the timbre won't match Scott.

Apple-Silicon path is via mlx-audio (native MLX). If the Orpheus model can't be loaded
here, the engine is logged and skipped (not fatal).

Run via:  uv run --with mlx-audio --with soundfile --with phonemizer --prerelease=allow python gen_orpheus.py
"""
from __future__ import annotations

import sys

import common
import tags

# Common MLX community Orpheus ids; first that loads wins.
MODEL_CANDIDATES = [
	"mlx-community/orpheus-3b-0.1-ft-bf16",
	"mlx-community/orpheus-3b-0.1-ft-4bit",
]
PRESET_VOICE = "leo"  # Orpheus built-in male voice


def _load():
	from mlx_audio.tts.utils import load_model
	last = None
	for mid in MODEL_CANDIDATES:
		try:
			return load_model(mid), mid
		except Exception as e:  # noqa: BLE001
			last = e
			print(f"[orpheus] {mid} failed: {e}", file=sys.stderr)
	raise last  # type: ignore[misc]


def main() -> int:
	import numpy as np
	import soundfile as sf

	data = common.load_lines()
	out = common.engine_dir("orpheus")

	try:
		model, mid = _load()
	except Exception as e:  # noqa: BLE001
		common.write_meta("orpheus", device="n/a", model="Orpheus 3B",
		                  entries=[], note=f"load failed on this host: {e}")
		return 0

	entries: list[dict] = []
	for line in data["lines"]:
		text = tags.orpheus(line["text"], line["tags"])
		fname = common.out_name(line)
		e = {"id": line["id"], "mood": line["mood"], "file": fname, "text": text, "ok": False}
		try:
			with common.Timer() as t:
				results = list(model.generate(text=text, voice=PRESET_VOICE))
			audio = np.array(results[0].audio)
			sf.write(str(out / fname), audio, 24000)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
			print(f"[orpheus] {line['id']}: {ex}", file=sys.stderr)
		entries.append(e)

	common.write_meta("orpheus", device="mlx", model=f"Orpheus 3B ({mid})",
	                  entries=entries, note=f"PRESET voice '{PRESET_VOICE}' (not cloned Scott); tags inline.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
