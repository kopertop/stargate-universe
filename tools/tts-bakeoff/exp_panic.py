#!/usr/bin/env python3
"""Focused panic/yelling A/B on TJ's triage line. Isolates which local lever actually
delivers shouting:
  - turbo_tags : Chatterbox-Turbo with the user's directorial tags verbatim
                 ([panicked]/[loud]/[yelling]/[louder]) — tests if Turbo honors them
  - turbo_caps : Turbo with CAPS + supported [gasp] only + punctuation
  - base_e16   : base Chatterbox, exaggeration 1.6, low cfg (urgent), CAPS
  - base_e20   : base Chatterbox, exaggeration 2.0 (max), low cfg, CAPS

(IndexTTS-2 panic is run separately — too slow to bundle.)
All clone TJ from refs/tj.wav. Output -> out/panic_test/.

Run: uv run --python-preference only-managed --python 3.12 \\
       --with chatterbox-tts --with torchaudio --with torchvision python exp_panic.py
"""
from __future__ import annotations

import sys

import common

REF = str(common.HERE / "refs" / "tj.wav")

# Directorial-tag style the user asked about (Turbo's real trained tag set is only
# paralinguistic sounds like [gasp]/[laugh], so these are expected to misfire):
TEXT_DIRECTORIAL = "[panicked] [loud] STAY WITH ME! [yelling] I need a hand over here, [louder] NOW!"
# CAPS + punctuation + one supported paralinguistic tag:
TEXT_CAPS = "[gasp] STAY WITH ME! I need a hand over here — NOW!"


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
	out = common.engine_dir("panic_test")
	dev = "mps" if torch.backends.mps.is_available() else "cpu"
	_shim()

	_orig = torch.load
	torch.load = lambda *a, **k: _orig(*a, **{**k, "map_location": torch.device(dev)})

	results = []

	# ---- base Chatterbox: the exaggeration knob is the yelling lever ----
	from chatterbox.tts import ChatterboxTTS
	base = ChatterboxTTS.from_pretrained(device=dev)
	for tag, exag in (("base_e16", 1.6), ("base_e20", 2.0)):
		wav = base.generate(TEXT_CAPS.replace("[gasp] ", ""), audio_prompt_path=REF,
		                    exaggeration=exag, cfg_weight=0.2, temperature=0.9)
		torchaudio.save(str(out / f"tj-triage-{tag}.wav"), wav, base.sr)
		results.append(tag)
		print(f"[panic] {tag} done")
	del base

	# ---- Turbo: tags only; exaggeration ignored ----
	from chatterbox.tts_turbo import ChatterboxTurboTTS
	turbo = ChatterboxTurboTTS.from_pretrained(device=dev)
	for tag, text in (("turbo_tags", TEXT_DIRECTORIAL), ("turbo_caps", TEXT_CAPS)):
		wav = turbo.generate(text, audio_prompt_path=REF, temperature=0.9)
		torchaudio.save(str(out / f"tj-triage-{tag}.wav"), wav, turbo.sr)
		results.append(tag)
		print(f"[panic] {tag} done")

	torch.load = _orig
	print("panic_test variants:", results)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
