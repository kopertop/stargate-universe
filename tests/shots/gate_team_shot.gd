extends SceneTree

# One-off capture harness for Phase F gate-room "team assembled at the gate"
# beat — sets the player at quest MINE_LIME with the post-scout briefing
# already done, routes into the gate room, and grabs an overhead still so the
# away team's formation in front of the active Stargate can be eyeballed.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: Dictionary = _parse_args()
	var out: String = String(args.get("out", "user://gate_team.png"))

	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	if gs == null or router == null:
		print("SHOT_ERROR autoloads missing")
		quit(1)
		return

	# Stand at the gate just after Scott's briefing — the assembled team beat.
	gs.set("met_scott", true)
	gs.set("met_rush", true)
	gs.set("scrubber_diagnosed", true)
	gs.set("kino_scout_done", true)
	gs.set("kino_plan_approved", true)
	gs.set("lime_planet_dialed", true)
	gs.set("away_party_briefed", true)
	gs.set("returned_from_lime_planet", false)
	gs.set("quest_step", GameState.QUEST_MINE_LIME)   # const, not a property — go through the singleton

	await process_frame
	await process_frame
	router.call("change_to", "res://scenes/gate_room.tscn", "FromCorridor")
	for _i in 200:
		await process_frame
		var cur: Node = current_scene
		if cur != null and String(cur.scene_file_path).ends_with("gate_room.tscn"):
			break
	# Let companions enter the tree + the briefing branch settle.
	for _j in 30:
		await process_frame

	var team: Array = get_nodes_in_group("away_team")
	print("SHOT gate-team count=", team.size())
	var gate_room: Node = current_scene
	if gate_room == null:
		print("SHOT_ERROR no gate_room")
		quit(1)
		return

	# Temporary camera placed inside the gate-room ceiling height, looking at
	# the team's spot in front of the gate so the trio + active event horizon
	# are both framed.
	var cam: Camera3D = Camera3D.new()
	gate_room.add_child(cam)
	cam.global_position = Vector3(0.0, 4.5, 3.5)
	cam.look_at(Vector3(0.0, 1.6, 11.0), Vector3.UP)
	cam.current = true
	for _k in 4:
		await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: int = img.save_png(out)
	print("SHOT ", out, " (save err=", err, ")")
	quit(0)


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		var eq: int = s.find("=")
		if eq > 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out
