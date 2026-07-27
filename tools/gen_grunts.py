"""Synthesize short male effort GRUNTS for the cold-open arrivals (no external API).

Each crew member flung through the gate hits the deck and grunts — the human panic
layer the Demucs no-vocals ambience bed strips out. We synthesize a few varied
"unh!" bursts: a low glottal buzz (~100-130 Hz, falling) shaped by vowel formants
(an "uh"), a fast attack + quick decay envelope, and a touch of breath noise.

Writes 44.1 kHz mono 16-bit WAVs into sounds/grunt_0N.wav. Re-run
`godot --headless --import` after to generate the .import sidecars.
"""
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter
import os

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")


def norm(x, peak=0.9):
	m = np.max(np.abs(x)) or 1.0
	return (x / m) * peak


def bandpass(x, lo, hi):
	lo = max(40.0, lo)
	hi = min(hi, SR / 2 - 100)
	b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], btype="band")
	return lfilter(b, a, x)


def formant(x, f0, bw):
	"""Cheap resonator at f0 (Hz) with bandwidth bw — fakes a vowel formant."""
	return bandpass(x, f0 - bw, f0 + bw)


def grunt(seed, base_hz, dur, f1, f2):
	rng = np.random.default_rng(seed)
	n = int(SR * dur)
	t = np.linspace(0, dur, n, endpoint=False)

	# Glottal buzz: a falling pitch (grunts drop ~15% across the burst).
	pitch = base_hz * (1.0 - 0.15 * (t / dur))
	phase = 2 * np.pi * np.cumsum(pitch) / SR
	# Sum a few harmonics for a buzzy voiced source.
	src = np.zeros(n)
	for h, amp in [(1, 1.0), (2, 0.5), (3, 0.33), (4, 0.2), (5, 0.12)]:
		src += amp * np.sin(h * phase)
	# Breath/effort noise mixed under the voice.
	src += 0.35 * rng.standard_normal(n)

	# Vowel colour: two formants ("uh") summed.
	voiced = formant(src, f1, 180) + 0.7 * formant(src, f2, 220)

	# Envelope: glottal attack ~12 ms, short sustain, exponential release.
	atk = 0.012
	env = np.where(t < atk, t / atk, np.exp(-(t - atk) * (3.2 / dur)))
	out = voiced * env
	return norm(out, 0.85)


def main():
	specs = [
		# seed, base_hz, dur,  F1,  F2
		(11, 122.0, 0.34, 640, 1080),
		(23, 108.0, 0.40, 600, 1000),
		(37, 134.0, 0.30, 700, 1150),
	]
	os.makedirs(OUT, exist_ok=True)
	for i, (seed, hz, dur, f1, f2) in enumerate(specs, start=1):
		g = grunt(seed, hz, dur, f1, f2)
		path = os.path.join(OUT, "grunt_%02d.wav" % i)
		wavfile.write(path, SR, (g * 32767).astype(np.int16))
		print("wrote", os.path.relpath(path))


if __name__ == "__main__":
	main()
