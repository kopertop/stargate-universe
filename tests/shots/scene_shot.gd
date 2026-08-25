extends SceneTree

# Reusable screenshot harness so gameplay fixes can be eyeballed WITHOUT walking
# through the game by hand. Boots a scene, optionally enters Kino-pilot mode,
# waits for it to settle, prints camera diagnostics, and saves a PNG.
#
# IMPORTANT: run WITHOUT --headless (which disables rendering) so a real frame
# is produced. Prefer the project's default renderer (Forward+) so the capture
# matches what the player actually sees; opengl3 shades sky/ambient differently.
#
# Usage (see tests/shots/capture.sh):
#   godot --quit-after 400 -s res://tests/shots/scene_shot.gd ++ \
#       scene=res://scenes/planet.tscn out=user://kino_planet.png kino_pilot=1 wait=45

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Dictionary = _parse_args()
	var scene_path: String = String(args.get("scene", "res://scenes/planet.tscn"))
	var out_path: String = String(args.get("out", "user://shot.png"))
	var kino_pilot: bool = String(args.get("kino_pilot", "0")) == "1"
	var wait_frames: int = int(args.get("wait", "45"))

	# Isolate saves off the real player file BEFORE driving any scene. This
	# harness boots full gameplay scenes with live autoloads, and SaveManager
	# autosaves on room/objective changes — without this redirect every capture
	# overwrites the player's user://save.json (see issue #44).
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "shot_scene")

	var gs: Node = root.get_node_or_null("GameState")
	# Optional biome: set an active PlanetSpec so planet.tscn builds a specific
	# biome (jungle traps/flora, etc.) rather than the default desert lime world.
	var biome: String = String(args.get("biome", ""))
	if biome != "" and gs != null:
		gs.set("active_planet_spec", {
			"seed": int(args.get("seed", "7")),
			"biome": biome,
			"resource_table": {"lime_nodes": 4, "lime_per_node": 1,
				"lime_min_radius": 50.0, "lime_max_radius": 120.0},
			"hazard_params": {},
			"name": "%s capture" % biome.capitalize(),
		})
	# Pick the procedural room (room.tscn serves many rooms via next_room_id).
	var room_id: String = String(args.get("room", ""))
	if room_id != "" and gs != null:
		gs.set("next_room_id", room_id)
	# Optional quest step so scene _ready branches (e.g. timer/away-team, atmosphere
	# state) match the beat being captured.
	var step: String = String(args.get("step", ""))
	if step != "" and gs != null:
		gs.set("quest_step", step)
	if kino_pilot and gs != null:
		gs.set("kino_pilot_mode", true)

	# flow=1 routes through SceneRouter.change_to with a spawn point, exactly
	# like the real ship→planet gate crossing — so it catches bugs that a direct
	# instantiate hides (e.g. _place_player_at_spawn clobbering the drone spawn).
	var flow: bool = String(args.get("flow", "0")) == "1"
	var spawn_pt: String = String(args.get("spawn", "FromShipGate"))
	if flow:
		var router: Node = root.get_node_or_null("SceneRouter")
		# Let the SceneRouter autoload finish its deferred _ready (builds the
		# fade layer) before driving a transition.
		await process_frame
		await process_frame
		router.call("change_to", scene_path, spawn_pt)
		for i in wait_frames + 100:
			await process_frame
	else:
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			print("SHOT_ERROR could not load ", scene_path)
			quit(1)
			return
		var inst: Node = packed.instantiate()
		root.add_child(inst)
		# The per-scene HUD picks its compass mode from current_scene.scene_file_path,
		# but its _ready ran during add_child (before current_scene was set), so set
		# it now and re-invoke the (idempotent) spawner — matches scene_boot.gd.
		current_scene = inst
		await process_frame
		var hud: Node = inst.get_node_or_null("HUDLayer/HUD")
		if hud != null and hud.has_method("_spawn_compass"):
			hud.call("_spawn_compass")
		for i in wait_frames:
			await process_frame

	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam != null:
		var up: Vector3 = cam.global_transform.basis.y
		print("CAM up=", up, " fwd=", -cam.global_transform.basis.z, " pos=", cam.global_position)
		print("UPRIGHT=", "YES" if up.y > 0.5 else ("UPSIDE_DOWN" if up.y < -0.5 else "TILTED"))
	else:
		print("SHOT_WARN no current camera")

	var img: Image = root.get_viewport().get_texture().get_image()
	var err: int = img.save_png(out_path)
	print("SHOT ", out_path, " (save err=", err, ")")
	quit(0)

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		var eq: int = s.find("=")
		if eq > 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out
