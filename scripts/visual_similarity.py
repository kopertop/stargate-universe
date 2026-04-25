#!/usr/bin/env python3
"""
Visual Similarity Tool for Stargate Universe
=============================================

Compares game screenshots against reference images from the show using
multiple perceptual metrics. Outputs a composite similarity percentage
that can drive an iterative Karpathy-style improvement loop.

Metrics used:
  1. SSIM (Structural Similarity Index) — structural pattern matching
  2. Color histogram correlation — palette/mood similarity
  3. Edge structure similarity — architectural geometry comparison
  4. Perceptual hash distance — coarse visual fingerprint

Usage:
  python3 scripts/visual-similarity.py compare <reference> <screenshot>
  python3 scripts/visual-similarity.py batch <catalog.json> <screenshots_dir>
  python3 scripts/visual-similarity.py validate
  python3 scripts/visual-similarity.py report <catalog.json> <screenshots_dir>
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

import imagehash
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
from skimage.metrics import structural_similarity as ssim


# ─── Configuration ──────────────────────────────────────────────────────────

# Weights for composite score — tuned for "does this 3D scene look like the reference?"
# Color palette is king for SGU's distinctive dark blue-grey mood.
# Edge structure captures architectural elements (arcs, panels, ring geometry).
# SSIM captures fine structural detail but is position-sensitive.
# Perceptual hash is a coarse sanity check.
WEIGHTS = {
	"ssim": 0.25,
	"color_histogram": 0.30,
	"edge_similarity": 0.25,
	"perceptual_hash": 0.20,
}

# Standard comparison resolution — both images resized to this before comparison
# to normalize for different source resolutions
COMPARE_SIZE = (512, 384)

# Number of bins for color histograms (per channel)
HIST_BINS = 64

# Canny edge detection thresholds (approximated via PIL + scipy)
EDGE_LOW = 50
EDGE_HIGH = 150


# ─── Data types ─────────────────────────────────────────────────────────────

@dataclass
class SimilarityResult:
	"""Result of comparing two images across all metrics."""
	ssim_score: float
	color_histogram_score: float
	edge_similarity_score: float
	perceptual_hash_score: float
	composite_score: float
	reference_path: str
	screenshot_path: str

	def to_dict(self) -> dict:
		return asdict(self)

	def summary(self) -> str:
		return (
			f"  SSIM:             {self.ssim_score:6.1f}%\n"
			f"  Color histogram:  {self.color_histogram_score:6.1f}%\n"
			f"  Edge structure:   {self.edge_similarity_score:6.1f}%\n"
			f"  Perceptual hash:  {self.perceptual_hash_score:6.1f}%\n"
			f"  ─────────────────────────\n"
			f"  COMPOSITE:        {self.composite_score:6.1f}%"
		)


@dataclass
class CatalogEntry:
	"""Maps a reference image to a game camera angle."""
	reference_path: str
	name: str
	description: str
	# Tags for what this reference shows (e.g. "gate", "room", "lighting")
	tags: list[str]


# ─── Image preprocessing ───────────────────────────────────────────────────

def load_and_normalize(path: str, size: tuple[int, int] = COMPARE_SIZE) -> Image.Image:
	"""Load an image and resize to standard comparison dimensions."""
	img = Image.open(path).convert("RGB")
	img = img.resize(size, Image.LANCZOS)
	return img


def to_grayscale_array(img: Image.Image) -> np.ndarray:
	"""Convert PIL Image to grayscale numpy array (0-255)."""
	gray = img.convert("L")
	return np.array(gray, dtype=np.float64)


def extract_edges(img: Image.Image) -> np.ndarray:
	"""
	Extract edge map using Sobel filters (scipy-based Canny approximation).
	Returns a binary edge map as float64 array.
	"""
	gray = to_grayscale_array(img)

	# Gaussian blur to reduce noise
	smoothed = ndimage.gaussian_filter(gray, sigma=1.4)

	# Sobel gradients
	sx = ndimage.sobel(smoothed, axis=0)
	sy = ndimage.sobel(smoothed, axis=1)
	magnitude = np.hypot(sx, sy)

	# Normalize to 0-255 range
	if magnitude.max() > 0:
		magnitude = (magnitude / magnitude.max()) * 255.0

	# Threshold to binary edges
	edges = np.zeros_like(magnitude)
	edges[magnitude > EDGE_LOW] = 128
	edges[magnitude > EDGE_HIGH] = 255

	return edges


def compute_color_histogram(img: Image.Image, bins: int = HIST_BINS) -> np.ndarray:
	"""
	Compute a normalized color histogram across R, G, B channels.
	Returns a single concatenated histogram vector.
	"""
	arr = np.array(img, dtype=np.float64)
	histograms = []

	for channel in range(3):
		hist, _ = np.histogram(arr[:, :, channel], bins=bins, range=(0, 256))
		# Normalize
		total = hist.sum()
		if total > 0:
			hist = hist.astype(np.float64) / total
		histograms.append(hist)

	return np.concatenate(histograms)


# ─── Similarity metrics ────────────────────────────────────────────────────

def compute_ssim(ref: Image.Image, shot: Image.Image) -> float:
	"""
	Structural Similarity Index between two images.
	Returns 0-100 percentage.
	"""
	ref_gray = to_grayscale_array(ref)
	shot_gray = to_grayscale_array(shot)

	score = ssim(ref_gray, shot_gray, data_range=255.0)
	# SSIM ranges from -1 to 1, map to 0-100
	return max(0.0, score * 100.0)


def compute_color_similarity(ref: Image.Image, shot: Image.Image) -> float:
	"""
	Color histogram correlation between two images.
	Uses histogram intersection (Swain-Ballard) — measures overlap.
	Returns 0-100 percentage.
	"""
	hist_ref = compute_color_histogram(ref)
	hist_shot = compute_color_histogram(shot)

	# Histogram intersection: sum of min values
	intersection = np.minimum(hist_ref, hist_shot).sum()

	# Maximum possible intersection is 1.0 per channel (3 channels = 3.0)
	# but since we normalize per channel, max intersection = 3.0
	# Normalize to 0-1 by dividing by number of channels
	score = intersection / 3.0

	return min(100.0, score * 100.0)


def compute_edge_similarity(ref: Image.Image, shot: Image.Image) -> float:
	"""
	Compare edge structure maps between two images.
	Uses normalized cross-correlation of edge magnitude maps.
	Returns 0-100 percentage.
	"""
	edges_ref = extract_edges(ref)
	edges_shot = extract_edges(shot)

	# Normalize both to zero-mean
	ref_mean = edges_ref - edges_ref.mean()
	shot_mean = edges_shot - edges_shot.mean()

	# Cross-correlation
	numerator = np.sum(ref_mean * shot_mean)
	denominator = np.sqrt(np.sum(ref_mean ** 2) * np.sum(shot_mean ** 2))

	if denominator < 1e-10:
		return 0.0

	# Correlation ranges from -1 to 1
	correlation = numerator / denominator

	return max(0.0, correlation * 100.0)


def compute_perceptual_hash_similarity(ref: Image.Image, shot: Image.Image) -> float:
	"""
	Perceptual hash similarity using average hash + wavelet hash.
	Returns 0-100 percentage.
	"""
	# Average hash (fast, coarse)
	ahash_ref = imagehash.average_hash(ref, hash_size=16)
	ahash_shot = imagehash.average_hash(shot, hash_size=16)

	# Wavelet hash (captures more structure)
	whash_ref = imagehash.whash(ref, hash_size=16)
	whash_shot = imagehash.whash(shot, hash_size=16)

	# Hash distance is number of differing bits (0 = identical)
	# Max distance for 16x16 hash = 256 bits
	max_bits = 16 * 16

	ahash_sim = 1.0 - (ahash_ref - ahash_shot) / max_bits
	whash_sim = 1.0 - (whash_ref - whash_shot) / max_bits

	# Weighted average — wavelet hash is more structural
	combined = 0.4 * ahash_sim + 0.6 * whash_sim

	return max(0.0, combined * 100.0)


# ─── Composite scoring ─────────────────────────────────────────────────────

def compare_images(
	reference_path: str,
	screenshot_path: str,
	weights: Optional[dict[str, float]] = None,
) -> SimilarityResult:
	"""
	Compare a screenshot against a reference image using all metrics.
	Returns a SimilarityResult with individual and composite scores.
	"""
	w = weights or WEIGHTS

	ref = load_and_normalize(reference_path)
	shot = load_and_normalize(screenshot_path)

	ssim_score = compute_ssim(ref, shot)
	color_score = compute_color_similarity(ref, shot)
	edge_score = compute_edge_similarity(ref, shot)
	hash_score = compute_perceptual_hash_similarity(ref, shot)

	composite = (
		w["ssim"] * ssim_score
		+ w["color_histogram"] * color_score
		+ w["edge_similarity"] * edge_score
		+ w["perceptual_hash"] * hash_score
	)

	return SimilarityResult(
		ssim_score=round(ssim_score, 2),
		color_histogram_score=round(color_score, 2),
		edge_similarity_score=round(edge_score, 2),
		perceptual_hash_score=round(hash_score, 2),
		composite_score=round(composite, 2),
		reference_path=reference_path,
		screenshot_path=screenshot_path,
	)


# ─── Batch operations ──────────────────────────────────────────────────────

def load_catalog(catalog_path: str) -> list[CatalogEntry]:
	"""Load reference image catalog from JSON."""
	with open(catalog_path) as f:
		data = json.load(f)

	entries = []
	for item in data["references"]:
		entries.append(CatalogEntry(
			reference_path=item["reference_path"],
			name=item["name"],
			description=item.get("description", ""),
			tags=item.get("tags", []),
		))
	return entries


def batch_compare(
	catalog_path: str,
	screenshots_dir: str,
) -> list[dict]:
	"""
	Compare all screenshots in a directory against their matching
	catalog references. Screenshots should be named to match catalog
	entry names (e.g. "gate-room-front.png" matches name "gate-room-front").
	"""
	catalog = load_catalog(catalog_path)
	results = []

	for entry in catalog:
		# Look for a matching screenshot
		shot_name = entry.name
		shot_path = None

		for ext in [".png", ".jpg", ".jpeg", ".webp"]:
			candidate = os.path.join(screenshots_dir, f"{shot_name}{ext}")
			if os.path.exists(candidate):
				shot_path = candidate
				break

		if not shot_path:
			print(f"  SKIP: No screenshot found for '{shot_name}'")
			continue

		if not os.path.exists(entry.reference_path):
			print(f"  SKIP: Reference not found: {entry.reference_path}")
			continue

		result = compare_images(entry.reference_path, shot_path)
		results.append({
			"name": entry.name,
			"description": entry.description,
			"tags": entry.tags,
			**result.to_dict(),
		})

		print(f"\n  {entry.name}: {result.composite_score:.1f}% composite")
		print(result.summary())

	return results


def generate_report(catalog_path: str, screenshots_dir: str) -> str:
	"""Generate a full comparison report as JSON."""
	results = batch_compare(catalog_path, screenshots_dir)

	if not results:
		return json.dumps({"error": "No comparisons made", "results": []}, indent=2)

	avg_composite = sum(r["composite_score"] for r in results) / len(results)

	report = {
		"timestamp": __import__("datetime").datetime.now().isoformat(),
		"average_composite_score": round(avg_composite, 2),
		"num_comparisons": len(results),
		"results": results,
		"weights": WEIGHTS,
	}

	return json.dumps(report, indent=2)


# ─── Self-validation ───────────────────────────────────────────────────────

def validate() -> bool:
	"""
	Validate the tool by running sanity checks:
	1. Compare a reference image against itself (should be ~100%)
	2. Compare two very different reference images (should be low)
	3. Compare same image with slight brightness shift (should be high)
	"""
	ref_dir = os.path.expanduser("~/Documents/Stargate")

	# Find two reference images that exist
	candidates = [
		os.path.join(ref_dir, "sgu-gateroom.webp"),
		os.path.join(ref_dir, "sgu-stargate.jpg"),
		os.path.join(ref_dir, "Observation Deck in FTL.jpeg"),
		os.path.join(ref_dir, "Destiny.jpeg"),
		os.path.join(ref_dir, "Kino_dispenser.webp"),
		os.path.join(ref_dir, "Stargate-Universe-SGU-Destiny-Hatch-Control-1.jpg"),
	]

	available = [p for p in candidates if os.path.exists(p)]

	if len(available) < 2:
		print("ERROR: Need at least 2 reference images for validation")
		return False

	img_a = available[0]
	img_b = available[1]

	print("=" * 60)
	print("VISUAL SIMILARITY TOOL — VALIDATION")
	print("=" * 60)

	# Test 1: Self-similarity (should be ~100%)
	print(f"\n--- Test 1: Self-similarity ---")
	print(f"  Comparing: {os.path.basename(img_a)} vs itself")
	result = compare_images(img_a, img_a)
	print(result.summary())
	test1_pass = result.composite_score > 98.0
	print(f"  {'PASS' if test1_pass else 'FAIL'}: Expected > 98%, got {result.composite_score:.1f}%")

	# Test 2: Different images (should be noticeably lower)
	print(f"\n--- Test 2: Cross-image comparison ---")
	print(f"  Comparing: {os.path.basename(img_a)} vs {os.path.basename(img_b)}")
	result = compare_images(img_a, img_b)
	print(result.summary())
	# Two SGU images from the same show will share palette, so we expect
	# moderate similarity (40-70%), not near-zero like totally unrelated images
	test2_pass = result.composite_score < 90.0
	print(f"  {'PASS' if test2_pass else 'FAIL'}: Expected < 90%, got {result.composite_score:.1f}%")

	# Test 3: Brightness-shifted version (should still be high)
	print(f"\n--- Test 3: Brightness-shifted self-similarity ---")
	ref_img = load_and_normalize(img_a)
	arr = np.array(ref_img, dtype=np.float64)
	# Darken by 20%
	darkened = np.clip(arr * 0.8, 0, 255).astype(np.uint8)
	dark_img = Image.fromarray(darkened)

	# Save temp file for comparison
	tmp_path = "/tmp/visual_sim_dark_test.png"
	dark_img.save(tmp_path)
	result = compare_images(img_a, tmp_path)
	print(f"  Comparing: {os.path.basename(img_a)} vs 20% darkened version")
	print(result.summary())
	test3_pass = result.composite_score > 60.0
	print(f"  {'PASS' if test3_pass else 'FAIL'}: Expected > 60%, got {result.composite_score:.1f}%")

	# Test 4: Compare all available reference images pairwise
	print(f"\n--- Test 4: Pairwise reference comparison matrix ---")
	print(f"  (Shows how distinct each reference is from the others)\n")

	names = [os.path.basename(p) for p in available]
	max_name_len = max(len(n) for n in names)

	# Print header
	header = " " * (max_name_len + 2)
	for name in names:
		header += f"{name[:12]:>13}"
	print(header)

	for i, path_a in enumerate(available):
		row = f"  {names[i]:<{max_name_len}}"
		for j, path_b in enumerate(available):
			if i == j:
				row += f"{'---':>13}"
			elif j > i:
				r = compare_images(path_a, path_b)
				row += f"{r.composite_score:>12.1f}%"
			else:
				row += f"{'':>13}"
		print(row)

	# Test 5: Totally synthetic image (solid color block — should be very low)
	print(f"\n--- Test 5: Synthetic dissimilarity ---")
	solid = Image.new("RGB", COMPARE_SIZE, (255, 0, 0))  # bright red
	solid_path = "/tmp/visual_sim_solid_test.png"
	solid.save(solid_path)
	result = compare_images(img_a, solid_path)
	print(f"  Comparing: {os.path.basename(img_a)} vs solid red block")
	print(result.summary())
	test5_pass = result.composite_score < 30.0
	print(f"  {'PASS' if test5_pass else 'FAIL'}: Expected < 30%, got {result.composite_score:.1f}%")

	# Cleanup
	for tmp in [tmp_path, solid_path]:
		if os.path.exists(tmp):
			os.remove(tmp)

	all_pass = test1_pass and test2_pass and test3_pass and test5_pass
	print(f"\n{'=' * 60}")
	print(f"OVERALL: {'ALL TESTS PASSED' if all_pass else 'SOME TESTS FAILED'}")
	print(f"{'=' * 60}")

	return all_pass


# ─── CLI ────────────────────────────────────────────────────────────────────

def main():
	parser = argparse.ArgumentParser(
		description="Visual similarity comparison for Stargate Universe game screenshots"
	)
	subparsers = parser.add_subparsers(dest="command")

	# compare: single pair
	p_compare = subparsers.add_parser("compare", help="Compare two images")
	p_compare.add_argument("reference", help="Path to reference image")
	p_compare.add_argument("screenshot", help="Path to game screenshot")
	p_compare.add_argument("--json", action="store_true", help="Output as JSON")

	# batch: catalog-based comparison
	p_batch = subparsers.add_parser("batch", help="Batch compare using catalog")
	p_batch.add_argument("catalog", help="Path to catalog JSON")
	p_batch.add_argument("screenshots_dir", help="Directory of game screenshots")

	# report: full JSON report
	p_report = subparsers.add_parser("report", help="Generate full comparison report")
	p_report.add_argument("catalog", help="Path to catalog JSON")
	p_report.add_argument("screenshots_dir", help="Directory of game screenshots")
	p_report.add_argument("-o", "--output", help="Output file (default: stdout)")

	# validate: self-test
	subparsers.add_parser("validate", help="Run self-validation tests")

	# shapes: B&W edge comparison focused on structure, not color
	p_shapes = subparsers.add_parser("shapes", help="Shape/structure comparison (grayscale edge maps)")
	p_shapes.add_argument("reference", help="Path to reference image")
	p_shapes.add_argument("screenshot", help="Path to game screenshot")
	p_shapes.add_argument("-o", "--output", help="Save side-by-side edge comparison image")

	args = parser.parse_args()

	if args.command == "shapes":
		ref = load_and_normalize(args.reference)
		shot = load_and_normalize(args.screenshot)

		# Convert to grayscale
		ref_gray = to_grayscale_array(ref)
		shot_gray = to_grayscale_array(shot)

		# Extract edges
		edges_ref = extract_edges(ref)
		edges_shot = extract_edges(shot)

		# SSIM on grayscale (structure only, no color)
		gray_ssim = ssim(ref_gray, shot_gray, data_range=255.0) * 100

		# Edge cross-correlation
		edge_sim = compute_edge_similarity(ref, shot)

		# Grayscale histogram (brightness distribution only)
		hist_ref, _ = np.histogram(ref_gray, bins=64, range=(0, 256))
		hist_shot, _ = np.histogram(shot_gray, bins=64, range=(0, 256))
		hist_ref = hist_ref / hist_ref.sum()
		hist_shot = hist_shot / hist_shot.sum()
		gray_hist = np.minimum(hist_ref, hist_shot).sum() * 100

		# Perceptual hash on grayscale
		ref_bw = ref.convert("L")
		shot_bw = shot.convert("L")
		ahash_sim = 1.0 - (imagehash.average_hash(ref_bw, 16) - imagehash.average_hash(shot_bw, 16)) / 256
		whash_sim = 1.0 - (imagehash.whash(ref_bw, 16) - imagehash.whash(shot_bw, 16)) / 256
		bw_hash = (0.4 * ahash_sim + 0.6 * whash_sim) * 100

		composite = 0.3 * gray_ssim + 0.2 * gray_hist + 0.3 * edge_sim + 0.2 * bw_hash

		print(f"\n  SHAPE COMPARISON (color removed)")
		print(f"  ─────────────────────────────────")
		print(f"  Grayscale SSIM:     {gray_ssim:6.1f}%")
		print(f"  Brightness hist:    {gray_hist:6.1f}%")
		print(f"  Edge structure:     {edge_sim:6.1f}%")
		print(f"  B&W perceptual:     {bw_hash:6.1f}%")
		print(f"  ─────────────────────────────────")
		print(f"  SHAPE COMPOSITE:    {composite:6.1f}%")

		if args.output:
			# Save side-by-side: ref edges | shot edges
			edge_ref_img = Image.fromarray(edges_ref.astype(np.uint8))
			edge_shot_img = Image.fromarray(edges_shot.astype(np.uint8))
			w, h = COMPARE_SIZE
			combined = Image.new("L", (w * 2 + 4, h), 128)
			combined.paste(edge_ref_img, (0, 0))
			combined.paste(edge_shot_img, (w + 4, 0))
			combined.save(args.output)
			print(f"\n  Edge comparison saved: {args.output}")

	elif args.command == "compare":
		result = compare_images(args.reference, args.screenshot)
		if args.json:
			print(json.dumps(result.to_dict(), indent=2))
		else:
			print(f"\nComparing:")
			print(f"  Reference:  {args.reference}")
			print(f"  Screenshot: {args.screenshot}")
			print()
			print(result.summary())

	elif args.command == "batch":
		batch_compare(args.catalog, args.screenshots_dir)

	elif args.command == "report":
		report = generate_report(args.catalog, args.screenshots_dir)
		if args.output:
			with open(args.output, "w") as f:
				f.write(report)
			print(f"Report written to {args.output}")
		else:
			print(report)

	elif args.command == "validate":
		success = validate()
		sys.exit(0 if success else 1)

	else:
		parser.print_help()


if __name__ == "__main__":
	main()
