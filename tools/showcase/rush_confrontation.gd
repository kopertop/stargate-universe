extends Node

# Movie Maker driver for the full Rush confrontation sequence:
#   1. Eli walks up to Rush in the control interface room (live gameplay cam)
#   2. first interact -> the standoff CUTSCENE plays (letterbox, captions,
#      Greer's charge + drawn sidearm, Scott's intervention, stand-down) —
#      beats advanced on a timed pinger standing in for the player's Space
#   3. re-interact -> the Fable conversation (camera locked on Rush, floating
#      gold choices) walks two nodes and closes
#
#   godot --path . --write-movie out/raw/rush_confrontation.avi \
#     --fixed-fps 30 --resolution 1280x720 tools/showcase/rush_confrontation.tscn
#
# Deterministic under fixed-fps: timers tick in movie time (create_timer's
# process_always default keeps them alive through the dialog pause).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	var save_mgr: Node = get_node_or_null("/root/SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths")   # never touch the real save
	SceneRouter.instant_mode = false
	GameState.reset()
	GameState.next_room_id = "control_interface_room"
	var room: Node = (load("res://scenes/room.tscn") as PackedScene).instantiate()
	add_child(room)
	await _wait(1.0)

	var player: Node3D = room.get_node_or_null("Player") as Node3D
	var rush: Node = room.get_node_or_null("DrRush")
	if player == null or rush == null:
		push_error("player/Rush missing")
		get_tree().quit()
		return

	# Gameplay beat: Eli walks across the room toward Rush.
	player.position = Vector3(-2.0, 0.0, 1.2)
	player.rotation.y = -PI * 0.5
	var view: Node = room.get_node_or_null("View")
	if view != null and view.has_method("snap_to_target"):
		view.call("snap_to_target")
	await _wait(0.8)
	player.call("auto_walk_to", Vector3(3.3, 0.0, 0.0), 3.4)
	var guard: int = 0
	while guard < 300 and player.position.distance_to(Vector3(3.3, 0.0, 0.0)) > 0.3:
		await get_tree().process_frame
		guard += 1
	await _wait(0.6)

	# The confrontation: first interact triggers the standoff cutscene.
	rush.call("interact", player)
	await _wait(0.5)
	var seq: Node = room.get_node_or_null("StandoffCinematic")
	if seq == null:
		push_error("standoff cinematic did not start")
		get_tree().quit()
		return
	# Timed stand-in for the player's Space presses: ping every 4.5 s — held
	# beats swallow early pings, so Greer's charge always lands first.
	while is_instance_valid(seq) and seq.is_inside_tree():
		await _wait(4.5)
		if is_instance_valid(seq) and seq.is_inside_tree():
			seq.call("request_advance")
	# Soldiers walk out; let the room breathe.
	await _wait(4.0)

	# Aftermath: talk to Rush again — the Fable conversation view.
	rush.call("interact", player)
	await _wait(3.4)
	_press_choice(1)   # "Go where?"
	await _wait(3.6)
	_press_choice(0)   # "Right." -> exit
	await _wait(2.0)
	get_tree().quit()


func _press_choice(idx: int) -> void:
	var screen: Node = _find_dialog_screen(get_tree().root)
	if screen == null:
		push_error("no dialog screen for choice %d" % idx)
		return
	var box: Node = screen.get_node_or_null("Window/Margin/VBox/ChoicesVBox")
	if box == null or idx >= box.get_child_count():
		push_error("choice %d missing" % idx)
		return
	(box.get_child(idx) as Button).emit_signal("pressed")


func _find_dialog_screen(node: Node) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path.ends_with("dialog_screen.gd"):
		return node
	for child in node.get_children():
		var found: Node = _find_dialog_screen(child)
		if found != null:
			return found
	return null


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
