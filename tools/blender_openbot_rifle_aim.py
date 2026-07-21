"""NEGATIVE EXAMPLE — do not use as the rifle-aim source of truth.

See docs/animation/rifle-aim-host-pipeline.md.

Correct path: Mixamo Y-Bot + Rifle Idle → Child Of mount → Godot BoneMap.
This script's world-matrix / euler probing on OpenBot tore meshes and never
produced a shippable shouldered hold. Kept only so agents can read the failure
modes; prefer deleting call sites over extending this file.
"""
from __future__ import annotations

import bpy
from math import radians
from mathutils import Matrix, Quaternion, Vector


OUT = "/Users/cmoyer/Projects/personal/stargate-universe/screenshots/result/mint_rifle_aim/openbot_blender_aim.png"
SIDE_OUT = "/Users/cmoyer/Projects/personal/stargate-universe/screenshots/result/mint_rifle_aim/openbot_blender_aim_side.png"
BLEND_OUT = "/Users/cmoyer/Projects/personal/stargate-universe/models/mixamo_openbot/OpenBot_rifle_aim.blend"
GLB_OUT = "/Users/cmoyer/Projects/personal/stargate-universe/models/mixamo_openbot/OpenBot_rifle_aim.glb"

BOT_PATH = "/Users/cmoyer/Projects/personal/stargate-universe/models/mixamo_openbot/OpenBot.glb"
RIFLE_PATH = "/Users/cmoyer/Projects/personal/stargate-universe/models/mint/props/rifle.glb"

FWD = Vector((0.0, -1.0, 0.0))
UP = Vector((0.0, 0.0, 1.0))
RIGHT = Vector((-1.0, 0.0, 0.0))

# Rifle local landmarks (mesh vertex clusters)
STOCK_LOCAL = Vector((-0.007, -0.477, 0.081))
GRIP_LOCAL = Vector((0.003, -0.092, 0.131))
SUPPORT_LOCAL = Vector((0.004, 0.220, 0.020))
RIFLE_SCALE = 0.50

# Degrees, applied as quaternion deltas on current (rest) pose — NOT absolute eulers.
POSE_DELTAS: dict[str, tuple[float, float, float]] = {
	"spine": (6.0, 0.0, -8.0),
	"spine.001": (4.0, 0.0, -5.0),
	"spine.002": (3.0, 0.0, -3.0),
	"chest": (4.0, 0.0, -6.0),
	"shoulder.R": (6.0, -10.0, -16.0),
	"upper_arm.R": (-28.0, -12.0, -38.0),
	"forearm.R": (-48.0, 4.0, -6.0),
	"hand.R": (8.0, -12.0, -10.0),
	"shoulder.L": (5.0, 10.0, 14.0),
	"upper_arm.L": (-22.0, 16.0, 32.0),
	"forearm.L": (-52.0, -4.0, 8.0),
	"hand.L": (4.0, 10.0, 12.0),
	"neck": (10.0, 0.0, -4.0),
	"head": (12.0, 0.0, -4.0),
	"thigh.R": (-4.0, 3.0, 0.0),
	"thigh.L": (-3.0, -4.0, 0.0),
}


def _purge_scene() -> None:
	bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
	for obj in list(bpy.data.objects):
		if obj.type not in {"CAMERA", "LIGHT"}:
			bpy.data.objects.remove(obj, do_unlink=True)
	for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials):
		for item in list(block):
			if item.users == 0:
				block.remove(item)


def ensure_scene() -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object]:
	_purge_scene()
	bpy.ops.import_scene.gltf(filepath=BOT_PATH)
	rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	rig.name = "rig"
	mesh = next(o for o in bpy.data.objects if o.type == "MESH")
	mesh.name = "OpenBot"
	bpy.ops.import_scene.gltf(filepath=RIFLE_PATH)
	rifle = next(o for o in bpy.data.objects if o.type == "MESH" and o.name != "OpenBot")
	rifle.name = "rifle"
	rifle.parent = None
	if bpy.context.scene.camera is None:
		bpy.ops.object.camera_add()
		bpy.context.scene.camera = bpy.context.active_object
	return rig, mesh, rifle


def _reset_pose(rig: bpy.types.Object) -> None:
	if rig.animation_data:
		rig.animation_data_clear()
	bpy.context.view_layer.objects.active = rig
	bpy.ops.object.mode_set(mode="POSE")
	for pb in rig.pose.bones:
		pb.matrix_basis = Matrix.Identity(4)


def _apply_deltas(rig: bpy.types.Object) -> None:
	for name, (rx, ry, rz) in POSE_DELTAS.items():
		pb = rig.pose.bones.get(name)
		if pb is None:
			continue
		delta = Quaternion(Vector((1, 0, 0)), radians(rx))
		delta = Quaternion(Vector((0, 1, 0)), radians(ry)) @ delta
		delta = Quaternion(Vector((0, 0, 1)), radians(rz)) @ delta
		pb.matrix_basis = (delta.to_matrix().to_4x4() @ pb.matrix_basis)


