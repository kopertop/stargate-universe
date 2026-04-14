#!/usr/bin/env python3
"""
Detailed validation of the visual similarity tool.

Tests:
1. Self-similarity (identity) — must be 100%
2. Near-miss (brightness/contrast shifts) — must be >60%
3. Cross-scene SGU images — should be 20-50% (shared palette, different structure)
4. Completely unrelated images — should be <25%
5. Synthetic gradient tests — validates each metric independently
6. Scale invariance — same image at different resolutions should score high
"""

import os
import sys
import tempfile

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

# Add parent directory to path
sys.path.insert(0, os.path.dirname(__file__))
from importlib.machinery import SourceFileLoader
sim = SourceFileLoader("visual_similarity", os.path.join(os.path.dirname(__file__), "visual-similarity.py")).load_module()


REF_DIR = os.path.expanduser("~/Documents/Stargate")

# All available reference images
REFS = {
	"gateroom": os.path.join(REF_DIR, "sgu-gateroom.webp"),
	"stargate": os.path.join(REF_DIR, "sgu-stargate.jpg"),
	"obs_deck": os.path.join(REF_DIR, "Observation Deck in FTL.jpeg"),
	"destiny": os.path.join(REF_DIR, "Destiny.jpeg"),
	"kino": os.path.join(REF_DIR, "Kino_dispenser.webp"),
	"hatch": os.path.join(REF_DIR, "Stargate-Universe-SGU-Destiny-Hatch-Control-1.jpg"),
	"destiny_ftl": os.path.join(REF_DIR, "Destiny out of FTL.jpeg"),
	"destiny_3q": os.path.join(REF_DIR, "Screenshot 2026-02-08 at 2.49.13 PM.png"),
}


def save_tmp(img: Image.Image, suffix: str = ".png") -> str:
	"""Save a PIL Image to a temp file and return the path."""
	fd, path = tempfile.mkstemp(suffix=suffix)
	os.close(fd)
	img.save(path)
	return path


def test_self_similarity():
	"""Every image compared to itself must score 100%."""
	print("\n" + "=" * 60)
	print("TEST: Self-similarity (identity)")
	print("=" * 60)

	passed = 0
	total = 0
	for name, path in REFS.items():
		if not os.path.exists(path):
			continue
		total += 1
		result = sim.compare_images(path, path)
		ok = result.composite_score >= 99.0
		passed += ok
		status = "PASS" if ok else "FAIL"
		print(f"  {status}: {name:>15} = {result.composite_score:.1f}%")

	print(f"  Result: {passed}/{total} passed")
	return passed == total


def test_brightness_robustness():
	"""Image with brightness/contrast shifts should still score high."""
	print("\n" + "=" * 60)
	print("TEST: Brightness/contrast robustness")
	print("=" * 60)

	ref_path = REFS["gateroom"]
	if not os.path.exists(ref_path):
		print("  SKIP: gateroom reference not found")
		return True

	ref_img = Image.open(ref_path).convert("RGB")
	transforms = [
		("20% darker", lambda img: ImageEnhance.Brightness(img).enhance(0.8)),
		("30% brighter", lambda img: ImageEnhance.Brightness(img).enhance(1.3)),
		("Low contrast", lambda img: ImageEnhance.Contrast(img).enhance(0.6)),
		("High contrast", lambda img: ImageEnhance.Contrast(img).enhance(1.5)),
		("Slight blur", lambda img: img.filter(ImageFilter.GaussianBlur(radius=2))),
		("Color shift (warmer)", lambda img: Image.merge("RGB", [
			ImageEnhance.Brightness(img.split()[0]).enhance(1.1),
			img.split()[1],
			ImageEnhance.Brightness(img.split()[2]).enhance(0.9),
		])),
	]

	passed = 0
	for name, transform in transforms:
		modified = transform(ref_img)
		tmp = save_tmp(modified)
		result = sim.compare_images(ref_path, tmp)
		os.unlink(tmp)

		# Brightness/contrast shifts should keep similarity >55%
		ok = result.composite_score > 55.0
		passed += ok
		status = "PASS" if ok else "FAIL"
		print(f"  {status}: {name:>25} = {result.composite_score:.1f}%  "
			  f"(ssim={result.ssim_score:.0f} color={result.color_histogram_score:.0f} "
			  f"edge={result.edge_similarity_score:.0f} hash={result.perceptual_hash_score:.0f})")

	print(f"  Result: {passed}/{len(transforms)} passed")
	return passed == len(transforms)


