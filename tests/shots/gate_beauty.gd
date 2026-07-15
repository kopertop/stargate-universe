extends SceneTree

# Fast standalone composition shot for the NEW gunmetal gate ring + procedural
# event horizon. Builds only a floor + the ring + horizon + lighting and a
# head-on camera (concept "Central Approach"). Lets us dial scale/rotation/
# horizon/brightness without booting the full gate_room + dialog cinema.
#
#   godot --quit-after 120 -s res://tests/shots/gate_beauty.gd ++ \
#       out=user://gate_beauty.png sx=0.33 sd=6.0 active=1 spin=0
#
#   sx     = ring depth scale (thin X axis)          (default 0.33)
#   sd     = ring diameter scale (Y/Z)               (default 6.0)
#   active = event horizon visible (1) or dormant(0) (default 1)
#   spin   = ring roll degrees (dial animation pose) (default 0)
#   cam    = "front" | "ots"                         (default front)

const RING := "res://models/sci-fi/stargate-props/gunmetal-gate-no-glyphs.glb"
const STARGATE := "res://objects/stargate.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var out_path := String(args.get("out", "user://gate_beauty.png"))
	var sx := float(args.get("sx", "0.33"))
	var sd := float(args.get("sd", "6.0"))
	var active := String(args.get("active", "1")) == "1"
	var spin := float(args.get("spin", "0"))
	var cam_mode := String(args.get("cam", "front"))

	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	# --- Environment: brighter-than-concept icy industrial ---
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.78)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.15
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(20), 0)
	sun.light_energy = 1.6
	sun.light_color = Color(0.8, 0.86, 1.0)
	world.add_child(sun)
	# Fill from camera side so the ring face reads.
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 4, 10)
	fill.light_energy = 3.0
	fill.omni_range = 30.0
	fill.light_color = Color(0.7, 0.8, 1.0)
	world.add_child(fill)

	# --- Floor (reflective grid feel) ---
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.10, 0.11, 0.14)
	fmat.metallic = 0.6
	fmat.roughness = 0.25
	floor.material_override = fmat
	world.add_child(floor)

	# --- New gunmetal ring, floor-pinned ---
	# Native: thin on X (0.291), circle in YZ (0.998). Rotate 90deg about Y so the
	# thin (facing) axis points along Z toward the camera. Roll about Z = dial spin.
	var ring_ps: PackedScene = load(RING)
	var diameter := 0.998 * sd
	if ring_ps != null:
		var ring: Node3D = ring_ps.instantiate()
		ring.scale = Vector3(sx, sd, sd)
		# After Y-rotation the ring faces +/-Z; bottom of the ring sits on floor.
		ring.rotation = Vector3(0.0, PI * 0.5, deg_to_rad(spin))
		ring.position = Vector3(0.0, diameter * 0.5, 0.0)
		ring.name = "Ring"
		world.add_child(ring)
		print("RING diameter=", diameter, " depth=", 0.291 * sx, " center_y=", diameter * 0.5)

	# --- Procedural event horizon sized to the new ring (empty-look = dormant) ---
	var sg_ps: PackedScene = load(STARGATE)
	if sg_ps != null:
		var sg: Node3D = sg_ps.instantiate()
		# Hide the built-in ring/chevrons — the gunmetal GLB is the ring now.
		sg.position = Vector3(0.0, diameter * 0.5, 0.0)
		world.add_child(sg)
		await process_frame
		for n in ["OuterRing", "GlyphBand"]:
			var old := sg.get_node_or_null(n)
			if old != null: (old as Node3D).visible = false
		for i in 9:
			var ch := sg.get_node_or_null("Chevron%d" % i)
			if ch != null: (ch as Node3D).visible = false
		# Size the horizon to the new inner radius (~0.45 * diameter).
		var target_inner := diameter * 0.45
		var scl := target_inner / 2.4   # stargate.gd radius_inner default
		var horizon := sg.get_node_or_null("EventHorizon")
		if "active" in sg:
			sg.set("active", active)
		# Scale the whole stargate node so horizon+ripples+light match the ring.
		sg.scale = Vector3(scl, scl, scl)
		sg.position = Vector3(0.0, diameter * 0.5, 0.0)

	# --- Camera ---
	var cam := Camera3D.new()
	cam.fov = 55.0
	if cam_mode == "ots":
		cam.position = Vector3(2.5, 1.6, 9.0)
		cam.look_at(Vector3(0, diameter * 0.45, 0), Vector3.UP)
	else:
		cam.position = Vector3(0.0, diameter * 0.45, 13.0)
		cam.look_at(Vector3(0, diameter * 0.45, 0), Vector3.UP)
	world.add_child(cam)

	for i in 30:
		await process_frame

	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("SHOT ", out_path, " err=", err)
	quit(0)
