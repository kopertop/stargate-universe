#!/usr/bin/env python3
"""Tokenize text -> LuxTTS token IDs at dev time, so the runtime never needs the
phonemizer (piper_phonemize/espeak) or the EmiliaTokenizer.

The tokenizer is the one piece that's awkward to port to the engine (it does
grapheme->phoneme via espeak). Pre-tokenizing authored dialogue sidesteps that
entirely: store the int token sequence alongside each line.

  ~/.cache/luxtts/.venv/bin/python precompute_tokens.py --text "Hello there." [--out tokens.json]
"""
import argparse
import json
import sys
from pathlib import Path


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--text", required=True)
	ap.add_argument("--out", default=None, help="Write JSON list of token ids; else print to stdout.")
	args = ap.parse_args()

	from huggingface_hub import snapshot_download
	from zipvoice.tokenizer.tokenizer import EmiliaTokenizer

	model_path = snapshot_download("YatharthS/LuxTTS")
	tok = EmiliaTokenizer(token_file=f"{model_path}/tokens.txt")
	token_ids = tok.texts_to_token_ids([args.text])  # -> [[int, ...]]

	payload = {"text": args.text, "tokens": token_ids}
	if args.out:
		Path(args.out).write_text(json.dumps(payload))
		print(f"[tokens] {len(token_ids[0])} ids -> {args.out}", file=sys.stderr)
	else:
		print(json.dumps(payload))
	return 0


if __name__ == "__main__":
	sys.exit(main())
