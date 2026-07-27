#!/usr/bin/env python3
"""Add Godot-humanoid finger bones + skin weights to a Mint clip GLB.

Mint's Meshy animation catalog ships a 24-bone body rig with no fingers.
This keeps that body skeleton (so Mint clips still merge) and inserts
SkeletonProfileHumanoid finger chains under LeftHand/RightHand.

All placement is done in armature-local space to avoid glTF scale mismatches.

Usage:
  blender -b --python tools/mint_add_finger_bones.py -- \\
	  --in models/mint/eli/clips/Idle.glb \\
	  --out models/mint/eli/clips/Idle.glb
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


FINGER_CHAINS = {
	"Thumb": ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"],
	"Index": ["IndexProximal", "IndexIntermediate", "IndexDistal"],
	"Middle": ["MiddleProximal", "MiddleIntermediate", "MiddleDistal"],
	"Ring": ["RingProximal", "RingIntermediate", "RingDistal"],
	"Little": ["LittleProximal", "LittleIntermediate", "LittleDistal"],
}

LANE_T = {
	"Thumb": 0.85,
	"Index": 0.40,
	"Middle": 0.05,
	"Ring": -0.30,
	"Little": -0.65,
}


def _parse_args(argv: list[str]) -> argparse.Namespace:
	if "--" in argv:
		argv = argv[argv.index("--") + 1 :]
	else:
		argv = []
	p = argparse.ArgumentParser()
	p.add_argument("--in", dest="in_path", required=True)
	p.add_argument("--out", dest="out_path", required=True)
	return p.parse_args(argv)


def _clear_scene() -> None:
	bpy.ops.wm.read_factory_settings(use_empty=True)


def _find_armature() -> bpy.types.Object:
	arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
	if not arms:
		raise RuntimeError("No armature in imported GLB")
	return arms[0]


def _find_skinned_meshes(arm: bpy.types.Object) -> list[bpy.types.Object]:
	out: list[bpy.types.Object] = []
	for o in bpy.context.scene.objects:
		if o.type != "MESH":
			continue
		for m in o.modifiers:
			if m.type == "ARMATURE" and m.object == arm:
				out.append(o)
				break
		if o not in out and any(b.name in o.vertex_groups for b in arm.data.bones):
			out.append(o)
	if not out:
		meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
		if not meshes:
			raise RuntimeError("No mesh in imported GLB")
		out = [max(meshes, key=lambda m: len(m.data.vertices))]
	return out


def _fix_leaf_bone_tails(arm: bpy.types.Object) -> None:
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for eb in arm.data.edit_bones:
		vec = eb.tail - eb.head
		if vec.length <= 80.0:
			continue
		parent_len = (eb.parent.tail - eb.parent.head).length if eb.parent else 12.0
		# Clamp absurd glTF leaf tails to a fraction of the parent bone.
		target = min(max(parent_len * 0.45, 6.0), 28.0)
		eb.tail = eb.head + vec.normalized() * target
	bpy.ops.object.mode_set(mode="OBJECT")


def _strip_existing_fingers(arm: bpy.types.Object) -> None:
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	ebones = arm.data.edit_bones
	names = [b.name for b in ebones if any(k in b.name for k in ("Thumb", "Index", "Middle", "Ring", "Little"))]
	for n in names:
		if n in ebones:
			ebones.remove(ebones[n])
	bpy.ops.object.mode_set(mode="OBJECT")


def _hand_points_local(arm: bpy.types.Object, mesh: bpy.types.Object, hand: str) -> list[Vector]:
	if hand not in mesh.vertex_groups:
		return []
	g = mesh.vertex_groups[hand]
	# Mesh → armature local.
	to_arm = arm.matrix_world.inverted() @ mesh.matrix_world
	pts: list[Vector] = []
	for v in mesh.data.vertices:
		w = 0.0
		for vg in v.groups:
			if vg.group == g.index:
				w = vg.weight
				break
		if w < 0.08:
			continue
		pts.append(to_arm @ v.co)
	return pts


def _hand_frame_local(
	arm: bpy.types.Object, mesh: bpy.types.Object, hand: str
) -> tuple[Vector, Vector, Vector, Vector, float]:
	pts = _hand_points_local(arm, mesh, hand)
	if len(pts) < 8:
		raise RuntimeError(f"Not enough weighted verts on {hand}")
	origin = arm.data.bones[hand].head_local.copy()
	finger = max(pts, key=lambda p: (p - origin).length) - origin
	if finger.length < 1e-4:
		finger = Vector((0, 1, 0))
	finger.normalize()
	parent = arm.data.bones[hand].parent
	if parent is not None:
		across = (origin - parent.head_local).cross(finger)
	else:
		across = Vector((1, 0, 0)).cross(finger)
	if across.length < 1e-4:
		across = Vector((0, 0, 1)).cross(finger)
	across.normalize()
	up = finger.cross(across).normalized()
	proj = sorted(max(0.0, (p - origin).dot(finger)) for p in pts)
	# Prefer euclidean span if projection collapses.
	eucl = sorted((p - origin).length for p in pts)
	length = max(proj[int(len(proj) * 0.9)], eucl[int(len(eucl) * 0.85)] * 0.85)
	length = max(8.0, min(length, 80.0))
	return origin, finger, across, up, length


def _add_finger_bones(
	arm: bpy.types.Object,
	side: str,
	origin: Vector,
	finger: Vector,
	across: Vector,
	up: Vector,
	length: float,
) -> list[str]:
	hand = f"{side}Hand"
	created: list[str] = []
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	ebones = arm.data.edit_bones
	hand_eb = ebones[hand]

	for digit, chain in FINGER_CHAINS.items():
		lane = LANE_T[digit]
		base_along = length * (0.18 if digit != "Thumb" else 0.10)
		base_across = length * 0.42 * lane
		base_up = length * (0.10 if digit == "Thumb" else 0.0)
		if digit == "Thumb":
			dir_f = (finger * 0.50 + across * 0.75 + up * 0.30).normalized()
			seg_fracs = (0.26, 0.20, 0.16)
		else:
			dir_f = (finger + across * lane * 0.10).normalized()
			seg_fracs = (0.28, 0.22, 0.16)
		cursor = origin + finger * base_along + across * base_across + up * base_up
		parent = hand_eb
		for i, suffix in enumerate(chain):
			bname = f"{side}{suffix}"
			seg = length * seg_fracs[i]
			eb = ebones.new(bname)
			eb.head = cursor.copy()
			eb.tail = cursor + dir_f * seg
			eb.parent = parent
			eb.use_connect = i > 0
			eb.align_roll(up)
			parent = eb
			cursor = eb.tail.copy()
			created.append(bname)
	bpy.ops.object.mode_set(mode="OBJECT")
	return created


def _ensure_vgroup(mesh: bpy.types.Object, name: str) -> bpy.types.VertexGroup:
	if name in mesh.vertex_groups:
		return mesh.vertex_groups[name]
	return mesh.vertex_groups.new(name=name)


def _weight_fingers(
	arm: bpy.types.Object,
	mesh: bpy.types.Object,
	side: str,
	origin: Vector,
	finger: Vector,
	across: Vector,
	up: Vector,
	length: float,
) -> int:
	hand = f"{side}Hand"
	hand_g = mesh.vertex_groups[hand]
	to_arm = arm.matrix_world.inverted() @ mesh.matrix_world
	for digit, chain in FINGER_CHAINS.items():
		for suffix in chain:
			_ensure_vgroup(mesh, f"{side}{suffix}")

	assigned = 0
	for vi, v in enumerate(mesh.data.vertices):
		hw = 0.0
		for vg in v.groups:
			if vg.group == hand_g.index:
				hw = vg.weight
				break
		if hw < 0.08:
			continue
		local = to_arm @ v.co
		rel = local - origin
		along = rel.dot(finger)
		if along < length * 0.10:
			continue
		lane = rel.dot(across) / max(1e-4, length * 0.45)
		up_v = rel.dot(up)
		scores = {}
		for digit, lane_t in LANE_T.items():
			s = abs(lane - lane_t)
			if digit == "Thumb":
				s -= max(0.0, up_v / max(1e-4, length)) * 0.55
			scores[digit] = s
		best = min(scores, key=scores.get)
		chain = FINGER_CHAINS[best]
		t = (along - length * 0.10) / max(1e-4, length * 0.90)
		t = max(0.0, min(1.0, t))
		ji = 0 if t < 0.34 else (1 if t < 0.67 else 2)
		weights = [0.12, 0.12, 0.12]
		weights[ji] = 0.70
		if ji > 0:
			weights[ji - 1] += 0.18
		if ji < 2:
			weights[ji + 1] += 0.12
		s = sum(weights)
		weights = [w / s for w in weights]
		remain = hw * 0.22
		finger_total = hw - remain
		hand_g.add([vi], remain, "REPLACE")
		# Clear any previous finger groups on this vert for this side.
		for digit, chain2 in FINGER_CHAINS.items():
			for suffix in chain2:
				mesh.vertex_groups[f"{side}{suffix}"].add([vi], 0.0, "REPLACE")
		for i, suffix in enumerate(chain):
			mesh.vertex_groups[f"{side}{suffix}"].add([vi], finger_total * weights[i], "REPLACE")
		assigned += 1
	return assigned


def _ensure_armature_modifier(mesh: bpy.types.Object, arm: bpy.types.Object) -> None:
	for m in mesh.modifiers:
		if m.type == "ARMATURE":
			m.object = arm
			m.use_vertex_groups = True
			return
	mod = mesh.modifiers.new(name="Armature", type="ARMATURE")
	mod.object = arm
	mod.use_vertex_groups = True


def _limit_influences(mesh: bpy.types.Object, max_w: int = 4) -> None:
	"""Keep glTF-friendly ≤4 influences per vertex."""
	for v in mesh.data.vertices:
		groups = [(vg.group, vg.weight) for vg in v.groups if vg.weight > 1e-5]
		if len(groups) <= max_w:
			continue
		groups.sort(key=lambda t: t[1], reverse=True)
		keep = {g for g, _ in groups[:max_w]}
		total = sum(w for g, w in groups if g in keep) or 1.0
		for g_idx, w in groups:
			name = mesh.vertex_groups[g_idx].name
			if g_idx in keep:
				mesh.vertex_groups[name].add([v.index], w / total, "REPLACE")
			else:
				mesh.vertex_groups[name].add([v.index], 0.0, "REPLACE")


def process(in_path: Path, out_path: Path) -> None:
	_clear_scene()
	bpy.ops.import_scene.gltf(filepath=str(in_path))
	arm = _find_armature()
	meshes = _find_skinned_meshes(arm)
	print(f"armature={arm.name} meshes={[m.name for m in meshes]}")
	_fix_leaf_bone_tails(arm)
	_strip_existing_fingers(arm)

	mesh = meshes[0]
	frames = {}
	for side in ("Left", "Right"):
		frames[side] = _hand_frame_local(arm, mesh, f"{side}Hand")
		origin, finger, across, up, length = frames[side]
		print(
			f"{side} length={length:.2f} finger={tuple(round(c, 3) for c in finger)} "
			f"across={tuple(round(c, 3) for c in across)}"
		)
		created = _add_finger_bones(arm, side, origin, finger, across, up, length)
		print(f"{side} created={len(created)}")

	total = 0
	for mesh in meshes:
		_ensure_armature_modifier(mesh, arm)
		for side in ("Left", "Right"):
			origin, finger, across, up, length = frames[side]
			n = _weight_fingers(arm, mesh, side, origin, finger, across, up, length)
			total += n
			print(f"{mesh.name} {side} weighted_verts={n}")
		_limit_influences(mesh, 4)
	print(f"total_weighted={total}")

	# Validate bone lengths.
	for b in arm.data.bones:
		if any(k in b.name for k in ("Thumb", "Index", "Middle", "Ring", "Little")):
			blen = (b.tail_local - b.head_local).length
			if blen > 100.0 or blen < 0.5:
				raise RuntimeError(f"bad finger bone length {b.name}={blen:.2f}")

	bone_count = len(arm.data.bones)
	finger_count = sum(
		1
		for b in arm.data.bones
		if any(k in b.name for k in ("Thumb", "Index", "Middle", "Ring", "Little"))
	)
	print(f"bone_count={bone_count} finger_bones={finger_count}")
	if finger_count < 30:
		raise RuntimeError(f"expected 30 finger bones, got {finger_count}")
	if total < 50:
		raise RuntimeError(f"finger skinning assigned too few verts: {total}")

	out_path.parent.mkdir(parents=True, exist_ok=True)
	bak = out_path.with_suffix(out_path.suffix + ".nofingers.bak")
	# Preserve original backup only once.
	if not bak.exists() and in_path.exists() and "nofingers.bak" not in str(in_path):
		bak.write_bytes(in_path.read_bytes())
		print(f"backup={bak}")

	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(
		filepath=str(out_path),
		export_format="GLB",
		use_selection=False,
		export_animations=True,
		export_skins=True,
		export_morph=True,
		export_apply=False,
	)
	print(f"wrote={out_path}")


def main() -> None:
	args = _parse_args(sys.argv)
	in_path = Path(args.in_path)
	bak = in_path.with_suffix(in_path.suffix + ".nofingers.bak")
	src = bak if bak.exists() else in_path
	print(f"source={src}")
	process(src, Path(args.out_path))


if __name__ == "__main__":
	main()