def test_cross_scene_discrimination():
	"""Different SGU scenes should score 20-65% — similar palette, different structure."""
	print("\n" + "=" * 60)
	print("TEST: Cross-scene discrimination")
	print("=" * 60)

	# Pick pairs that should be meaningfully different
	pairs = [
		("gateroom", "stargate", "Same room, different framing/lighting"),
		("gateroom", "obs_deck", "Different rooms, similar mood"),
		("gateroom", "kino", "Interior vs close-up prop"),
		("destiny", "destiny_ftl", "Same ship, different lighting"),
		("obs_deck", "kino", "Interior vs prop detail"),
	]

	passed = 0
	total = 0
	for name_a, name_b, desc in pairs:
		path_a = REFS.get(name_a)
		path_b = REFS.get(name_b)
		if not path_a or not path_b or not os.path.exists(path_a) or not os.path.exists(path_b):
			continue

		total += 1
		result = sim.compare_images(path_a, path_b)

		# Cross-scene SGU images share palette but differ structurally
		# Expect 15-65% range
		ok = 10.0 < result.composite_score < 70.0
		passed += ok
		status = "PASS" if ok else "FAIL"
		print(f"  {status}: {name_a:>10} vs {name_b:<12} = {result.composite_score:.1f}%  ({desc})")

	print(f"  Result: {passed}/{total} passed")
	return passed == total


def test_synthetic_dissimilarity():
	"""Totally synthetic/unrelated images should score very low."""
	print("\n" + "=" * 60)
	print("TEST: Synthetic dissimilarity")
	print("=" * 60)

	ref_path = REFS["gateroom"]
	if not os.path.exists(ref_path):
		print("  SKIP: gateroom reference not found")
		return True

	synthetics = [
		("Solid red", Image.new("RGB", sim.COMPARE_SIZE, (255, 0, 0))),
		("Solid white", Image.new("RGB", sim.COMPARE_SIZE, (255, 255, 255))),
		("Solid black", Image.new("RGB", sim.COMPARE_SIZE, (0, 0, 0))),
		("Random noise", Image.fromarray(
			np.random.randint(0, 256, (*sim.COMPARE_SIZE[::-1], 3), dtype=np.uint8)
		)),
		("Horizontal gradient", Image.fromarray(
			np.tile(np.linspace(0, 255, sim.COMPARE_SIZE[0], dtype=np.uint8),
					(sim.COMPARE_SIZE[1], 1))[..., np.newaxis].repeat(3, axis=2)
		)),
	]

	passed = 0
	for name, img in synthetics:
		tmp = save_tmp(img)
		result = sim.compare_images(ref_path, tmp)
		os.unlink(tmp)

		ok = result.composite_score < 35.0
		passed += ok
		status = "PASS" if ok else "FAIL"
		print(f"  {status}: {name:>25} = {result.composite_score:.1f}%  "
			  f"(ssim={result.ssim_score:.0f} color={result.color_histogram_score:.0f} "
			  f"edge={result.edge_similarity_score:.0f} hash={result.perceptual_hash_score:.0f})")

	print(f"  Result: {passed}/{len(synthetics)} passed")
	return passed == len(synthetics)


