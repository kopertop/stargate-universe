#!/usr/bin/env python3
"""ONNX-exportable inverse STFT.

torch.istft does not lower to ONNX (it triggers a broadcast bug in the
decomposition). This module reimplements center-padded iSTFT with hann window
using only export-friendly ops:

  - irfft  -> a fixed real MatMul against precomputed cos/sin DFT bases
  - overlap-add -> ConvTranspose1d with a fixed identity kernel
  - NOLA normalization -> same overlap-add applied to the squared window

Matches `vocos.spectral_ops.ISTFT(padding="center")` numerically.
"""
import torch
from torch import nn


class OnnxISTFT(nn.Module):
	def __init__(self, n_fft: int, hop_length: int, win_length: int):
		super().__init__()
		self.n_fft = n_fft
		self.hop_length = hop_length
		self.pad = n_fft // 2  # center padding trim

		n = n_fft
		N = n_fft // 2 + 1
		window = torch.hann_window(win_length)

		# irfft bases: time[j] = sum_k ( Sr[k]*cos_b[j,k] + Si[k]*sin_b[j,k] )
		# with Hermitian doubling (k=0 and Nyquist counted once, the rest twice).
		k = torch.arange(N).float()
		j = torch.arange(n).float()
		ang = 2.0 * torch.pi * torch.outer(j, k) / n  # (n, N)
		scale = torch.full((N,), 2.0 / n)
		scale[0] = 1.0 / n
		if n % 2 == 0:
			scale[-1] = 1.0 / n
		cos_b = (torch.cos(ang) * scale).float()   # (n, N)
		sin_b = (-torch.sin(ang) * scale).float()  # (n, N)

		# Apply synthesis window into the basis so MatMul output is already windowed.
		self.register_buffer("cos_b", (cos_b * window.unsqueeze(1)))  # (n, N)
		self.register_buffer("sin_b", (sin_b * window.unsqueeze(1)))  # (n, N)
		self.register_buffer("window_sq", (window ** 2).view(1, n, 1))  # (1, n, 1)

		# Identity kernel for overlap-add via ConvTranspose1d: (in=n, out=1, k=n).
		eye = torch.eye(n).unsqueeze(1)  # (n, 1, n)
		self.register_buffer("ola_kernel", eye)

	def forward(self, spec_real: torch.Tensor, spec_imag: torch.Tensor) -> torch.Tensor:
		# spec_*: (B, N, T). Per-frame windowed time signal -> (B, n, T).
		# frames[b, j, t] = sum_k cos_b[j,k]*Sr[b,k,t] + sin_b[j,k]*Si[b,k,t]
		frames = torch.einsum("jk,bkt->bjt", self.cos_b, spec_real) + torch.einsum(
			"jk,bkt->bjt", self.sin_b, spec_imag
		)
		# Overlap-add: ConvTranspose1d places frame j at offset j within each window,
		# stepping by hop -> output[b, 0, t*hop + j] += frames[b, j, t].
		num = torch.nn.functional.conv_transpose1d(frames, self.ola_kernel, stride=self.hop_length)

		# NOLA normalization: overlap-add of the squared window over T frames.
		T = frames.shape[-1]
		win_frames = self.window_sq.expand(frames.shape[0], -1, T)
		den = torch.nn.functional.conv_transpose1d(win_frames, self.ola_kernel, stride=self.hop_length)
		out = num / torch.clamp(den, min=1e-11)
		out = out.squeeze(1)  # (B, L_full)
		return out[:, self.pad : out.shape[-1] - self.pad]  # trim center padding
