extends SceneTree

# Cinematic gate-room capture for the #30 art pass. Boots gate_room cleanly (no
# arrival dialog, gate ACTIVE so the event horizon glows), hides the player rig +
# HUD, drops a free Camera3D framed down the room axis toward the gate, and saves
# a PNG. Run WITHOUT --headless (headless disables rendering → blank PNG):
#
#   godot --quit-after 400 -s res://tests/shots/gate_cinematic_shot.gd ++ \
#       out=user://gate_cine.png cam_pos=0,2.2,-11 cam_look=0,3.4,12.2 fov=70 wait=40

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Dictionary = _parse_args()
	var out_path: String = String(args.get("out", "user://gate_cine.png"))

	var router: Node = root.get_node_or_null("SceneRouter")
	if router != null:
		router.set("instant_mode", true)
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "gate_cine")
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.call("reset")
		# Take the save-spawn branch so _run_arrival's dialog/cinematic never fires.
		gs.set("skip_arrival_cinematic", true)
		gs.set("pending_spawn_position", Vector3(0.0, 0.05, -11.0))
		# Open the gate for real — gate_room._process re-asserts active from
		# is_gate_open() every frame, so forcing _stargate.active alone gets undone.
		gs.set("lime_planet_dialed", true)

	var packed: PackedScene = load("res://scenes/gate_room.tscn") as PackedScene
	if packed == null:
		print("SHOT_ERROR could not load gate_room.tscn")
		quit(1)
		return
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	current_scene = inst
	await process_frame
	await process_frame

	# Light the gate up — the event horizon is the key light in the reference.
	var gate: Node = inst.find_child("Stargate", true, false)
	if gate != null and "active" in gate:
		gate.set("active", true)
	if String(OS.get_environment("CINE_DEBUG")) == "1":
		print("DBG gate=", gate)
		var eh: Node = inst.find_child("EventHorizon", true, false)
		print("DBG horizon=", eh, " visible=", (eh as Node3D).visible if eh is Node3D else "n/a")
		if eh != null:
			var m: Variant = (eh as MeshInstance3D).material_override
			print("DBG horizon_mat=", m, " class=", (m.get_class() if m != null else "NULL"))
			print("DBG horizon_aabb=", (eh as MeshInstance3D).get_aabb(), " gpos=", (eh as Node3D).global_position)
	if String(OS.get_environment("CINE_DEBUG")) == "2":
		var eh2: Node = inst.find_child("EventHorizon", true, false)
		if eh2 is MeshInstance3D:
			var simple: StandardMaterial3D = StandardMaterial3D.new()
			simple.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			simple.albedo_color = Color(0.3, 0.8, 1.0, 1.0)
			simple.emission_enabled = true
			simple.emission = Color(0.3, 0.8, 1.0, 1.0)
			simple.emission_energy_multiplier = 4.0
			(eh2 as MeshInstance3D).material_override = simple
	# Clean environment shot: hide the on-foot rig + HUD.
	var ply: Node = inst.get_node_or_null("Player")
	if ply is Node3D:
		(ply as Node3D).visible = false
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false

	var cam: Camera3D = Camera3D.new()
	cam.fov = float(args.get("fov", "70"))
	inst.add_child(cam)
	cam.global_position = _v3(String(args.get("cam_pos", "0,2.2,-11")))
	cam.look_at(_v3(String(args.get("cam_look", "0,3.4,12.2"))), Vector3.UP)
	cam.current = true

	var wait_frames: int = int(args.get("wait", "40"))
	for i in wait_frames:
		await process_frame

	var img: Image = root.get_viewport().get_texture().get_image()
	var err: int = img.save_png(out_path)
	print("SHOT ", out_path, " (save err=", err, ")")
	quit(0)

func _v3(s: String) -> Vector3:
	var p: PackedStringArray = s.split(",")
	if p.size() != 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		var eq: int = s.find("=")
		if eq > 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out
