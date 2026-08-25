#!/usr/bin/env python3
"""Resident LuxTTS sidecar — keeps the model warm and synthesizes dynamic lines
on demand for the game engine.

The engine (Godot) POSTs/GETs text + a pre-computed voice name; the server
tokenizes arbitrary text (real espeak phonemizer) and returns 48kHz WAV bytes.
Voices are the committed .voice.pt embeddings — no new voices are created at
runtime, only reused.

  ~/.cache/luxtts/.venv/bin/python tts_server.py [--host 127.0.0.1] [--port 8765] \
      [--voices-dir DIR] [--device auto|mps|cuda|cpu]

Endpoints:
  GET  /health                                  -> {"status":"ok","voices":[...]}
  GET  /synthesize?voice=rush&text=...&seed=7   -> audio/wav (48kHz)
"""
import argparse
import io
import json
import sys
import warnings
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

warnings.filterwarnings("ignore")

TTS = None          # loaded LuxTTS model (resident)
VOICES_DIR = None   # Path to .voice.pt embeddings
_CACHE = {}         # name -> encode_dict (on device)


def load_voice(name: str):
	import torch

	if name in _CACHE:
		return _CACHE[name]
	pt = VOICES_DIR / f"{name}.voice.pt"
	if not pt.is_file():
		return None
	enc = torch.load(pt, map_location="cpu", weights_only=True)
	enc = {k: (v.to(TTS.device) if torch.is_tensor(v) else v) for k, v in enc.items()}
	_CACHE[name] = enc
	return enc


def synthesize(voice: str, text: str, seed: int | None) -> bytes:
	import soundfile as sf
	import torch

	enc = load_voice(voice)
	if enc is None:
		raise KeyError(voice)
	if seed is not None:
		torch.manual_seed(seed)
	wav = TTS.generate_speech(text, enc)  # (1, samples) @ 48kHz
	data = wav.squeeze(0).cpu().numpy()
	buf = io.BytesIO()
	sf.write(buf, data, 48000, format="WAV")
	return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
	def log_message(self, *a):  # quiet
		pass

	def _json(self, code, obj):
		body = json.dumps(obj).encode()
		self.send_response(code)
		self.send_header("Content-Type", "application/json")
		self.send_header("Content-Length", str(len(body)))
		self.end_headers()
		self.wfile.write(body)

	def do_GET(self):
		u = urlparse(self.path)
		if u.path == "/health":
			voices = sorted(p.stem.replace(".voice", "") for p in VOICES_DIR.glob("*.voice.pt"))
			return self._json(200, {"status": "ok", "device": TTS.device, "voices": voices})
		if u.path == "/synthesize":
			q = parse_qs(u.query)
			voice = (q.get("voice") or [""])[0]
			text = (q.get("text") or [""])[0]
			seed = int(q["seed"][0]) if "seed" in q else None
			if not voice or not text:
				return self._json(400, {"error": "voice and text are required"})
			try:
				wav = synthesize(voice, text, seed)
			except KeyError:
				return self._json(404, {"error": f"unknown voice '{voice}'"})
			except Exception as e:  # noqa: BLE001
				return self._json(500, {"error": str(e)})
			self.send_response(200)
			self.send_header("Content-Type", "audio/wav")
			self.send_header("Content-Length", str(len(wav)))
			self.end_headers()
			self.wfile.write(wav)
			return
		self._json(404, {"error": "not found"})


def main() -> int:
	global TTS, VOICES_DIR
	ap = argparse.ArgumentParser()
	ap.add_argument("--host", default="127.0.0.1")
	ap.add_argument("--port", type=int, default=8765)
	ap.add_argument("--voices-dir", default=str(Path.home() / ".cache/luxtts/voices"))
	ap.add_argument("--device", default="cuda", help="auto-falls back cuda->mps->cpu")
	args = ap.parse_args()

	VOICES_DIR = Path(args.voices_dir)
	from zipvoice.luxvoice import LuxTTS

	print(f"[tts-server] loading model (device={args.device})…", file=sys.stderr)
	TTS = LuxTTS(device=args.device)
	n = len(list(VOICES_DIR.glob("*.voice.pt")))
	print(f"[tts-server] ready on http://{args.host}:{args.port}  ({n} voices in {VOICES_DIR})", file=sys.stderr)
	ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
	return 0


if __name__ == "__main__":
	sys.exit(main())
