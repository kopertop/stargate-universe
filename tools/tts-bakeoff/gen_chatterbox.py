#!/usr/bin/env python3
"""Chatterbox (Resemble AI) — MIT, emotion via a single `exaggeration` knob + cfg/temp.

Clones Scott's timbre from the reference clip; emotion intensity comes from the
per-line params in tags.chatterbox(). Apple-Silicon MPS support is inconsistent, so
we try MPS and fall back to CPU on any failure.

Run via:  uv run --with chatterbox-tts --with torchaudio python gen_chatterbox.py
"""
from __future__ import annotations

import sys

import common
import tags


def _pick_device():
	import torch
	if torch.backends.mps.is_available():
		return "mps"
	if torch.cuda.is_available():
		return "cuda"
	return "cpu"


def _shim_watermarker() -> None:
	# resemble-perth ships a stub on this platform: perth.PerthImplicitWatermarker is
	# None, so ChatterboxTTS.__init__ crashes ("'NoneType' object is not callable").
	# Watermarking is irrelevant to a bake-off — install a no-op so the model loads.
	import perth
	if getattr(perth, "PerthImplicitWatermarker", None) is None:
		class _NoWM:
			def apply_watermark(self, wav, sample_rate=None, **k):
				return wav

			def get_watermark(self, *a, **k):
				return None
		perth.PerthImplicitWatermarker = _NoWM


def _load(device: str):
	# Chatterbox checkpoints are CUDA-saved; on mps/cpu torch.load needs remapping.
	import torch
	from chatterbox.tts import ChatterboxTTS

	_shim_watermarker()

	_orig = torch.load
	def _patched(*a, **k):
		k.setdefault("map_location", torch.device(device))
		return _orig(*a, **k)
	torch.load = _patched
	try:
		return ChatterboxTTS.from_pretrained(device=device)
	finally:
		torch.load = _orig


def main() -> int:
	import torchaudio

	data = common.load_lines()
	ref = str(common.ref_wav())
	out = common.engine_dir("chatterbox")

	device = _pick_device()
	try:
		model = _load(device)
	except Exception as e:  # noqa: BLE001
		print(f"[chatterbox] {device} load failed ({e}); retrying on cpu", file=sys.stderr)
		device = "cpu"
		try:
			model = _load(device)
		except Exception as e2:  # noqa: BLE001
			print(f"[chatterbox] cpu load failed: {e2}", file=sys.stderr)
			common.write_meta("chatterbox", device="n/a", model="Chatterbox",
			                  entries=[], note=f"load failed: {e2}")
			return 0

	entries: list[dict] = []
	for line in data["lines"]:
		p = tags.chatterbox(line["tags"])
		fname = common.out_name(line)
		e = {"id": line["id"], "mood": line["mood"], "file": fname, "text": line["text"],
		     "params": p, "ok": False}
		try:
			with common.Timer() as t:
				wav = model.generate(
					line["text"], audio_prompt_path=ref,
					exaggeration=p["exaggeration"], temperature=p["temperature"],
					cfg_weight=p["cfg_weight"],
				)
			torchaudio.save(str(out / fname), wav, model.sr)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
			print(f"[chatterbox] {line['id']}: {ex}", file=sys.stderr)
		entries.append(e)

	common.write_meta("chatterbox", device=device, model="Chatterbox (ResembleAI)",
	                  entries=entries, note="exaggeration knob: panic high, calm low.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
