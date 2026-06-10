#!/usr/bin/env python3
"""Probe Kenney mini-character GLBs: map atlas swatch cells -> garment roles.

Each mini-char garment UV-maps onto a flat gradient swatch in the shared
512x512 colormap. This script reads POSITION + TEXCOORD_0 straight from the
GLB binary chunk, buckets vertices by swatch cell, and reports per cell the
vertex count, mean height band, and sampled albedo so a human (or the
character_factory registry) can assign roles like shirt/pants/shoes/skin/hair.

Usage: python3 tools/probe_character_swatches.py models/characters/*.glb
"""
import json
import struct
import sys

ATLAS = 512
CELL = 32  # quantize UVs to 32px cells; swatch columns are ~46px wide


def read_glb(path):
	with open(path, "rb") as f:
		data = f.read()
	magic, _version, _length = struct.unpack("<III", data[:12])
	assert magic == 0x46546C67, f"not a GLB: {path}"
	offset = 12
	doc = None
	blob = None
	while offset < len(data):
		clen, ctype = struct.unpack("<II", data[offset : offset + 8])
		chunk = data[offset + 8 : offset + 8 + clen]
		if ctype == 0x4E4F534A:
			doc = json.loads(chunk)
		elif ctype == 0x004E4942:
			blob = chunk
		offset += 8 + clen
	return doc, blob


def read_accessor(doc, blob, idx):
	acc = doc["accessors"][idx]
	view = doc["bufferViews"][acc["bufferView"]]
	comp_size = {5126: 4, 5123: 2, 5121: 1}[acc["componentType"]]
	ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
	start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
	stride = view.get("byteStride", comp_size * ncomp)
	fmt = {5126: "f", 5123: "H", 5121: "B"}[acc["componentType"]]
	out = []
	for i in range(acc["count"]):
		base = start + i * stride
		vals = struct.unpack_from("<" + fmt * ncomp, blob, base)
		out.append(vals)
	return out


def sample_colormap(px, x, y):
	x = max(0, min(ATLAS - 1, x))
	y = max(0, min(ATLAS - 1, y))
	return px[x, y]


def probe(path, px):
	doc, blob = read_glb(path)
	cells = {}
	for mesh in doc["meshes"]:
		for prim in mesh["primitives"]:
			pos = read_accessor(doc, blob, prim["attributes"]["POSITION"])
			uv = read_accessor(doc, blob, prim["attributes"]["TEXCOORD_0"])
			for (x, y, z), (u, v) in zip(pos, uv):
				cx = int(u * ATLAS) // CELL
				cy = int(v * ATLAS) // CELL
				key = (cx, cy)
				entry = cells.setdefault(key, {"n": 0, "ys": [], "mesh": mesh["name"]})
				entry["n"] += 1
				entry["ys"].append(y)
	report = []
	for (cx, cy), e in sorted(cells.items(), key=lambda kv: -kv[1]["n"]):
		ys = e["ys"]
		color = sample_colormap(px, cx * CELL + CELL // 2, cy * CELL + CELL // 2)
		report.append(
			{
				"cell": [cx, cy],
				"px_rect": [cx * CELL, cy * CELL, CELL, CELL],
				"verts": e["n"],
				"y_min": round(min(ys), 3),
				"y_max": round(max(ys), 3),
				"y_mean": round(sum(ys) / len(ys), 3),
				"rgb": list(color)[:3],
				"mesh": e["mesh"],
			}
		)
	return report


def main():
	from PIL import Image

	im = Image.open("models/characters/Textures/colormap.png").convert("RGB")
	px = im.load()
	out = {}
	for path in sys.argv[1:]:
		name = path.split("/")[-1].replace(".glb", "")
		out[name] = probe(path, px)
	print(json.dumps(out, indent=1))


if __name__ == "__main__":
	main()