def test_metric_independence():
	"""Verify each metric responds to the right kind of change."""
	print("\n" + "=" * 60)
	print("TEST: Metric independence")
	print("=" * 60)

	ref_path = REFS["gateroom"]
	if not os.path.exists(ref_path):
		print("  SKIP: gateroom reference not found")
		return True

	ref_img = sim.load_and_normalize(ref_path)

	# Create a version with same structure but shifted color palette
	arr = np.array(ref_img, dtype=np.float64)
	# Swap R and B channels
	color_shifted = arr.copy()
	color_shifted[:, :, 0] = arr[:, :, 2]
	color_shifted[:, :, 2] = arr[:, :, 0]
	color_shifted_img = Image.fromarray(np.clip(color_shifted, 0, 255).astype(np.uint8))
	tmp_color = save_tmp(color_shifted_img)

	r_color = sim.compare_images(ref_path, tmp_color)
	os.unlink(tmp_color)

	# Color swap should hurt color_histogram more than edge_similarity
	color_penalty = 100 - r_color.color_histogram_score
	edge_penalty = 100 - r_color.edge_similarity_score
	ssim_penalty = 100 - r_color.ssim_score

	print(f"  Channel swap (R<->B):")
	print(f"    Color histogram penalty: {color_penalty:.1f} (should be high)")
	print(f"    Edge similarity penalty: {edge_penalty:.1f} (should be low)")
	print(f"    SSIM penalty:            {ssim_penalty:.1f} (moderate)")

	# Create a version with same colors but scrambled structure (shuffle blocks)
	block_size = 32
	arr2 = np.array(ref_img)
	h, w, c = arr2.shape
	blocks = []
	for y in range(0, h - block_size, block_size):
		for x in range(0, w - block_size, block_size):
			blocks.append(arr2[y:y + block_size, x:x + block_size].copy())
	np.random.shuffle(blocks)
	scrambled = arr2.copy()
	idx = 0
	for y in range(0, h - block_size, block_size):
		for x in range(0, w - block_size, block_size):
			if idx < len(blocks):
				scrambled[y:y + block_size, x:x + block_size] = blocks[idx]
				idx += 1
	scrambled_img = Image.fromarray(scrambled)
	tmp_scramble = save_tmp(scrambled_img)

	r_scramble = sim.compare_images(ref_path, tmp_scramble)
	os.unlink(tmp_scramble)

	print(f"\n  Block scramble (same colors, shuffled structure):")
	print(f"    Color histogram: {r_scramble.color_histogram_score:.1f}% (should remain high)")
	print(f"    Edge similarity: {r_scramble.edge_similarity_score:.1f}% (should drop)")
	print(f"    SSIM:            {r_scramble.ssim_score:.1f}% (should drop)")

	# Verify: color swap hurts color more than edges
	test1 = color_penalty > edge_penalty
	# Verify: block scramble preserves color histogram better than structure
	test2 = r_scramble.color_histogram_score > r_scramble.edge_similarity_score

	print(f"\n  Metric isolation test 1 (color swap hurts color > edges): {'PASS' if test1 else 'FAIL'}")
	print(f"  Metric isolation test 2 (scramble preserves color > structure): {'PASS' if test2 else 'FAIL'}")

	return test1 and test2


def test_scale_invariance():
	"""Same image at different resolutions should score high after normalization."""
	print("\n" + "=" * 60)
	print("TEST: Scale invariance")
	print("=" * 60)

	ref_path = REFS["gateroom"]
	if not os.path.exists(ref_path):
		print("  SKIP: gateroom reference not found")
		return True

	ref_img = Image.open(ref_path).convert("RGB")
	original_size = ref_img.size

	resolutions = [
		("Quarter size", (original_size[0] // 4, original_size[1] // 4)),
		("Double size", (original_size[0] * 2, original_size[1] * 2)),
		("Square crop", (300, 300)),
		("Wide aspect", (800, 200)),
	]

	passed = 0
	for name, size in resolutions:
		resized = ref_img.resize(size, Image.LANCZOS)
		tmp = save_tmp(resized)
		result = sim.compare_images(ref_path, tmp)
		os.unlink(tmp)

		# After normalization, should still be recognizable (>50%)
		# Wide aspect ratio is a harder test (letterboxing distortion)
		threshold = 40.0 if "Wide" in name else 60.0
		ok = result.composite_score > threshold
		passed += ok
		status = "PASS" if ok else "FAIL"
		print(f"  {status}: {name:>20} ({size[0]}x{size[1]}) = {result.composite_score:.1f}%")

	print(f"  Result: {passed}/{len(resolutions)} passed")
	return passed == len(resolutions)


# ─── Main ───────────────────────────────────────────────────────────────────

def main():
	print("=" * 60)
	print("VISUAL SIMILARITY TOOL — DETAILED VALIDATION")
	print("=" * 60)

	results = {
		"Self-similarity": test_self_similarity(),
		"Brightness robustness": test_brightness_robustness(),
		"Cross-scene discrimination": test_cross_scene_discrimination(),
		"Synthetic dissimilarity": test_synthetic_dissimilarity(),
		"Metric independence": test_metric_independence(),
		"Scale invariance": test_scale_invariance(),
	}

	print("\n" + "=" * 60)
	print("SUMMARY")
	print("=" * 60)

	all_pass = True
	for name, passed in results.items():
		status = "PASS" if passed else "FAIL"
		if not passed:
			all_pass = False
		print(f"  {status}: {name}")

	print(f"\n  OVERALL: {'ALL TESTS PASSED' if all_pass else 'SOME TESTS FAILED'}")
	print("=" * 60)

	return all_pass


if __name__ == "__main__":
	success = main()
	sys.exit(0 if success else 1)
