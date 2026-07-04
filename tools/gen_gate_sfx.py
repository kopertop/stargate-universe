"""Synthesize Stargate gate SFX (no external API needed):

  • gate_kawoosh.wav — the unstable vortex bursting outward then settling: a
    fast noise swell with a downward low-pass sweep + a deep sub thump + a long
    watery tail.
  • gate_active_hum.wav — a low, seamless energy-hum loop for the open gate.

Writes 44.1 kHz mono 16-bit WAVs into sounds/. Re-run `godot --headless --import`
after to generate the .import sidecars.
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")


def norm(x, peak=0.92):
	x = x - np.mean(x)
	m = np.max(np.abs(x)) or 1.0
	return (x / m) * peak


def lp(x, cutoff):
	cutoff = max(40.0, min(cutoff, SR / 2 - 100))
	b, a = butter(4, cutoff / (SR / 2), btype="low")
	return lfilter(b, a, x)


def kawoosh():
	dur = 3.0
	n = int(SR * dur)
	t = np.linspace(0, dur, n, endpoint=False)
	noise = np.random.randn(n)

	# Burst: hard attack ~50 ms, then a long exponential tail.
	env = np.where(t < 0.05, (t / 0.05), np.exp(-(t - 0.05) * 1.7))
	# Down-sweeping low-pass: starts bright (vortex erupts), closes to watery.
	out = np.zeros(n)
	block = 1024
	for i in range(0, n, block):
		j = min(i + block, n)
		frac = i / n
		cutoff = 9000 * (1 - frac) ** 2 + 350
		out[i:j] = lp(noise[i:j], cutoff)[: j - i]
	out *= env

	# Deep sub "whump" of the puddle forming.
	sub = np.sin(2 * np.pi * (60 * np.exp(-t * 2.0) + 35) * t) * np.exp(-t * 3.0)
	# Watery shimmer tail (ring-y resonance) after the burst.
	shimmer = lp(np.random.randn(n), 1200) * np.exp(-(t) * 1.1) * 0.4
	mix = norm(out * 1.0 + sub * 0.8 + shimmer * 0.5)
	# Gentle fade-out so it doesn't click.
	fade = np.minimum(1.0, (dur - t) / 0.2)
	return norm(mix * fade)


def hum():
	dur = 4.0  # loops cleanly (integer cycles of the base tone)
	n = int(SR * dur)
	t = np.linspace(0, dur, n, endpoint=False)
	# Stack low tones + slow beating for a living energy hum.
	base = 70.0
	sig = (np.sin(2 * np.pi * base * t)
		+ 0.5 * np.sin(2 * np.pi * base * 2 * t + 0.6)
		+ 0.3 * np.sin(2 * np.pi * base * 3 * t))
	# Slow amplitude shimmer (2 full cycles over the loop → seamless).
	sig *= 1.0 + 0.18 * np.sin(2 * np.pi * (2.0 / dur) * t)
	# Airy filtered-noise bed.
	bed = lp(np.random.randn(n), 600) * 0.12
	return norm(sig + bed, peak=0.6)


def save(name, data):
	path = os.path.join(OUT, name)
	wavfile.write(path, SR, (data * 32767).astype(np.int16))
	print("WROTE", path, "%.2fs" % (len(data) / SR))


if __name__ == "__main__":
	np.random.seed(7)
	save("gate_kawoosh.wav", kawoosh())
	save("gate_active_hum.wav", hum())
	print("DONE")
