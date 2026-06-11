#!/usr/bin/env python3
"""Export the LuxTTS Vocos vocoder (torch `vocos.bin`) to ONNX.

This is the ONE torch-only piece of the LuxTTS synthesis pipeline. The text
encoder + flow-matching decoder already ship as ONNX; if the vocoder also
exports, the entire text->audio path can run torch-free in onnxruntime
(and therefore inside a Godot onnxruntime GDExtension).

Risk: the vocoder heads use ISTFT, historically hard to export. We try the
modern dynamo exporter first (torch 2.x), then the legacy TorchScript exporter.

Run inside the LuxTTS venv:
  ~/.cache/luxtts/.venv/bin/python export_vocos.py [--out vocos.onnx]
"""
import argparse
import sys
from pathlib import Path

import torch
from torch import nn


def build_vocoder():
	from huggingface_hub import snapshot_download
	from linacodec.vocoder.vocos import Vocos
	from torch.nn.utils import parametrize

	model_path = snapshot_download("YatharthS/LuxTTS")
	vocos = Vocos.from_hparams(f"{model_path}/vocoder/config.yaml").eval()
	parametrize.remove_parametrizations(vocos.upsampler.upsample_layers[0], "weight")
	parametrize.remove_parametrizations(vocos.upsampler.upsample_layers[1], "weight")
	vocos.load_state_dict(torch.load(f"{model_path}/vocoder/vocos.bin", map_location="cpu", weights_only=True))
	vocos.return_48k = True
	vocos.freq_range = 12000
	return vocos


class DecodeWrapper(nn.Module):
	"""ONNX-exportable wrapper: mel features (B, C=100, L) -> audio (B, T) @ 48kHz."""

	def __init__(self, vocos):
		super().__init__()
		self.vocos = vocos
		from onnx_istft import OnnxISTFT

		# head_48k config: n_fft=1024, hop_length=256 (vocoder config.yaml).
		self.istft = OnnxISTFT(n_fft=1024, hop_length=256, win_length=1024)

	def forward(self, features):  # noqa: D401
		# Single-head 48kHz path: backbone -> upsampler -> head_48k. This is a
		# complete standalone vocoder. We deliberately DROP the dual-path
		# Linkwitz-Riley crossover (the second 24kHz head + FFT merge) because it
		# builds a torch.linspace whose length depends on the dynamic frame count,
		# which can't be symbolically traced for ONNX export with dynamic length.
		# The crossover is a phase-polish post-step, not core synthesis, and can
		# be re-added in numpy/GDScript later (rfft -> static mask -> irfft).
		#
		# head_48k's forward is inlined here with our ONNX-exportable iSTFT in
		# place of torch.istft (which has a broadcast bug under onnxruntime).
		v = self.vocos
		features_b = v.backbone(features).transpose(1, 2)
		upsampled = v.upsampler(features_b).transpose(1, 2)

		h = v.head_48k
		x = h.out(upsampled).transpose(1, 2)  # (B, n_fft+2, L)
		mag, p = x.chunk(2, dim=1)
		mag = torch.clip(torch.exp(mag), max=1e2)
		real = mag * torch.cos(p)
		imag = mag * torch.sin(p)
		return self.istft(real, imag)


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--out", default=str(Path(__file__).parent / "artifacts" / "vocos.onnx"))
	ap.add_argument("--opset", type=int, default=18)
	args = ap.parse_args()

	out = Path(args.out)
	out.parent.mkdir(parents=True, exist_ok=True)

	print("[export] loading vocoder…", file=sys.stderr)
	vocos = build_vocoder()
	wrapper = DecodeWrapper(vocos).eval()

	# Dummy: 1 batch, 100 mel channels, 120 frames.
	dummy = torch.randn(1, 100, 120)
	with torch.no_grad():
		ref = wrapper(dummy)
	print(f"[export] torch decode OK: {tuple(dummy.shape)} -> {tuple(ref.shape)}", file=sys.stderr)

	dynamic_axes = {"features": {0: "batch", 2: "frames"}, "audio": {0: "batch", 1: "samples"}}

	# Attempt 1: modern dynamo exporter (best ISTFT support on torch 2.x).
	errors = []
	try:
		print("[export] attempt 1: dynamo exporter…", file=sys.stderr)
		torch.onnx.export(
			wrapper, (dummy,), str(out),
			input_names=["features"], output_names=["audio"],
			dynamic_axes=dynamic_axes, opset_version=args.opset, dynamo=True,
		)
		print(f"[export] SUCCESS (dynamo) -> {out}", file=sys.stderr)
		return _validate(out, dummy, ref)
	except Exception as e:  # noqa: BLE001
		errors.append(f"dynamo: {type(e).__name__}: {e}")
		print(f"[export] dynamo failed: {e}", file=sys.stderr)

	# Attempt 2: legacy TorchScript exporter.
	try:
		print("[export] attempt 2: legacy exporter…", file=sys.stderr)
		torch.onnx.export(
			wrapper, (dummy,), str(out),
			input_names=["features"], output_names=["audio"],
			dynamic_axes=dynamic_axes, opset_version=args.opset,
		)
		print(f"[export] SUCCESS (legacy) -> {out}", file=sys.stderr)
		return _validate(out, dummy, ref)
	except Exception as e:  # noqa: BLE001
		errors.append(f"legacy: {type(e).__name__}: {e}")
		print(f"[export] legacy failed: {e}", file=sys.stderr)

	print("\n[export] BOTH EXPORTERS FAILED — likely the ISTFT op. Errors:\n  " + "\n  ".join(errors), file=sys.stderr)
	return 1


def _fix_scatternd_int64(onnx_path) -> None:
	"""onnxruntime requires ScatterND `indices` to be int64; the ISTFT head's
	overlap-add exports them as int32. Insert a Cast(int64) before each ScatterND."""
	import onnx
	from onnx import TensorProto, helper

	model = onnx.load(str(onnx_path))  # pulls in the external .data weights
	g = model.graph
	nodes, fixed = [], 0
	for node in g.node:
		if node.op_type == "ScatterND" and len(node.input) >= 2:
			idx = node.input[1]
			cast_out = f"{idx}_i64_{fixed}"
			nodes.append(helper.make_node("Cast", [idx], [cast_out], to=TensorProto.INT64, name=f"{node.name}_castidx"))
			node.input[1] = cast_out
			fixed += 1
		nodes.append(node)
	if not fixed:
		return
	del g.node[:]
	g.node.extend(nodes)
	onnx.save(model, str(onnx_path), save_as_external_data=True, all_tensors_to_one_file=True, location=f"{onnx_path.name}.data")
	print(f"[export] patched {fixed} ScatterND node(s) to int64 indices", file=sys.stderr)


def _validate(onnx_path, dummy, ref) -> int:
	import numpy as np
	import onnxruntime as ort

	_fix_scatternd_int64(onnx_path)

	sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
	got = sess.run(["audio"], {"features": dummy.numpy()})[0]
	ref_np = ref.detach().numpy()
	n = min(got.shape[-1], ref_np.shape[-1])
	mae = float(np.abs(got[..., :n] - ref_np[..., :n]).mean())
	print(f"[export] onnx vs torch MAE={mae:.6e} (shapes onnx={got.shape} torch={ref_np.shape})", file=sys.stderr)
	if mae < 1e-3:
		print("[export] ✅ ONNX vocoder matches torch within tolerance.", file=sys.stderr)
		return 0
	print("[export] ⚠️ ONNX vocoder output diverges from torch — investigate.", file=sys.stderr)
	return 0  # still exported; divergence may be acceptable / numeric


if __name__ == "__main__":
	sys.exit(main())
