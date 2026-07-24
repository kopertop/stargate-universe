"""Build Mixamo combat pack with a procedural Mixamo-span M4 proxy.

Mixamo does not ship a rifle mesh. Rifle Idle palm span ≈ 32.2cm.
This builds a simple M4-shaped proxy whose grip→support is locked to that
span, so both palms land on real mesh landmarks by construction.

Local-only host outputs (Mixamo ToS, gitignored):
  models/mixamo_openbot/Swat_rifle_combat.glb   (--host swat, default)
  models/mixamo_openbot/YBot_rifle_combat.glb   (--host ybot)
Also writes: models/mixamo_openbot/mixamo_virtual_rifle.glb (CC0 procedural)

Usage:
  blender -b -P tools/blender_mixamo_rifle_combat.py
  blender -b -P tools/blender_mixamo_rifle_combat.py -- --host ybot
  MIXAMO_COMBAT_HOST=ybot blender -b -P tools/blender_mixamo_rifle_combat.py
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
IN = ROOT / "models/mixamo_openbot/incoming"
OUT_DIR = ROOT / "models/mixamo_openbot"
PROXY_GLB = OUT_DIR / "mixamo_virtual_rifle.glb"


@dataclass(frozen=True)
class HostPreset:
	key: str
	fbx: Path
	scene_name: str
	glb_out: Path
	blend_out: Path
	shot_dir: Path


HOST_PRESETS: dict[str, HostPreset] = {
	"swat": HostPreset(
		key="swat",
		fbx=IN / "Swat.fbx",
		scene_name="Swat",
		glb_out=OUT_DIR / "Swat_rifle_combat.glb",
		blend_out=OUT_DIR / "Swat_rifle_combat.blend",
		shot_dir=ROOT / "screenshots/result/mint_rifle_aim",
	),
	"ybot": HostPreset(
		key="ybot",
		fbx=IN / "Y Bot.fbx",
		scene_name="YBot",
		glb_out=OUT_DIR / "YBot_rifle_combat.glb",
		blend_out=OUT_DIR / "YBot_rifle_combat.blend",
		shot_dir=ROOT / "screenshots/result/mint_rifle_aim/ybot",
	),
}


def _resolve_host() -> HostPreset:
	key = os.environ.get("MIXAMO_COMBAT_HOST", "swat").strip().lower()
	for i, arg in enumerate(sys.argv):
		if arg == "--host" and i + 1 < len(sys.argv):
			key = sys.argv[i + 1].strip().lower()
			break
		if arg.startswith("--host="):
			key = arg.split("=", 1)[1].strip().lower()
			break
	if key not in HOST_PRESETS:
		raise SystemExit(f"unknown MIXAMO_COMBAT_HOST {key!r}; choose: {', '.join(HOST_PRESETS)}")
	return HOST_PRESETS[key]


HOST = _resolve_host()
HOST_FBX = HOST.fbx
GLB_OUT = HOST.glb_out
BLEND_OUT = HOST.blend_out
SHOT_DIR = HOST.shot_dir

# Measured on Swat + Rifle Idle mid-frame (see blender_measure_mixamo_hand_span.py).
MIXAMO_HAND_SPAN = 0.322

CLIPS: dict[str, Path] = {
	# Default showcase idle: natural arms + Blender-authored rifle_holster on Spine2.
	"Unarmed_Idle": IN / "Unarmed Idle 01.fbx",
	"Breathing_Idle": IN / "Breathing Idle.fbx",
	"Walking": IN / "Walking.fbx",
	"Running": IN / "Running.fbx",
	"Strafe": IN / "Strafe.fbx",
	"Strafe_Alt": IN / "Strafe_Alt.fbx",
	"Rifle_Idle": IN / "Rifle Idle.fbx",
	"Firing_Rifle": IN / "Firing Rifle.fbx",
	# Standing / moving fire — preferred over Walk_With_Rifle for aim+move.
	"Shoot_Rifle": IN / "Shoot Rifle.fbx",
	"Walk_With_Rifle": IN / "Walk With Rifle.fbx",
	"Rifle_Start_Run": IN / "Rifle Start Run.fbx",
	"Fire_Rifle_Crouched": IN / "Fire Rifle While Crouched.fbx",
	"Rifle_Kneeling_Aim": IN / "Rifle Aiming And Kneeling.fbx",
	"Rifle_Stand_To_Kneel": IN / "Rifle Standing To Kneeling.fbx",
	"Rifle_Crouched_Idle_Aim": IN / "Rifle Crouched Idle Aiming.fbx",
	# Y Bot tool-use (unarmed; holster rifle before play).
	"Digging": IN / "Digging.fbx",
	"Working_On_Device": IN / "Working On Device.fbx",
}

# Local +Y = barrel toward muzzle. Grip→support Y = MIXAMO_HAND_SPAN.
GRIP_LOCAL = Vector((0.0, 0.0, -0.035))
SUPPORT_LOCAL = Vector((0.0, MIXAMO_HAND_SPAN, -0.020))
MUZZLE_LOCAL = Vector((0.0, 0.55, 0.03))
STOCK_LOCAL = Vector((0.0, -0.28, 0.04))


def _purge() -> None:
	if bpy.context.object and bpy.context.object.mode != "OBJECT":
		bpy.ops.object.mode_set(mode="OBJECT")
	for obj in list(bpy.data.objects):
		if obj.type not in {"CAMERA", "LIGHT"}:
			bpy.data.objects.remove(obj, do_unlink=True)
	for act in list(bpy.data.actions):
		bpy.data.actions.remove(act)
	for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
		for item in list(block):
			if item.users == 0:
				block.remove(item)


def _strip_scale_fcurves(action: bpy.types.Action) -> int:
	removed = 0
	for layer in action.layers:
		for strip in layer.strips:
			for cb in strip.channelbags:
				for fc in list(cb.fcurves):
					if fc.data_path.endswith(".scale"):
						cb.fcurves.remove(fc)
						removed += 1
	return removed


def _strip_hip_location(action: bpy.types.Action) -> int:
	removed = 0
	for layer in action.layers:
		for strip in layer.strips:
			for cb in strip.channelbags:
				for fc in list(cb.fcurves):
					dp = fc.data_path
					if "Hips" in dp and "location" in dp:
						cb.fcurves.remove(fc)
						removed += 1
	return removed


def _disable_inherit_scale(arm: bpy.types.Object) -> None:
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.mode_set(mode="EDIT")
	for b in arm.data.edit_bones:
		if hasattr(b, "inherit_scale"):
			b.inherit_scale = "NONE"
	bpy.ops.object.mode_set(mode="POSE")


def _bind_action(arm: bpy.types.Object, action: bpy.types.Action) -> None:
	if arm.animation_data is None:
		arm.animation_data_create()
	ad = arm.animation_data
	ad.action = action
	if hasattr(ad, "action_slot") and action.slots:
		ad.action_slot = action.slots[0]


def _world_bone(arm: bpy.types.Object, name: str) -> Matrix:
	return arm.matrix_world @ arm.pose.bones[name].matrix


def _palm(arm: bpy.types.Object, side: str) -> Vector:
	wrist = _world_bone(arm, f"mixamorig:{side}Hand").translation
	tips: list[Vector] = []
	for finger in ("Thumb4", "Index4", "Middle4"):
		n = f"mixamorig:{side}Hand{finger}"
		if n in arm.pose.bones:
			tips.append(_world_bone(arm, n).translation)
	if not tips:
		return wrist
	return wrist.lerp(sum(tips, Vector()) / len(tips), 0.65)


def _foot_z_min(arm: bpy.types.Object) -> float:
	zmin = 1e9
	for name in arm.pose.bones.keys():
		if "Toe" in name or name.endswith("Foot"):
			zmin = min(zmin, _world_bone(arm, name).translation.z)
	return zmin


def _ground_across_clips(arm: bpy.types.Object, actions: dict[str, bpy.types.Action]) -> None:
	worst = 0.0
	for name, act in actions.items():
		_bind_action(arm, act)
		mid = int((act.frame_range[0] + act.frame_range[1]) // 2)
		bpy.context.scene.frame_set(mid)
		bpy.context.view_layer.update()
		z = _foot_z_min(arm)
		worst = min(worst, z)
		print(f"  footZ {name:28} {z:.4f}")
	arm.location.z -= worst - 0.01
	bpy.context.view_layer.update()
	print("grounded; worst was", round(worst, 4), "host.z", round(arm.location.z, 4))


def _import_clip_action(path: Path, name: str) -> bpy.types.Action | None:
	if not path.exists():
		print("SKIP missing", path)
		return None
	before_arms = {o.name for o in bpy.data.objects if o.type == "ARMATURE"}
	before_actions = {a.name for a in bpy.data.actions}
	bpy.ops.import_scene.fbx(filepath=str(path), automatic_bone_orientation=True)
	for o in list(bpy.data.objects):
		if o.type == "ARMATURE" and o.name not in before_arms:
			bpy.data.objects.remove(o, do_unlink=True)
	new_actions = [a for a in bpy.data.actions if a.name not in before_actions]
	if not new_actions:
		print("SKIP no action", path.name)
		return None
	act = next((a for a in new_actions if "Layer0" in a.name), None)
	if act is None:
		act = max(new_actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
	for a in new_actions:
		if a != act:
			bpy.data.actions.remove(a)
	act.name = name
	_strip_scale_fcurves(act)
	if name in (
		"Walk_With_Rifle",
		"Rifle_Start_Run",
		"Walking",
		"Running",
		"Shoot_Rifle",
		"Strafe",
		"Strafe_Alt",
		"Fire_Rifle_Crouched",
		"Firing_Rifle",
		"Rifle_Crouched_Idle_Aim",
		"Rifle_Kneeling_Aim",
		"Rifle_Stand_To_Kneel",
		"Rifle_Idle",
	):
		print("stripped hip loc", name, _strip_hip_location(act))
	print("CLIP", name, "frames", tuple(act.frame_range))
	return act


def _make_mat(name: str, color: tuple[float, float, float]) -> bpy.types.Material:
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nodes = mat.node_tree.nodes
	links = mat.node_tree.links
	nodes.clear()
	bsdf = nodes.new("ShaderNodeBsdfPrincipled")
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Metallic"].default_value = 0.65
	bsdf.inputs["Roughness"].default_value = 0.42
	out = nodes.new("ShaderNodeOutputMaterial")
	links.new(bsdf.outputs[0], out.inputs[0])
	return mat


def _box(name: str, size: Vector, loc: Vector, mat: bpy.types.Material) -> bpy.types.Object:
	# size=2 cube spans 2 units; scale by half-extents so `size` is full XYZ size.
	bpy.ops.mesh.primitive_cube_add(size=2.0, location=loc)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size * 0.5
	bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
	obj.data.materials.append(mat)
	return obj


def _build_mixamo_proxy_rifle() -> bpy.types.Object:
	"""Simple M4 silhouette; landmarks locked to Mixamo palm span."""
	body_mat = _make_mat("ProxyRifleBody", (0.12, 0.13, 0.14))
	dark_mat = _make_mat("ProxyRifleDark", (0.05, 0.055, 0.06))
	parts: list[bpy.types.Object] = []

	parts.append(_box("recv", Vector((0.045, 0.28, 0.07)), Vector((0.0, 0.10, 0.02)), body_mat))
	parts.append(
		_box(
			"guard",
			Vector((0.04, 0.18, 0.05)),
			Vector((0.0, MIXAMO_HAND_SPAN, 0.02)),
			dark_mat,
		)
	)
	parts.append(_box("barrel", Vector((0.018, 0.28, 0.018)), Vector((0.0, 0.42, 0.03)), dark_mat))
	parts.append(_box("stock", Vector((0.035, 0.22, 0.06)), Vector((0.0, -0.18, 0.03)), dark_mat))
	parts.append(_box("stock_pad", Vector((0.05, 0.04, 0.09)), Vector((0.0, -0.28, 0.04)), dark_mat))
	parts.append(_box("grip", Vector((0.028, 0.04, 0.11)), GRIP_LOCAL + Vector((0.0, 0.0, -0.02)), dark_mat))
	parts.append(_box("mag", Vector((0.025, 0.05, 0.12)), Vector((0.0, 0.06, -0.08)), dark_mat))
	parts.append(_box("optic", Vector((0.03, 0.12, 0.035)), Vector((0.0, 0.08, 0.08)), body_mat))

	bpy.ops.object.select_all(action="DESELECT")
	for p in parts:
		p.select_set(True)
	bpy.context.view_layer.objects.active = parts[0]
	bpy.ops.object.join()
	rifle = bpy.context.active_object
	rifle.name = "rifle"
	rifle.location = (0.0, 0.0, 0.0)
	bpy.context.view_layer.update()

	sep = (SUPPORT_LOCAL - GRIP_LOCAL).length
	print(
		"proxy span", round(sep, 4),
		"(target Y", MIXAMO_HAND_SPAN, ")",
		"dims", tuple(round(c, 3) for c in rifle.dimensions),
	)
	if abs(sep - MIXAMO_HAND_SPAN) > 0.02:
		raise RuntimeError(f"proxy landmark span drifted: {sep}")

	for o in bpy.context.view_layer.objects:
		o.select_set(False)
	rifle.select_set(True)
	bpy.context.view_layer.objects.active = rifle
	bpy.ops.export_scene.gltf(
		filepath=str(PROXY_GLB),
		use_selection=True,
		export_animations=False,
	)
	print("WROTE proxy", PROXY_GLB)
	return rifle


def _seat_rifle(arm: bpy.types.Object, rifle: bpy.types.Object) -> None:
	rh = _palm(arm, "Right")
	lh = _palm(arm, "Left")
	mesh_forward = (MUZZLE_LOCAL - GRIP_LOCAL).normalized()
	hand_aim = (lh - rh).normalized()
	up = Vector((0.0, 0.0, 1.0))

	x = up.cross(hand_aim)
	if x.length < 1e-5:
		x = Vector((1.0, 0.0, 0.0))
	x.normalize()
	z = x.cross(hand_aim).normalized()
	if z.dot(up) < 0.0:
		x = -x
		z = x.cross(hand_aim).normalized()
	world_basis = Matrix((x, hand_aim, z)).transposed().to_4x4()

	mx = up.cross(mesh_forward)
	if mx.length < 1e-5:
		mx = Vector((1.0, 0.0, 0.0))
	mx.normalize()
	# Cross order must keep mesh +Z (optic) as "up" — mx×forward yields -Z and flips the gun.
	mz = mesh_forward.cross(mx).normalized()
	if mz.dot(up) < 0.0:
		mx = -mx
		mz = -mz
	mesh_basis = Matrix((mx, mesh_forward, mz)).transposed().to_4x4()

	# Proxy is authored at Mixamo span — scale should be ~1.
	local_sep = (SUPPORT_LOCAL - GRIP_LOCAL).length
	hand_sep = (lh - rh).length
	scale = hand_sep / max(local_sep, 1e-6)
	print("hand_sep", round(hand_sep, 4), "scale", round(scale, 4))

	R = world_basis @ mesh_basis.inverted()
	origin = rh - R.to_3x3() @ (GRIP_LOCAL * scale)
	mw = Matrix.Translation(origin) @ R @ Matrix.Scale(scale, 4)

	rifle.constraints.clear()
	rifle.parent = None
	rifle.matrix_world = mw
	bpy.context.view_layer.update()
	rifle.matrix_world = mw
	bpy.context.view_layer.update()

	grip_err = (rifle.matrix_world @ GRIP_LOCAL - rh).length
	sup_err = (rifle.matrix_world @ SUPPORT_LOCAL - lh).length
	muz = rifle.matrix_world @ MUZZLE_LOCAL
	stock = rifle.matrix_world @ STOCK_LOCAL
	chest = _world_bone(arm, "mixamorig:Spine2").translation
	print(
		"seat grip_err", round(grip_err, 4),
		"sup_err", round(sup_err, 4),
		"dims", tuple(round(c, 3) for c in rifle.dimensions),
	)
	print(
		"orient stock_dist", round((stock - chest).length, 3),
		"muz_dist", round((muz - chest).length, 3),
	)
	if grip_err > 0.015:
		raise RuntimeError(f"grip seating failed: {grip_err}")
	if sup_err > 0.04:
		print("WARN support slip", round(sup_err, 4))
	if (muz - chest).length < (stock - chest).length:
		raise RuntimeError("rifle backwards")


def _mount_bone_parent(arm: bpy.types.Object, rifle: bpy.types.Object) -> None:
	con = rifle.constraints.new("CHILD_OF")
	con.target = arm
	con.subtarget = "mixamorig:RightHand"
	con.inverse_matrix = (arm.matrix_world @ arm.pose.bones["mixamorig:RightHand"].matrix).inverted()
	bpy.context.view_layer.update()
	mw = rifle.matrix_world.copy()
	rifle.constraints.clear()
	rifle.parent = arm
	rifle.parent_type = "BONE"
	rifle.parent_bone = "mixamorig:RightHand"
	bpy.context.view_layer.update()
	rifle.matrix_world = mw
	bpy.context.view_layer.update()
	rh = _palm(arm, "Right")
	print(
		"mounted grip_err",
		round((rifle.matrix_world @ GRIP_LOCAL - rh).length, 4),
		"sup_err",
		round((rifle.matrix_world @ SUPPORT_LOCAL - _palm(arm, "Left")).length, 4),
	)


def _author_rifle_holster(arm: bpy.types.Object, rifle_hand: bpy.types.Object) -> bpy.types.Object:
	"""Duplicate the hand rifle onto Spine2 for holstered visibility swap.

	Local transform baked from the signed-off Swat_rifle_combat.blend (2026-07-21).
	Mixamo bone-parent scale is quirky (-100); keep it so Godot matches the look.
	"""
	holster = rifle_hand.copy()
	holster.data = rifle_hand.data.copy()
	bpy.context.collection.objects.link(holster)
	holster.name = "rifle_holster"
	holster.constraints.clear()
	holster.parent = None
	bpy.context.view_layer.update()

	holster.parent = arm
	holster.parent_type = "BONE"
	holster.parent_bone = "mixamorig:Spine2"
	bpy.context.view_layer.update()
	# Signed-off back sling (user-authored in Blender, then captured).
	holster.location = Vector((-1.679, -4.9685, -20.9981))
	holster.rotation_euler = (-0.3379, 2.1146, -0.7889)
	holster.scale = Vector((-100.0, -100.0, -100.0))
	bpy.context.view_layer.update()
	print(
		"holster parent", holster.parent_bone,
		"loc", tuple(round(c, 3) for c in holster.location),
	)
	return holster


def _add_muzzle(rifle: bpy.types.Object) -> bpy.types.Object:
	existing = bpy.data.objects.get("Muzzle")
	if existing:
		bpy.data.objects.remove(existing, do_unlink=True)
	bpy.ops.object.empty_add(type="PLAIN_AXES")
	muzzle = bpy.context.active_object
	muzzle.name = "Muzzle"
	muzzle.empty_display_size = 0.04
	muzzle.parent = rifle
	muzzle.matrix_parent_inverse.identity()
	muzzle.location = MUZZLE_LOCAL.copy()
	bpy.context.view_layer.update()
	print("Muzzle world", tuple(round(c, 3) for c in muzzle.matrix_world.translation))
	return muzzle


def _ensure_lights() -> None:
	if not any(o.type == "LIGHT" for o in bpy.data.objects):
		bpy.ops.object.light_add(type="SUN", location=(3, -2, 6))
		bpy.context.active_object.data.energy = 3.5
	if bpy.context.scene.camera is None:
		bpy.ops.object.camera_add()
		bpy.context.scene.camera = bpy.context.active_object


def _render(arm: bpy.types.Object, tag: str, offset: Vector) -> None:
	_ensure_lights()
	cam = bpy.context.scene.camera
	chest = _world_bone(arm, "mixamorig:Spine2").translation
	cam.location = chest + offset
	cam.rotation_euler = (chest - cam.location).to_track_quat("-Z", "Y").to_euler()
	arm.hide_render = True
	path = str(SHOT_DIR / f"combat_proxy_{tag}.png")
	scene = bpy.context.scene
	scene.render.filepath = path
	scene.render.resolution_x = 1400
	scene.render.resolution_y = 1000
	bpy.ops.render.render(write_still=True)
	print("WROTE", path)


def run() -> None:
	if not HOST_FBX.exists():
		raise FileNotFoundError(f"missing host FBX: {HOST_FBX} (drop Mixamo export into incoming/)")
	print("HOST", HOST.key, HOST_FBX.name, "->", GLB_OUT.name)
	_purge()
	SHOT_DIR.mkdir(parents=True, exist_ok=True)
	OUT_DIR.mkdir(parents=True, exist_ok=True)

	bpy.ops.import_scene.fbx(filepath=str(HOST_FBX), automatic_bone_orientation=True)
	host = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	host.name = HOST.scene_name
	meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	if host.animation_data:
		host.animation_data_clear()
	print("keeping Mixamo scale", tuple(host.scale))
	_disable_inherit_scale(host)

	actions: dict[str, bpy.types.Action] = {}
	for name, path in CLIPS.items():
		act = _import_clip_action(path, name)
		if act is not None:
			actions[name] = act
	if "Rifle_Idle" not in actions:
		raise RuntimeError("Rifle_Idle required")

	print("grounding across clips…")
	_ground_across_clips(host, actions)

	_bind_action(host, actions["Rifle_Idle"])
	mid = int((actions["Rifle_Idle"].frame_range[0] + actions["Rifle_Idle"].frame_range[1]) // 2)
	bpy.context.scene.frame_set(mid)
	bpy.context.view_layer.update()

	rifle = _build_mixamo_proxy_rifle()
	_seat_rifle(host, rifle)
	_mount_bone_parent(host, rifle)
	holster = _author_rifle_holster(host, rifle)
	muzzle = _add_muzzle(rifle)

	if host.animation_data is None:
		host.animation_data_create()
	while host.animation_data.nla_tracks:
		host.animation_data.nla_tracks.remove(host.animation_data.nla_tracks[0])
	for name, act in actions.items():
		track = host.animation_data.nla_tracks.new()
		track.name = name
		strip = track.strips.new(name, 1, act)
		strip.action = act

	for clip, offset in (
		("Rifle_Idle", Vector((1.5, -2.1, 0.35))),
		("Firing_Rifle", Vector((1.5, -2.1, 0.35))),
		("Walk_With_Rifle", Vector((1.8, -2.4, 0.4))),
		("Fire_Rifle_Crouched", Vector((1.4, -2.0, 0.25))),
		("Rifle_Kneeling_Aim", Vector((1.5, -2.1, 0.2))),
	):
		if clip not in actions:
			continue
		_bind_action(host, actions[clip])
		m = int((actions[clip].frame_range[0] + actions[clip].frame_range[1]) // 2)
		bpy.context.scene.frame_set(m)
		bpy.context.view_layer.update()
		z = _foot_z_min(host)
		rh = _palm(host, "Right")
		lh = _palm(host, "Left")
		gerr = (rifle.matrix_world @ GRIP_LOCAL - rh).length
		serr = (rifle.matrix_world @ SUPPORT_LOCAL - lh).length
		print(f"VALIDATE {clip:28} grip={gerr:.3f} sup={serr:.3f} footZ={z:.3f}")
		_render(host, clip.lower(), offset)

	_bind_action(host, actions["Rifle_Idle"])
	bpy.context.scene.frame_set(mid)
	bpy.context.view_layer.update()

	bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
	for o in bpy.context.view_layer.objects:
		o.select_set(False)
	host.select_set(True)
	for m in meshes:
		m.select_set(True)
	rifle.select_set(True)
	holster.select_set(True)
	muzzle.select_set(True)
	bpy.context.view_layer.objects.active = host
	bpy.ops.export_scene.gltf(
		filepath=str(GLB_OUT),
		use_selection=True,
		export_animations=True,
		export_animation_mode="NLA_TRACKS",
		export_nla_strips=True,
		export_def_bones=True,
		export_rest_position_armature=True,
		export_extras=True,
	)
	print("EXPORTED", GLB_OUT)


if __name__ == "__main__":
	run()
