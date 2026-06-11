#!/usr/bin/env python3
"""Convert a LuxTTS voice embedding (.voice.pt, torch) into a portable .npz
(numpy) that the torch-free runtime can load without torch.

  ~/.cache/luxtts/.venv/bin/python export_voice.py --in voices/eli.voice.pt --out artifacts/eli.npz
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import torch


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--in", dest="inp", required=True, help="Path to <name>.voice.pt")
	ap.add_argument("--out", required=True, help="Path to write <name>.npz")
	args = ap.parse_args()

	enc = torch.load(args.inp, map_location="cpu", weights_only=True)

	# encode_dict: prompt_tokens (list[list[int]]), prompt_features_lens (tensor),
	#              prompt_features (tensor B,L,C), prompt_rms (tensor/float).
	def to_np(v):
		return v.detach().cpu().numpy() if torch.is_tensor(v) else np.asarray(v)

	prompt_tokens = np.asarray(enc["prompt_tokens"], dtype=np.int64)  # (1, S)
	prompt_features = to_np(enc["prompt_features"]).astype(np.float32)  # (1, L, C)
	prompt_features_lens = to_np(enc["prompt_features_lens"]).astype(np.int64)
	prompt_rms = float(to_np(enc["prompt_rms"]))

	out = Path(args.out)
	out.parent.mkdir(parents=True, exist_ok=True)
	np.savez(
		out,
		prompt_tokens=prompt_tokens,
		prompt_features=prompt_features,
		prompt_features_lens=prompt_features_lens,
		prompt_rms=np.float32(prompt_rms),
	)
	print(f"[export-voice] {args.inp} -> {out}  (features {prompt_features.shape}, tokens {prompt_tokens.shape})", file=sys.stderr)
	print(str(out))
	return 0


if __name__ == "__main__":
	sys.exit(main())