def _curl_fingers(rig: bpy.types.Object) -> None:
	for side, curl in (("R", 0.55), ("L", 0.48)):
		axis = Vector((1.0, 0.0, 0.0))
		for finger in ("f_index", "f_middle", "f_ring", "f_pinky"):
			for i, mul in ((1, 0.7), (2, 1.0), (3, 0.95)):
				pb = rig.pose.bones.get(f"{finger}.{i:02d}.{side}")
				if pb is None:
					continue
				q = Quaternion(axis, curl * mul)
				pb.matrix_basis = q.to_matrix().to_4x4() @ pb.matrix_basis
		# Mild thumb opposition
		for i, ang in ((1, 0.35), (2, 0.4), (3, 0.35)):
			pb = rig.pose.bones.get(f"thumb.{i:02d}.{side}")
			if pb is None:
				continue
			flip = 1.0 if side == "R" else -1.0
			q = (
				Quaternion(Vector((0, 1, 0)), 0.4 * flip)
				@ Quaternion(Vector((1, 0, 0)), ang)
			)
			pb.matrix_basis = q.to_matrix().to_4x4() @ pb.matrix_basis


def _world_head(rig: bpy.types.Object, name: str) -> Vector:
	return (rig.matrix_world @ rig.pose.bones[name].matrix).translation


def _basis(x: Vector, y: Vector, z: Vector, origin: Vector) -> Matrix:
	rot = Matrix((x.normalized(), y.normalized(), z.normalized())).transposed().to_4x4()
	rot.translation = origin
	return rot


def _seat_rifle(rifle: bpy.types.Object, stock_w: Vector, aim: Vector) -> None:
	aim = aim.normalized()
	x = UP.cross(aim)
	if x.length < 1e-6:
		x = Vector((1.0, 0.0, 0.0))
	x.normalize()
	if x.dot(-RIGHT) < 0.0:
		x = -x
	z = x.cross(aim).normalized()
	if z.dot(UP) > 0.0:
		x = -x
		z = x.cross(aim).normalized()
	scaled_stock = STOCK_LOCAL * RIFLE_SCALE
	origin = stock_w - _basis(x, aim, z, Vector()).to_3x3() @ scaled_stock
	bpy.ops.object.mode_set(mode="OBJECT")
	rifle.matrix_world = _basis(x, aim, z, origin) @ Matrix.Scale(RIFLE_SCALE, 4)
	bpy.context.view_layer.update()


def _render(cam_offset: Vector, path: str, lens: float = 55.0) -> None:
	scene = bpy.context.scene
	cam = scene.camera
	rig = bpy.data.objects["rig"]
	rifle = bpy.data.objects["rifle"]
	target = rifle.matrix_world.translation
	cam.location = target + cam_offset
	cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
	cam.data.lens = lens
	rig.hide_render = True
	scene.render.engine = "BLENDER_EEVEE"
	scene.render.resolution_x = 1400
	scene.render.resolution_y = 1000
	scene.render.filepath = path
	bpy.ops.render.render(write_still=True)
	print("WROTE", path)


def run() -> None:
	rig, mesh, rifle = ensure_scene()
	_reset_pose(rig)
	bpy.context.view_layer.update()
	_apply_deltas(rig)
	_curl_fingers(rig)
	bpy.context.view_layer.update()

	hand_r = _world_head(rig, "hand.R")
	hand_l = _world_head(rig, "hand.L")
	shoulder_r = _world_head(rig, "shoulder.R")
	print("hand.R", hand_r, "hand.L", hand_l, "shoulder.R", shoulder_r)

	# Aim along character forward; stock into shoulder pocket near right shoulder.
	aim = (FWD + UP * 0.04).normalized()
	# Seat stock at shoulder, then slide so grip sits at right hand.
	stock_w = shoulder_r + FWD * 0.04 + RIGHT * 0.06 + UP * (-0.06)
	_seat_rifle(rifle, stock_w, aim)
	grip_w = rifle.matrix_world @ GRIP_LOCAL
	# Translate rifle so grip matches right hand (preserve orientation)
	delta = hand_r - grip_w
	# Bias: pull slightly into body so stock shoulders; lift to hand height
	delta += RIGHT * 0.02 + FWD * (-0.02)
	rifle.matrix_world = Matrix.Translation(delta) @ rifle.matrix_world
	bpy.context.view_layer.update()

	grip_w = rifle.matrix_world @ GRIP_LOCAL
	support_w = rifle.matrix_world @ SUPPORT_LOCAL
	stock_w = rifle.matrix_world @ STOCK_LOCAL
	print("seated stock", stock_w, "grip", grip_w, "support", support_w)
	print("grip→hand.R", (grip_w - hand_r).length, "support→hand.L", (support_w - hand_l).length)

	# Nudge left forearm toward support without matrix IK — small extra delta
	pb = rig.pose.bones.get("forearm.L")
	if pb is not None and (support_w - hand_l).length > 0.08:
		to_sup = (support_w - hand_l).normalized()
		# Mild reach
		q = Quaternion(Vector((1, 0, 0)), radians(-8.0))
		pb.matrix_basis = q.to_matrix().to_4x4() @ pb.matrix_basis
		bpy.context.view_layer.update()
		hand_l = _world_head(rig, "hand.L")
		print("hand.L after nudge", hand_l, "err", (support_w - hand_l).length)

	_render(Vector((1.6, -2.2, 0.35)), OUT, 55.0)
	_render(Vector((2.5, 0.0, 0.1)), SIDE_OUT, 50.0)

	bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
	print("SAVED", BLEND_OUT)

	for obj in bpy.context.view_layer.objects:
		obj.select_set(False)
	rig.select_set(True)
	mesh.select_set(True)
	rifle.select_set(True)
	bpy.context.view_layer.objects.active = rig
	bpy.ops.export_scene.gltf(
		filepath=GLB_OUT,
		use_selection=True,
		export_animations=False,
		export_def_bones=True,
		export_rest_position_armature=False,
	)
	print("EXPORTED", GLB_OUT)


if __name__ == "__main__":
	run()
