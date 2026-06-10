extends SceneTree

# Quaternius modular-outfit experiment: assemble characters IN CODE from the
# Universal Base + Modular Outfit parts (all BoneMap-retargeted to humanoid
# names), drive them with OUR shared Mixamo crew_body AnimationLibrary, and
# mount our rifle on the RightHand bone. Columns:
#   1. bare base (walk)   2. full Ranger assembled (walk)
#   3. MIXED Ranger top + Peasant legs (rifle_aim + rifle in hands)
# Run NON-headless:
#   godot --quit-after 900 -s res://tests/capture/quaternius_assembly.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const BASE: String = "res://models/quaternius/base/Superhero_Male_FullBody.gltf"
const PARTS_DIR: String = "res://models/quaternius/parts"

const LOOKS: Array = [
	["bare base", "body/walk", []],
	["ranger (assembled)", "body/walk",
		["Male_Ranger_Body", "Male_Ranger_Legs", "Male_Ranger_Feet_Boots", "Male_Ranger_Head_Hood"]],
	["ranger top + peasant legs", "body/rifle_aim",
		["Male_Ranger_Body", "Male_Peasant_Legs", "Male_Ranger_Feet_Boots"]],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1380, 800)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.21)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.05
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.45, 0.0)
	sun.light_energy = 1.1
	world.add_child(sun)

	var lib: AnimationLibrary = load("res://models/vrm/anim/crew_body.res")
	for i in range(LOOKS.size()):
		var look: Array = LOOKS[i]
		var inst: Node3D = (load(BASE) as PackedScene).instantiate()
		inst.position = Vector3(i * 1.5 - 1.5, 0.0, 0.0)
		inst.rotation.y = 0.35
		world.add_child(inst)
		var skel: Skeleton3D = inst.get_node_or_null("%GeneralSkeleton")
		if skel == null:
			skel = _find_skeleton(inst)
		# Assemble outfit parts onto the base skeleton (binds match by name).
		for part_name in look[2]:
			var part_scene: PackedScene = load("%s/%s.gltf" % [PARTS_DIR, part_name])
			if part_scene == null:
				print("[asm] missing part %s" % part_name)
				continue
			var part: Node = part_scene.instantiate()
			for mi in _skinned_meshes(part):
				var worn: MeshInstance3D = mi.duplicate() as MeshInstance3D
				skel.add_child(worn)
			part.free()
		# Drive with OUR Mixamo library via a fresh AnimationPlayer.
		var ap: AnimationPlayer = AnimationPlayer.new()
		inst.add_child(ap)
		ap.root_node = ap.get_path_to(inst)
		ap.add_animation_library("body", lib)
		if ap.has_animation(look[1]):
			ap.play(look[1])
			ap.seek(ap.current_animation_length * 0.35, true)
			ap.pause()
		# Our rifle in his hands for the aim column.
		if String(look[1]).contains("aim") and skel != null:
			var mount: BoneAttachment3D = BoneAttachment3D.new()
			skel.add_child(mount)
			mount.bone_name = "RightHand"
			var rifle: Node3D = FactoryRef.build_rifle()
			rifle.position = Vector3(0.0, 0.08, -0.02)
			rifle.rotation = Vector3(1.57, 0.0, 0.0)
			mount.add_child(rifle)
		var tag: Label3D = Label3D.new()
		tag.text = look[0]
		tag.position = Vector3(inst.position.x, 2.05, 0.0)
		tag.pixel_size = 0.0032
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.position = Vector3(0.0, 1.2, 4.6)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://quaternius_assembly.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://quaternius_assembly.png"))
	quit()


func _skinned_meshes(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
