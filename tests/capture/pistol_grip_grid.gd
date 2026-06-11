extends SceneTree

# Candidate grid for the AIMED PISTOL mount: one character per rotation
# candidate, frozen in the pistol_aim pose with Gun_Pistol mounted on
# RightHand at that rotation. Pick the one whose barrel runs down the aim
# line — never reason about gun-model axes (rifle_grip_tune lesson).
#   godot --quit-after 600 -s res://tests/capture/pistol_grip_grid.gd

const ModularScript: Script = preload("res://scripts/modular_character.gd")
const PISTOL: String = "res://models/quaternius/guns/Gun_Pistol.gltf"

const CANDIDATES: Array = [
	Vector3(-1.57, 1.57, 3.14),    # original (user: points RIGHT)
	Vector3(-1.57, 0.0, 3.14),     # current (user: points UP)
	Vector3(-1.57, 3.14, 3.14),
	Vector3(-1.57, -1.57, 3.14),
	Vector3(-1.57, 1.57, 0.0),
	Vector3(0.0, 1.57, 3.14),
	Vector3(0.0, -1.57, 0.0),
	Vector3(1.57, 1.57, 3.14),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	world.add_child(env)
	env.environment = e

	for i in range(CANDIDATES.size()):
		var c: Node3D = ModularScript.create("Male")
		c.position = Vector3(float(i) * 1.6 - float(CANDIDATES.size() - 1) * 0.8, 0.0, 0.0)
		c.rotation.y = PI * 0.5   # profile — extended arms cross the frame
		world.add_child(c)
		c.call("set_slot", "Body", "Male_Ranger_Body")
		c.call("freeze_clip_at", "pistol_aim", 0.3)
		var skel: Skeleton3D = c.call("skeleton")
		var mount: BoneAttachment3D = BoneAttachment3D.new()
		skel.add_child(mount)
		mount.bone_name = "RightHand"
		var gun: Node3D = Node3D.new()
		gun.position = Vector3(0.0, 0.06, 0.02)
		gun.rotation = CANDIDATES[i]
		mount.add_child(gun)
		gun.add_child((load(PISTOL) as PackedScene).instantiate())
		var tag: Label3D = Label3D.new()
		tag.text = "%d\n(%.2f, %.2f, %.2f)" % [i, CANDIDATES[i].x, CANDIDATES[i].y, CANDIDATES[i].z]
		tag.pixel_size = 0.0035
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 2.1, 0)
		c.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.45, 8.5)
	cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	cam.current = true
	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("user://pistol_grid.png")
	print("[grid] %s" % ProjectSettings.globalize_path("user://pistol_grid.png"))
	quit()
