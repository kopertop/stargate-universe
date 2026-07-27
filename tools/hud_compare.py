#!/usr/bin/env python3
"""hud_compare.py — non-subjective HUD-vs-concept similarity score.

WHY THIS EXISTS
---------------
We are re-skinning the in-game HUD to match a *concept screenshot from a
DIFFERENT game* (a WoW-style fantasy UI). A whole-frame pixel diff is useless:
the 3D worlds differ entirely, so most pixels will never match and the signal is
pure noise (see memory `render-diff-baseline-poisoning`).

Instead we compare **HUD palette signatures per screen region**. For each named
region (player frame top-left, minimap top-right, chat bottom-left, action bar
bottom-center, ...) we measure the *fraction* of pixels that fall into the HUD
palette buckets — gold, HP-green, oxygen-cyan, panel-dark, bright — in BOTH the
reference concept and our candidate render. The per-region score is
`100 * (1 - mean_abs_difference_of_those_fractions)`. The world center is never
scored.

This is deterministic and reproducible. The ABSOLUTE score is not meaningful
(our content differs); the DELTA between two candidate captures is — that is
exactly the signal a Karpathy commit-if-closer / revert-if-not loop needs.

USAGE
-----
    python3 tools/hud_compare.py --reference docs/hud-redesign/wow-hud-reference.png \
                                 --candidate <capture.png> [--json out.json] \
                                 [--composite side_by_side.png] [--spec regions.json]

Exit code is always 0 on success; the score is printed as `SCORE=<float>` (so a
shell loop can grep it) plus a per-region breakdown table.

DEPENDENCIES: Pillow + numpy. (`python3 -c "import PIL, numpy"` to check.)
"""

import argparse
import json
import sys

try:
	import numpy as np
	from PIL import Image, ImageDraw
except ImportError as exc:  # pragma: no cover - environment guard
	sys.stderr.write(
		"hud_compare needs Pillow + numpy: pip install pillow numpy\n(%s)\n" % exc
	)
	sys.exit(2)


# Normalized (0..1) regions covering each HUD element in the concept image.
# x0,y0 = top-left, x1,y1 = bottom-right. Tuned to the WoW reference. The world
# center is intentionally NOT a region — we never score it. Weight biases the
# total toward the elements we care most about getting right.
DEFAULT_REGIONS = {
	"player_frame":  {"box": [0.000, 0.000, 0.185, 0.090], "weight": 1.4},
	"target_frame":  {"box": [0.135, 0.000, 0.280, 0.075], "weight": 1.0},
	"minimap":       {"box": [0.870, 0.000, 1.000, 0.205], "weight": 1.2},
	"quest_tracker": {"box": [0.850, 0.205, 1.000, 0.345], "weight": 1.0},
	"chat_log":      {"box": [0.000, 0.825, 0.190, 1.000], "weight": 1.0},
	"action_bar":    {"box": [0.315, 0.930, 0.635, 1.000], "weight": 1.2},
	"menu_col":      {"box": [0.620, 0.840, 0.670, 1.000], "weight": 0.6},
}

# Palette buckets, expressed as HSV predicates. Hue is in degrees [0,360).
# These describe the *concept's* HUD colors; our gold-skin target matches them.
PALETTE = {
	"gold":   {"h": (33, 56),  "s_min": 0.30, "v_min": 0.40},
	"green":  {"h": (85, 155), "s_min": 0.35, "v_min": 0.30},
	"cyan":   {"h": (165, 210),"s_min": 0.30, "v_min": 0.35},
	"bright": {"h": None,      "s_max": 0.25, "v_min": 0.80},  # near-white text/markers
	"dark":   {"h": None,      "s_max": 1.01, "v_max": 0.22},  # panel fill / outline
}


def rgb_to_hsv(arr):
	"""arr: HxWx3 float in [0,1] -> (h[0,360), s[0,1], v[0,1])."""
	r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
	mx = np.max(arr, axis=-1)
	mn = np.min(arr, axis=-1)
	df = mx - mn
	v = mx
	s = np.where(mx <= 1e-6, 0.0, df / np.maximum(mx, 1e-6))
	h = np.zeros_like(mx)
	mask = df > 1e-6
	# Per-channel max determines the hue sector.
	rmax = (mx == r) & mask
	gmax = (mx == g) & mask
	bmax = (mx == b) & mask
	h[rmax] = (60 * ((g - b)[rmax] / df[rmax]) + 360) % 360
	h[gmax] = (60 * ((b - r)[gmax] / df[gmax]) + 120) % 360
	h[bmax] = (60 * ((r - g)[bmax] / df[bmax]) + 240) % 360
	return h, s, v


