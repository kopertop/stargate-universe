extends SceneTree

# Headed capture harness for the PLANET DEPARTURE CUTSCENE (Phase F / F1). Boots
# the lime planet at quest MINE_LIME so planet.gd spawns the DepartureTimer,
# teleports the player far from the return gate, then forces the timer to expire
# so the full letterbox cutscene plays: caption on the bottom bar, high overhead
# camera, the away team dashing the whole distance, vanishing through the gate,
# the gate shutting down, and the recall to the gate room.
#
# Saves a numbered PNG sequence (frame_00..frame_NN) plus an "_after" shot once
# the scene has changed to the gate room, so the beat can be eyeballed without
# playing the whole 10-minute run by hand.
#
# IMPORTANT: run WITHOUT --headless (rendering must be live) and with the project
# default renderer (Forward+) so the capture matches what the player sees.
#
#   godot --quit-after 900 -s res://tests/shots/cutscene_shot.gd ++ \
#       out=user://cutscene far=52 frames=380

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Dictionary = _parse_args()
	var out_prefix: String = String(args.get("out", "user://cutscene"))
	var far: float = float(args.get("far", "72"))
	var total_frames: int = int(args.get("frames", "600"))
	# Physics can step several times per render frame here, so the dash covers a
	# lot of ground between captures. Grab by DISTANCE-to-gate instead of frame
	# index so the stills land at predictable points along the run.
	var grab_dist: Array = [60.0, 42.0, 26.0, 12.0]

	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	if gs == null or router == null:
		print("SHOT_ERROR autoloads missing (gs=", gs, " router=", router, ")")
		quit(1)
		return

	# Already met Scott at this point in the spine, so the gate-room arrival on
	# recall must NOT re-trigger his walk-up greet (that's first-boot behaviour).
	gs.set("met_scott", true)
	# Sit exactly at the mining run. Set quest_step LAST and DON'T add lime —
	# add_resource() recomputes the quest ladder and would push us past mine_lime,
	# so the timer (which only spawns at MINE_LIME) would never appear.
	gs.set("kino_pilot_mode", false)
	gs.set("quest_step", gs.get("QUEST_MINE_LIME"))

	# Let SceneRouter finish its deferred _ready (fade layer) before transitioning.
	await process_frame
	await process_frame
	router.call("change_to", "res://scenes/planet.tscn", "FromShipGate")

	# Wait for the planet to build + the player rig + DepartureTimer to settle.
	var planet: Node = null
	for i in 120:
		await process_frame
		planet = current_scene
		if planet != null and String(planet.scene_file_path).ends_with("planet.tscn"):
			if planet.get_node_or_null("DepartureTimer") != null:
				break

	if planet == null:
		print("SHOT_ERROR planet scene never came up")
		quit(1)
		return

	var timer: Node = planet.get_node_or_null("DepartureTimer")
	var player: Node3D = get_first_node_in_group("player") as Node3D
	var gate: Node3D = _find_gate()
	var companions: int = get_nodes_in_group("away_team").size()
	print("SHOT setup planet=", planet.scene_file_path,
		" timer=", timer != null, " player=", player != null, " gate=", gate != null,
		" companions=", companions, " lime_nodes=", get_nodes_in_group("lime_node").size())
	if timer == null or player == null or gate == null:
		print("SHOT_ERROR missing node(s)")
		quit(1)
		return

	# Settle a bit so companions step into their follow positions, then grab a
	# landing-zone still from a temporary overhead camera (the player's own view
	# camera is jammed against the gate, so it can't see the team).
	for _s in 40:
		await process_frame
	var look_cam: Camera3D = Camera3D.new()
	planet.add_child(look_cam)
	look_cam.global_position = player.global_position + Vector3(0.0, 14.0, 12.0)
	look_cam.look_at(player.global_position, Vector3.UP)
	look_cam.current = true
	await process_frame
	_save_cam(out_prefix + "_idle.png")
	look_cam.queue_free()
	await process_frame

	# Teleport the player far from the gate so the dash is long enough to read on
	# camera. +Z is away from the gate (gate faces -Z). Keep current height — the
	# cinematic dash's ground ray re-grounds it on the first frame.
	var gp: Vector3 = gate.global_position
	player.global_position = Vector3(gp.x + 3.0, player.global_position.y, gp.z + far)
	print("SHOT player moved to ", player.global_position, " gate at ", gp,
		" planar=", Vector2(player.global_position.x - gp.x, player.global_position.z - gp.z).length())

	# Force the countdown to expire on the next _process tick → cutscene begins.
	timer.set("_remaining", 0.05)

	var grabbed: int = 0
	var after_saved: bool = false
	for f in total_frames:
		await process_frame
		# Distance-driven stills: snap the next threshold as the player passes it.
		if grabbed < grab_dist.size() and is_instance_valid(player):
			var planar: float = Vector2(player.global_position.x - gp.x,
				player.global_position.z - gp.z).length()
			if planar <= float(grab_dist[grabbed]):
				_save_cam(out_prefix + "_run_%02d.png" % grabbed)
				print("  (grab at planar=", planar, ")")
				grabbed += 1
		# Detect the recall: scene flips to the gate room.
		var cur: Node = current_scene
		if not after_saved and cur != null and String(cur.scene_file_path).ends_with("gate_room.tscn"):
			# Let the gate room settle a few frames, then capture the arrival.
			for _j in 30:
				await process_frame
			_save_cam(out_prefix + "_after.png")
			after_saved = true
			break

	if not after_saved:
		_save_cam(out_prefix + "_end.png")
		print("SHOT_WARN never reached gate_room within ", total_frames, " frames")

	print("SHOT done grabbed=", grabbed, " reached_gate_room=", after_saved)
	quit(0)

func _find_gate() -> Node3D:
	for n in get_nodes_in_group("planet_gate"):
		if n is Node3D and String(n.get("mode")) == "to_ship":
			return n as Node3D
	return null

func _save_cam(path: String) -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	if cam != null:
		var up: Vector3 = cam.global_transform.basis.y
		print("CAM ", path, " up=", up, " fwd=", -cam.global_transform.basis.z, " pos=", cam.global_position)
	else:
		print("SHOT_WARN no camera for ", path)
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: int = img.save_png(path)
	print("SHOT ", path, " (save err=", err, ")")

func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		var eq: int = s.find("=")
		if eq > 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out
