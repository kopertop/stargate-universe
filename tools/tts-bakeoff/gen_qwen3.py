#!/usr/bin/env python3
"""Qwen3-TTS via mlx-audio — native MLX, fastest on Apple Silicon. Uses CustomVoice,
which supports emotion via an `instruct` directive (tags.qwen3_instruct()) but only on
5 PRESET speakers — so the voice is NOT cloned Scott. The cell tests Qwen3's emotion
control quality; timbre won't match. (Reuses the project's `mlx-audio-tts` skill recipe.)

Run via:
  PHONEMIZER_ESPEAK_LIBRARY=$(brew --prefix espeak)/lib/libespeak.dylib \\
  uv run --with mlx-audio --with soundfile --with phonemizer --prerelease=allow python gen_qwen3.py
"""
from __future__ import annotations

import sys

import common
import tags

MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"
PRESET_SPEAKER = "ryan"  # male preset


def main() -> int:
	import numpy as np
	import soundfile as sf
	from mlx_audio.tts.utils import load_model

	data = common.load_lines()
	out = common.engine_dir("qwen3")

	try:
		model = load_model(MODEL)
	except Exception as e:  # noqa: BLE001
		common.write_meta("qwen3", device="mlx", model="Qwen3-TTS CustomVoice",
		                  entries=[], note=f"load failed: {e}")
		print(f"[qwen3] unavailable: {e}", file=sys.stderr)
		return 0

	entries: list[dict] = []
	for line in data["lines"]:
		instruct = tags.qwen3_instruct(line["tags"])
		fname = common.out_name(line)
		e = {"id": line["id"], "mood": line["mood"], "file": fname,
		     "text": line["text"], "instruct": instruct, "ok": False}
		try:
			with common.Timer() as t:
				results = list(model.generate_custom_voice(
					text=line["text"], speaker=PRESET_SPEAKER,
					language="English", instruct=instruct,
				))
			audio = np.array(results[0].audio)
			sf.write(str(out / fname), audio, 24000)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
			print(f"[qwen3] {line['id']}: {ex}", file=sys.stderr)
		entries.append(e)

	common.write_meta("qwen3", device="mlx", model="Qwen3-TTS-1.7B CustomVoice",
	                  entries=entries, note=f"PRESET speaker '{PRESET_SPEAKER}' (not Scott); emotion via instruct.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
