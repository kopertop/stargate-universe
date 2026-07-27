#!/usr/bin/env python3
"""Chatterbox-Turbo — distilled one-step decoder that ALSO parses inline paralinguistic
tags ([gasp]/[laugh]/[sigh]/[cough]/[chuckle]) the base model ignores. Clones each
character from a fixed reference clip in refs/ and renders the tagged lines in
lines_turbo.json, with a per-line `exaggeration` for emotional intensity.

Run via:
  uv run --python-preference only-managed --python 3.12 \\
         --with chatterbox-tts --with torchaudio --with torchvision python gen_chatterbox_turbo.py
"""
from __future__ import annotations

import json
import sys

import common


def _shim_watermarker() -> None:
	# resemble-perth ships a stub here (PerthImplicitWatermarker is None), which
	# crashes model init. Watermarking is irrelevant to a sample render — no-op it.
	import perth
	if getattr(perth, "PerthImplicitWatermarker", None) is None:
		class _NoWM:
			def apply_watermark(self, wav, sample_rate=None, **k):
				return wav

			def get_watermark(self, *a, **k):
				return None
		perth.PerthImplicitWatermarker = _NoWM


def _pick_device():
	import torch
	if torch.backends.mps.is_available():
		return "mps"
	if torch.cuda.is_available():
		return "cuda"
	return "cpu"


def _load(device: str):
	import torch
	from chatterbox.tts_turbo import ChatterboxTurboTTS

	_shim_watermarker()
	_orig = torch.load
	def _patched(*a, **k):
		k.setdefault("map_location", torch.device(device))
		return _orig(*a, **k)
	torch.load = _patched
	try:
		return ChatterboxTurboTTS.from_pretrained(device=device)
	finally:
		torch.load = _orig


def main() -> int:
	import torchaudio

	data = json.loads((common.HERE / "lines_turbo.json").read_text())
	chars = data["characters"]
	out = common.engine_dir("chatterbox_turbo")

	device = _pick_device()
	try:
		model = _load(device)
	except Exception as e:  # noqa: BLE001
		print(f"[turbo] {device} load failed ({e}); retrying cpu", file=sys.stderr)
		device = "cpu"
		try:
			model = _load(device)
		except Exception as e2:  # noqa: BLE001
			common.write_meta("chatterbox_turbo", device="n/a", model="Chatterbox-Turbo",
			                  entries=[], note=f"load failed: {e2}")
			return 0

	entries: list[dict] = []
	for line in data["lines"]:
		ref = str(common.HERE / chars[line["char"]])
		fname = f"{line['char']}-{line['id']}.wav"
		exag = line.get("exaggeration", 0.5)
		e = {"id": f"{line['char']}-{line['id']}", "mood": line["char"], "file": fname,
		     "text": line["text"], "exaggeration": exag, "ok": False}
		try:
			with common.Timer() as t:
				wav = model.generate(line["text"], audio_prompt_path=ref,
				                     exaggeration=exag, temperature=0.8)
			torchaudio.save(str(out / fname), wav, model.sr)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
			print(f"[turbo] {fname}: {ex}", file=sys.stderr)
		entries.append(e)

	common.write_meta("chatterbox_turbo", device=device, model="Chatterbox-Turbo (ResembleAI)",
	                  entries=entries, note="Inline tags [gasp]/[laugh]/[sigh]/[cough]; per-line exaggeration.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
