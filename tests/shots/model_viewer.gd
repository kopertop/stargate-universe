extends SceneTree

# Dev-only model viewer capture: renders a single GLB (with the Mini-Characters
# colormap) against a neutral ground and saves a PNG. Used to eyeball what a
# character rig ACTUALLY looks like, independent of any gameplay scene.
#
#   xvfb-run godot --rendering-driver opengl3 -s res://tests/shots/model_viewer.gd \
#       -- model=res://models/characters/eli.glb out=user://eli_view.png [colormap=0] [yaw=200]

const CHAR_COLORMAP: String = "res://models/characters/Textures/colormap.png"

var _frames: int = 0
var _out: String = "user://model_view.png"

func _initialize() -> void:
	var model_path: String = "res://models/characters/eli.glb"
	var use_colormap: bool = true
	var yaw_deg: float = 200.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("model="):
			model_path = arg.substr(6)
		elif arg.begins_with("out="):
			_out = arg.substr(4)
		elif arg.begins_with("colormap="):
			use_colormap = arg.substr(9) != "0"
		elif arg.begins_with("yaw="):
			yaw_deg = arg.substr(4).to_float()

	var scene_root: Node3D = Node3D.new()
	root.add_child(scene_root)

	var glb: PackedScene = load(model_path)
	if glb == null:
		print("[model_viewer] cannot load ", model_path)
		quit(1)
		return
	var inst: Node3D = glb.instantiate()
	inst.rotation_degrees.y = yaw_deg
	scene_root.add_child(inst)
	# Inline colormap re-bind (mirrors npc.gd::apply_kenney_colormap — that
	# script can't be preloaded from a bare -s entry script: its GameState
	# references don't resolve at entry-parse time).
	if use_colormap:
		var tex: Texture2D = load(CHAR_COLORMAP) as Texture2D
		if tex != null:
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_texture = tex
			mat.roughness = 0.78
			var stack: Array = [inst]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is MeshInstance3D:
					(n as MeshInstance3D).material_override = mat
				for c in n.get_children():
					stack.append(c)

	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.mesh = PlaneMesh.new()
	(ground.mesh as PlaneMesh).size = Vector2(8, 8)
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.albedo_color = Color(0.32, 0.33, 0.36)
	ground.material_override = gmat
	scene_root.add_child(ground)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.3
	scene_root.add_child(sun)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(-1.5, 1.5, 2.0)
	fill.light_energy = 0.8
	scene_root.add_child(fill)

	var cam: Camera3D = Camera3D.new()
	cam.position = Vector3(0.0, 1.1, 2.4)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	scene_root.add_child(cam)
	cam.make_current()

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var img: Image = root.get_viewport().get_texture().get_image()
		var abs_out: String = ProjectSettings.globalize_path(_out)
		var err: int = img.save_png(abs_out)
		print("[model_viewer] saved=%s err=%d" % [abs_out, err])
		quit(0)
	return false
