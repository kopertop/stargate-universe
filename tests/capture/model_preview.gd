extends SceneTree

# Quick model lineup: instances a set of character GLBs side by side (with the
# shared Kenney colormap) and screenshots them, so we can pick/tweak base models.
# Run NON-headless:
#   godot --quit-after 600 -s res://tests/capture/model_preview.gd

const COLORMAP: String = "res://models/characters/Textures/colormap.png"
# The shipped crew roster — a lineup viewer for tweaking base models.
const MODELS: Array[String] = [
	"res://models/characters/eli.glb",
	"res://models/characters/rush.glb",
	"res://models/characters/scott.glb",
	"res://models/characters/park.glb",
	"res://models/characters/james.glb",
	"res://models/characters/chloe.glb",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.7)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.2
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	world.add_child(sun)

	var tex: Texture2D = load(COLORMAP)
	var x: float = 0.0
	for path in MODELS:
		var holder := Node3D.new()
		holder.position = Vector3(x, 0.0, 0.0)
		holder.scale = Vector3(2.6, 2.6, 2.6)
		world.add_child(holder)
		var packed := load(path) as PackedScene
		if packed != null:
			var inst := packed.instantiate()
			holder.add_child(inst)
			_colormap(inst, tex)
		var tag := Label3D.new()
		tag.text = path.get_file().replace(".glb", "")
		tag.position = Vector3(x, 1.6, 0.0)
		tag.pixel_size = 0.01
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(tag)
		x += 1.6

	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.global_position = Vector3((x - 1.6) * 0.5, 2.2, 6.5)
	cam.look_at(Vector3((x - 1.6) * 0.5, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://model_lineup.png")
	print("[preview] saved abs=%s" % ProjectSettings.globalize_path("user://model_lineup.png"))
	quit()


func _colormap(root_node: Node, tex: Texture2D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)
