#!/usr/bin/env python3
"""Base-Chatterbox PANIC render for every game voice. Mints a calm timbre reference per
voice from the running LuxTTS sidecar (if not already in refs/), then clones it through
base Chatterbox with high `exaggeration` + low cfg + CAPS to produce a yelling take.

These double as PANIC REFERENCE CLIPS: clone from <voice>_panic.wav in any engine
(including Turbo, which can't crank intensity itself but inherits the reference's energy)
to get a panicked delivery for that character.

Output -> out/panic_voices/<voice>.wav  (+ meta.json)

Run: uv run --python-preference only-managed --python 3.12 \\
       --with chatterbox-tts --with torchaudio --with torchvision python gen_panic_voices.py
"""
from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request

import common

SIDECAR = "http://127.0.0.1:8765"
SKIP = {"default"}  # generic fallback, not a character
NEUTRAL = ("This is a calm reference line, recorded so the voice can be cloned cleanly "
           "with a steady and even tone.")
PANIC_TEXT = "INCOMING! Everybody DOWN — MOVE, MOVE, MOVE!"
EXAG, CFG, TEMP = 1.8, 0.2, 0.9


def _voices() -> list[str]:
	with urllib.request.urlopen(f"{SIDECAR}/health", timeout=5) as r:
		vs = json.loads(r.read()).get("voices", [])
	return [v for v in vs if v not in SKIP]


def _ensure_ref(voice: str) -> str:
	dst = common.HERE / "refs" / f"{voice}.wav"
	if dst.is_file():
		return str(dst)
	url = f"{SIDECAR}/synthesize?voice={voice}&text={urllib.parse.quote(NEUTRAL)}&seed=7"
	with urllib.request.urlopen(url, timeout=60) as r:
		dst.write_bytes(r.read())
	print(f"  minted ref {dst.name}")
	return str(dst)


def _shim():
	import perth
	if getattr(perth, "PerthImplicitWatermarker", None) is None:
		class _N:
			def apply_watermark(self, wav, sample_rate=None, **k): return wav
			def get_watermark(self, *a, **k): return None
		perth.PerthImplicitWatermarker = _N


def main() -> int:
	import torch
	import torchaudio

	try:
		voices = _voices()
	except Exception as e:  # noqa: BLE001
		print(f"[panic_voices] sidecar offline ({e}) — start tools/tts-onnx-poc/run_server.sh", file=sys.stderr)
		return 1
	print(f"[panic_voices] {len(voices)} voices: {voices}")

	out = common.engine_dir("panic_voices")
	dev = "mps" if torch.backends.mps.is_available() else "cpu"
	_shim()
	_orig = torch.load
	torch.load = lambda *a, **k: _orig(*a, **{**k, "map_location": torch.device(dev)})
	from chatterbox.tts import ChatterboxTTS
	model = ChatterboxTTS.from_pretrained(device=dev)

	entries = []
	for v in voices:
		e = {"id": v, "mood": "panic", "file": f"{v}.wav", "text": PANIC_TEXT,
		     "exaggeration": EXAG, "ok": False}
		try:
			ref = _ensure_ref(v)
			with common.Timer() as t:
				wav = model.generate(PANIC_TEXT, audio_prompt_path=ref,
				                     exaggeration=EXAG, cfg_weight=CFG, temperature=TEMP)
			torchaudio.save(str(out / f"{v}.wav"), wav, model.sr)
			e["ok"] = True
			e["gen_seconds"] = round(t.seconds, 2)
			print(f"[panic_voices] {v} done ({e['gen_seconds']}s)")
		except Exception as ex:  # noqa: BLE001
			e["error"] = str(ex)
			print(f"[panic_voices] {v}: {ex}", file=sys.stderr)
		entries.append(e)

	torch.load = _orig
	common.write_meta("panic_voices", device=dev, model="base Chatterbox (panic preset)",
	                  entries=entries, note=f"exaggeration={EXAG}, cfg={CFG}, CAPS yelling line. Doubles as panic ref clips.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
