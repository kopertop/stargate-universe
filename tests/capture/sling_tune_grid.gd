extends SceneTree

# Karpathy-loop tuning grid for the SLUNG rifle mount (Chest bone): one
# character per candidate transform, rendered from BACK and FRONT, compared
# against the user's reference chart (vertical-diagonal on the back, barrel
# UP behind the shoulder, stock at the hip, tight to the back).
#   godot --quit-after 900 -s res://tests/capture/sling_tune_grid.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")
const RIFLE: String = "res://models/quaternius/guns/Gun_Rifle.gltf"

# [label, position, rotation]
# Round 3: B/F (Rz -1.57 family = barrel up the back) won round 2 but rode
# too high — drop the mount so the muzzle just clears the shoulder, try both
# tilt directions + a tuck toward the back.
const CANDIDATES: Array = [
	["B1", Vector3(-0.04, -0.08, -0.17), Vector3(0.0, 0.0, -1.57)],
	["B2", Vector3(-0.04, -0.16, -0.17), Vector3(0.0, 0.0, -1.57)],
	["B3", Vector3(-0.04, -0.12, -0.20), Vector3(0.0, 0.0, -1.57)],
	["F1", Vector3(-0.04, -0.08, -0.17), Vector3(0.25, 0.0, -1.35)],
	["F2", Vector3(-0.04, -0.16, -0.17), Vector3(0.25, 0.0, -1.35)],
	["F3", Vector3(-0.04, -0.12, -0.20), Vector3(0.15, 0.0, -1.45)],
	["F4", Vector3(-0.04, -0.12, -0.17), Vector3(-0.25, 0.0, -1.35)],
	["F5", Vector3(-0.04, -0.12, -0.17), Vector3(0.25, 0.5, -1.35)],
]

var _world: Node3D = null
var _bodies: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	_world.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.72, 0.78)
	_world.add_child(env)
	env.environment = e

	for i in range(CANDIDATES.size()):
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(float(i) * 1.6 - float(CANDIDATES.size() - 1) * 0.8, 0.0, 0.0)
		c.rotation.y = -PI * 0.25   # back three-quarter first
		_world.add_child(c)
		c.call("set_slot", "Body", "Male_Ranger_Body")
		c.call("set_slot", "Legs", "Male_Ranger_Legs")
		c.call("freeze_clip_at", "idle", 0.3)
		var skel: Skeleton3D = c.call("skeleton")
		var mount: BoneAttachment3D = BoneAttachment3D.new()
		skel.add_child(mount)
		mount.bone_name = "Chest"
		var gun: Node3D = Node3D.new()
		gun.position = CANDIDATES[i][1]
		gun.rotation = CANDIDATES[i][2]
		mount.add_child(gun)
		gun.add_child((load(RIFLE) as PackedScene).instantiate())
		var tag: Label3D = Label3D.new()
		tag.text = String(CANDIDATES[i][0])
		tag.pixel_size = 0.005
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.15, 0)
		c.add_child(tag)
		_bodies.append(c)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	_world.add_child(cam)
	cam.position = Vector3(0.0, 1.4, 9.2)
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	cam.current = true
	await _settle(14)
	await _shot("user://sling_back.png")
	for c in _bodies:
		(c as Node3D).rotation.y = PI * 0.75
	await _settle(8)
	await _shot("user://sling_front.png")
	print("=== done ===")
	quit()


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[shot] %s" % ProjectSettings.globalize_path(path))
