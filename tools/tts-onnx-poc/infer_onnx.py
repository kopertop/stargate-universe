#!/usr/bin/env python3
"""Torch-FREE LuxTTS inference: text tokens + voice embedding -> audio.

Uses ONLY numpy + onnxruntime + soundfile. No torch, no transformers, no
librosa, no Whisper. This is the exact computation a Godot onnxruntime
GDExtension (+ GDScript for the sampler arithmetic) would perform, proving the
synthesis can run inside the engine.

Pipeline (mirrors zipvoice/onnx_modeling.py::sample, in numpy):
  text_encoder.onnx -> flow-matching sampler loop over fm_decoder.onnx
  -> mel features -> vocos.onnx -> waveform.

  python infer_onnx.py --voice artifacts/eli.npz --tokens tokens.json \
      --models <hf_snapshot_dir> --vocos artifacts/vocos.onnx --out out.wav
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import onnxruntime as ort
import soundfile as sf


def get_time_steps(num_step: int, t_shift: float) -> np.ndarray:
	t = np.linspace(0.0, 1.0, num_step + 1, dtype=np.float32)
	return (t_shift * t / (1.0 + (t_shift - 1.0) * t)).astype(np.float32)


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--voice", required=True, help="Voice embedding .npz (from export_voice.py)")
	ap.add_argument("--tokens", required=True, help="tokens.json (from precompute_tokens.py)")
	ap.add_argument("--models", required=True, help="Dir with text_encoder.onnx + fm_decoder.onnx (HF snapshot)")
	ap.add_argument("--vocos", required=True, help="vocos.onnx (from export_vocos.py)")
	ap.add_argument("--out", required=True, help="Output .wav (48kHz)")
	ap.add_argument("--num-steps", type=int, default=4)
	ap.add_argument("--guidance-scale", type=float, default=3.0)
	ap.add_argument("--speed", type=float, default=1.0)
	ap.add_argument("--t-shift", type=float, default=0.5)
	ap.add_argument("--int8", action="store_true", help="Use *_int8.onnx encoder/decoder if present.")
	ap.add_argument("--seed", type=int, default=0)
	args = ap.parse_args()

	rng = np.random.default_rng(args.seed)
	models = Path(args.models)
	suf = "_int8" if args.int8 else ""

	def sess(p):
		return ort.InferenceSession(str(p), providers=["CPUExecutionProvider"])

	text_encoder = sess(models / f"text_encoder{suf}.onnx")
	fm_decoder = sess(models / f"fm_decoder{suf}.onnx")
	vocoder = sess(args.vocos)
	feat_dim = int(fm_decoder.get_modelmeta().custom_metadata_map["feat_dim"])

	v = np.load(args.voice)
	prompt_tokens = v["prompt_tokens"].astype(np.int64)
	prompt_features = v["prompt_features"].astype(np.float32)  # (1, L, C)
	prompt_len = int(prompt_features.shape[1])
	prompt_features_len = np.array(prompt_len, dtype=np.int64)  # 0-d array (ORT needs ndarray, not scalar)
	prompt_rms = float(v["prompt_rms"])

	tokens = np.asarray(json.loads(Path(args.tokens).read_text())["tokens"], dtype=np.int64)
	speed = np.array(args.speed * 1.3, dtype=np.float32)  # repo applies 1.3x; 0-d array

	# --- text encoder ---
	te_in = [i.name for i in text_encoder.get_inputs()]
	text_condition = text_encoder.run(
		[text_encoder.get_outputs()[0].name],
		{te_in[0]: tokens, te_in[1]: prompt_tokens, te_in[2]: prompt_features_len, te_in[3]: speed},
	)[0]  # (B, num_frames, C)
	batch, num_frames, _ = text_condition.shape
	print(f"[infer] text_condition {text_condition.shape}  feat_dim={feat_dim}", file=sys.stderr)

	# --- flow-matching sampler (pure numpy) ---
	timesteps = get_time_steps(args.num_steps, args.t_shift)
	x = rng.standard_normal((batch, num_frames, feat_dim)).astype(np.float32)
	pad = num_frames - prompt_features.shape[1]
	speech_condition = np.pad(prompt_features, ((0, 0), (0, pad), (0, 0))).astype(np.float32)
	guidance = np.array(args.guidance_scale, dtype=np.float32)

	fm_in = [i.name for i in fm_decoder.get_inputs()]
	fm_out = fm_decoder.get_outputs()[0].name
	for step in range(args.num_steps):
		t_cur, t_next = float(timesteps[step]), float(timesteps[step + 1])
		vel = fm_decoder.run(
			[fm_out],
			{fm_in[0]: np.array(t_cur, dtype=np.float32), fm_in[1]: x,
			 fm_in[2]: text_condition, fm_in[3]: speech_condition, fm_in[4]: guidance},
		)[0]
		x1 = x + (1.0 - t_cur) * vel
		x0 = x - t_cur * vel
		x = x1 if step == args.num_steps - 1 else (1.0 - t_next) * x0 + t_next * x1

	x = x[:, prompt_len:, :]                                  # strip prompt portion
	mel = np.transpose(x, (0, 2, 1)).astype(np.float32) / 0.1  # (B, C, frames)
	print(f"[infer] mel {mel.shape}", file=sys.stderr)

	# --- vocoder (torch-free) ---
	vc_in = vocoder.get_inputs()[0].name
	wav = vocoder.run([vocoder.get_outputs()[0].name], {vc_in: mel})[0]  # (B, T) @ 48kHz
	wav = np.clip(wav, -1.0, 1.0)[0]
	if prompt_rms < 0.1:
		wav = wav * (prompt_rms / 0.1)

	out = Path(args.out)
	out.parent.mkdir(parents=True, exist_ok=True)
	sf.write(str(out), wav, 48000)
	print(f"[infer] wrote {out} ({len(wav) / 48000:.2f}s, peak={np.abs(wav).max():.3f}) — TORCH-FREE", file=sys.stderr)
	print(str(out))
	return 0


if __name__ == "__main__":
	sys.exit(main())
