extends SceneTree

# One-shot lineup of the stargate-prop pack so we can see each prop's native
# orientation/silhouette at a known scale, instead of guessing rotations blind.
# Each prop is normalized to a 1-unit box, so scale 3.0 -> ~3 m. Front view (+Z
# camera) and the props sit feet-on-floor at y=0.
#
#   godot --quit-after 200 -s res://tests/shots/prop_lineup.gd ++ out=user://lineup.png

const DIR := "res://models/sci-fi/stargate-props/"
const FILES := [
	"sci-fi-stargate-props-stargate-portal-ring.glb",
	"sci-fi-stargate-props-raised-circular-platform.glb",
	"sci-fi-stargate-props-metal-staircase-steps.glb",
	"sci-fi-stargate-props-operator-control-console.glb",
	"sci-fi-stargate-props-overhead-ceiling-ring-structure.glb",
	"sci-fi-stargate-props-spotlight-ceiling-light.glb",
	"sci-fi-stargate-props-industrial-wall-column.glb",
	"sci-fi-stargate-props-catwalk-railing-segment.glb",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var out_path := String(args.get("out", "user://lineup.png"))

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.18)
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.6
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.4
	world.add_child(sun)

	var spacing := 5.0
	for i in FILES.size():
		var ps: PackedScene = load(DIR + FILES[i]) as PackedScene
		var x := (i - (FILES.size() - 1) * 0.5) * spacing
		if ps != null:
			var inst: Node3D = ps.instantiate()
			inst.scale = Vector3(3, 3, 3)
			inst.position = Vector3(x, 0, 0)
			world.add_child(inst)
		var tag := Label3D.new()
		tag.text = FILES[i].replace("sci-fi-stargate-props-", "").replace(".glb", "")
		tag.position = Vector3(x, 4.2, 0)
		tag.pixel_size = 0.01
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color(1, 0.9, 0.4)
		world.add_child(tag)

	var cam := Camera3D.new()
	cam.fov = 55
	cam.position = Vector3(0, 2.5, 26)
	world.add_child(cam)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	cam.current = true

	for i in 30:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("SHOT ", out_path)
	quit(0)