def bucket_fraction(h, s, v, spec):
	"""Fraction of pixels in (h,s,v) matching a PALETTE bucket spec."""
	cond = np.ones(h.shape, dtype=bool)
	if spec.get("h") is not None:
		lo, hi = spec["h"]
		cond &= (h >= lo) & (h <= hi)
	if "s_min" in spec:
		cond &= s >= spec["s_min"]
	if "s_max" in spec:
		cond &= s <= spec["s_max"]
	if "v_min" in spec:
		cond &= v >= spec["v_min"]
	if "v_max" in spec:
		cond &= v <= spec["v_max"]
	return float(np.count_nonzero(cond)) / float(h.size) if h.size else 0.0


def region_signature(img_arr, box):
	"""Palette-fraction vector for one normalized region of an image array."""
	hh, ww = img_arr.shape[0], img_arr.shape[1]
	x0 = int(round(box[0] * ww)); x1 = int(round(box[2] * ww))
	y0 = int(round(box[1] * hh)); y1 = int(round(box[3] * hh))
	x0, x1 = max(0, min(x0, ww)), max(0, min(x1, ww))
	y0, y1 = max(0, min(y0, hh)), max(0, min(y1, hh))
	if x1 <= x0 or y1 <= y0:
		return {k: 0.0 for k in PALETTE}
	crop = img_arr[y0:y1, x0:x1, :3]
	h, s, v = rgb_to_hsv(crop)
	return {name: bucket_fraction(h, s, v, spec) for name, spec in PALETTE.items()}


def load_rgb(path):
	img = Image.open(path).convert("RGB")
	return np.asarray(img, dtype=np.float32) / 255.0


def score_region(ref_sig, cand_sig):
	"""0..100 similarity of two palette-fraction vectors (1 - mean L1)."""
	keys = list(PALETTE.keys())
	diff = sum(abs(ref_sig[k] - cand_sig[k]) for k in keys) / len(keys)
	return max(0.0, 100.0 * (1.0 - diff))


def main():
	ap = argparse.ArgumentParser(description="HUD-vs-concept palette similarity")
	ap.add_argument("--reference", required=True, help="concept screenshot")
	ap.add_argument("--candidate", required=True, help="our render to score")
	ap.add_argument("--spec", help="optional regions JSON (overrides defaults)")
	ap.add_argument("--json", help="write full result JSON here")
	ap.add_argument("--composite", help="write side-by-side w/ region boxes here")
	args = ap.parse_args()

	regions = DEFAULT_REGIONS
	if args.spec:
		with open(args.spec) as fh:
			regions = json.load(fh)

	ref = load_rgb(args.reference)
	cand = load_rgb(args.candidate)

	rows = []
	total_w = 0.0
	weighted = 0.0
	for name, cfg in regions.items():
		box = cfg["box"]
		w = float(cfg.get("weight", 1.0))
		ref_sig = region_signature(ref, box)
		cand_sig = region_signature(cand, box)
		s = score_region(ref_sig, cand_sig)
		rows.append((name, s, w, ref_sig, cand_sig))
		weighted += s * w
		total_w += w

	total = weighted / total_w if total_w else 0.0

	print("region          score   weight  | gold  grn  cyan brgt dark  (ref -> cand)")
	print("-" * 78)
	for name, s, w, rsig, csig in rows:
		def fmt(sig):
			return " ".join("%0.2f" % sig[k] for k in PALETTE)
		print("%-15s %6.2f  %5.1f   | ref %s\n%-30s| cand %s"
		      % (name, s, w, fmt(rsig), "", fmt(csig)))
	print("-" * 78)
	print("SCORE=%.4f" % total)

	if args.json:
		out = {
			"total": total,
			"regions": {
				name: {"score": s, "weight": w, "reference": rsig, "candidate": csig}
				for name, s, w, rsig, csig in rows
			},
		}
		with open(args.json, "w") as fh:
			json.dump(out, fh, indent=2)

	if args.composite:
		_write_composite(args.reference, args.candidate, regions, args.composite)

	return 0


def _write_composite(ref_path, cand_path, regions, out_path):
	"""Side-by-side concept|candidate with region boxes drawn, for eyeballing."""
	ref = Image.open(ref_path).convert("RGB")
	cand = Image.open(cand_path).convert("RGB")
	h = 540
	def scaled(img):
		w = int(img.width * (h / img.height))
		return img.resize((w, h))
	ref_s, cand_s = scaled(ref), scaled(cand)
	comp = Image.new("RGB", (ref_s.width + cand_s.width + 12, h), (20, 20, 24))
	comp.paste(ref_s, (0, 0))
	comp.paste(cand_s, (ref_s.width + 12, 0))
	draw = ImageDraw.Draw(comp)
	for panel, ox in ((ref_s, 0), (cand_s, ref_s.width + 12)):
		for name, cfg in regions.items():
			b = cfg["box"]
			draw.rectangle(
				[ox + b[0] * panel.width, b[1] * h, ox + b[2] * panel.width, b[3] * h],
				outline=(255, 210, 90), width=2,
			)
	comp.save(out_path)


if __name__ == "__main__":
	sys.exit(main())
