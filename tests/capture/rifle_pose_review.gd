extends SceneTree

# Visual review grid for the Quaternius Gun_Rifle on the modular rig: one
# character per (mount, clip) state, rendered from FRONT and BACK so both
# the aimed hand mount and the back sling can be eyeballed in every pose.
#   godot --quit-after 900 -s res://tests/capture/rifle_pose_review.gd
# Output: user://rifle_poses_front.png / user://rifle_poses_back.png

const ModularScript: Script = preload("res://scripts/modular_character.gd")

# [label, aimed, clip, fraction]
const STATES: Array = [
	["slung idle", false, "idle", 0.3],
	["slung walk", false, "walk", 0.4],
	["slung run", false, "run", 0.4],
	["drawing", false, "rifle_draw", 0.6],
	["aimed", true, "rifle_aim", 0.5],
	["aim walk-fire", true, "rifle_fire_walk", 0.4],
	["aim run", true, "rifle_run_aim", 0.4],
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

	for i in range(STATES.size()):
		var s: Array = STATES[i]
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(float(i) * 1.7 - float(STATES.size() - 1) * 0.85, 0.0, 0.0)
		c.rotation.y = PI * 0.75   # front three-quarter
		_world.add_child(c)
		c.call("set_slot", "Body", "Male_Ranger_Body")
		c.call("set_slot", "Legs", "Male_Ranger_Legs")
		c.call("set_rifle", true, bool(s[1]))
		c.call("freeze_clip_at", String(s[2]), float(s[3]))
		var tag: Label3D = Label3D.new()
		tag.text = String(s[0])
		tag.pixel_size = 0.004
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.15, 0)
		c.add_child(tag)
		_bodies.append(c)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	_world.add_child(cam)
	cam.position = Vector3(0.0, 1.4, 9.0)
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	cam.current = true
	await _settle(14)
	await _shot("user://rifle_poses_front.png")

	# Back view: spin the figures so the sling/back mount reads.
	for c in _bodies:
		(c as Node3D).rotation.y = -PI * 0.25
	await _settle(8)
	await _shot("user://rifle_poses_back.png")
	print("=== done ===")
	quit()


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] %s" % ProjectSettings.globalize_path(path))
