extends SceneTree

# Visual validation for the Fable-style conversation presentation: OTS camera
# on the speaker, player framed while choosing, floating gold choice list,
# bottom subtitle. Drives a REAL conversation (Colonel Young, control room)
# through the live DialogScreen + DialogCinema path and screenshots each view.
#
# Run NON-headless:
#   godot --quit-after 3000 -s res://tests/capture/dialog_cinema.gd
#
# Output: user://dialog_<NN>_<label>.png

const ROOM_SCENE: String = "res://scenes/room.tscn"

var _shots: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== dialog cinema capture ===")
	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if gs == null or router == null:
		push_error("autoloads missing")
		quit()
		return
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths")
	router.set("instant_mode", false)
	gs.call("reset")
	gs.set("met_rush", true)   # no standoff — plain conversations today

	gs.set("next_room_id", "control_interface_room")
	var room: Node = (load(ROOM_SCENE) as PackedScene).instantiate()
	root.add_child(room)
	for i in range(20):
		await process_frame

	# Stand in front of Dr Rush (always in the control room; met_rush=true so
	# his REPEAT tree plays: node 0 = 2 choices, node 1 = single choice).
	var pl: Node3D = room.get_node_or_null("Player") as Node3D
	var rush: Node = room.get_node_or_null("DrRush")
	if pl == null or rush == null:
		push_error("player/Rush missing")
		quit()
		return
	pl.position = Vector3(3.4, 0.0, 0.0)
	pl.rotation.y = -PI * 0.5   # face +X toward Rush
	for i in range(2):
		await process_frame
	rush.call("interact", pl)
	await _settle(45)   # screen spawns; camera locks on the speaker (Rush)

	var screen: Node = _find_dialog_screen(root)
	print("[dialog] screen=%s" % (screen != null))
	_dump_facing(pl, rush)
	# Camera on Rush with the choices ALREADY floating beside him.
	await _shot("speaker_rush_with_choices")

	# Pick "Go where?" (index 1) -> node 1 -> camera stays on Rush.
	_press_choice(screen, 1)
	await _settle(50)
	await _shot("speaker_rush_node1")

	# Exit ("Yes, sir.") -> gameplay camera restored.
	_press_choice(_find_dialog_screen(root), 0)
	await _settle(30)
	print("[dialog] screen freed=%s" % (_find_dialog_screen(root) == null))
	await _shot("restored_gameplay")

	print("=== done: %d shots ===" % _shots)
	quit()


# Both participants must face each other during the conversation (dot of
# body-forward onto the to-other vector; ~1.0 = squared up).
func _dump_facing(pl: Node3D, rush: Node) -> void:
	var r3: Node3D = rush as Node3D
	var to_rush: Vector3 = r3.global_position - pl.global_position
	to_rush.y = 0.0
	var p_fwd: Vector3 = Vector3(-sin(pl.rotation.y), 0.0, -cos(pl.rotation.y))
	var r_fwd: Vector3 = Vector3(-sin(r3.rotation.y), 0.0, -cos(r3.rotation.y))
	print("[facing] player->rush=%.2f rush->player=%.2f" % [
		p_fwd.dot(to_rush.normalized()), r_fwd.dot(-to_rush.normalized())])


func _press_choice(screen: Node, idx: int) -> void:
	if screen == null:
		push_error("no dialog screen to press")
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


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://dialog_%02d_%s.png" % [_shots, label]
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(path)
	print("[shot] %s err=%s abs=%s" % [path, err, ProjectSettings.globalize_path(path)])
	_shots += 1
