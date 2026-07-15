#!/usr/bin/env python3
"""Batch-enroll many reference clips into LuxTTS voice embeddings in one model load.

  ~/.cache/luxtts/.venv/bin/python batch_enroll.py --src <dir-of-wavs> [--voices-dir DIR] [--duration 5]

Writes <voices-dir>/<name>.voice.pt for each audio file (name = filename stem).
Much faster than calling the /tts skill per voice (model loads once).
"""
import argparse
import os
import sys
from pathlib import Path

AUDIO_EXTS = {".wav", ".flac", ".aiff", ".aif", ".mp3", ".m4a", ".ogg"}


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--src", required=True, help="Directory of reference clips.")
	ap.add_argument("--voices-dir", default=os.environ.get("LUXTTS_VOICES", str(Path.home() / ".cache/luxtts/voices")))
	ap.add_argument("--duration", type=float, default=5.0, help="Seconds of each clip to encode.")
	ap.add_argument("--device", default="cuda", help="cuda|mps|cpu (auto-falls back).")
	args = ap.parse_args()

	clips = sorted(p for p in Path(args.src).iterdir() if p.suffix.lower() in AUDIO_EXTS)
	if not clips:
		print(f"ERROR: no audio files in {args.src}", file=sys.stderr)
		return 2

	import torch
	from zipvoice.luxvoice import LuxTTS

	print(f"[batch] loading model…", file=sys.stderr)
	tts = LuxTTS(device=args.device)
	out_dir = Path(args.voices_dir)
	out_dir.mkdir(parents=True, exist_ok=True)

	ok, fail = 0, 0
	for clip in clips:
		name = clip.stem
		try:
			enc = tts.encode_prompt(str(clip), duration=args.duration)
			enc_cpu = {k: (v.cpu() if torch.is_tensor(v) else v) for k, v in enc.items()}
			out = out_dir / f"{name}.voice.pt"
			torch.save(enc_cpu, out)
			print(f"[batch] ✅ {name:12s} -> {out.name} ({out.stat().st_size/1024:.0f} KB)", file=sys.stderr)
			ok += 1
		except Exception as e:  # noqa: BLE001
			print(f"[batch] ❌ {name:12s}: {e}", file=sys.stderr)
			fail += 1

	print(f"[batch] done: {ok} enrolled, {fail} failed -> {out_dir}", file=sys.stderr)
	return 0 if fail == 0 else 1


if __name__ == "__main__":
	sys.exit(main())
