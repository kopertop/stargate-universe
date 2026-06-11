extends SceneTree

# Visual validation for the standoff CINEMATIC CAMERA (the pause-immune rig
# room.gd activates at dialog-open). Unlike standoff_capture.gd this adds NO
# framing camera of its own — every PNG is exactly what the player will see
# behind the dialog panel (subjects biased right-of-frame via h_offset).
#
# Run NON-headless (needs a real frame to capture pixels):
#   godot --quit-after 2000 -s res://tests/capture/standoff_cinema.gd
#
# Output: user://cinema_<NN>_<label>.png (absolute paths printed to stdout).

const ROOM_SCENE: String = "res://scenes/room.tscn"

var _shots: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== standoff cinema capture ===")
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

	gs.set("next_room_id", "control_interface_room")
	var room: Node = (load(ROOM_SCENE) as PackedScene).instantiate()
	root.add_child(room)
	for i in range(20):
		await process_frame

	# Player walked up to Rush; dialog opens → restage + cinema begins.
	var pl: Node3D = room.get_node_or_null("Player") as Node3D
	if pl != null:
		pl.position = Vector3(2.6, 0.0, 0.0)
		pl.rotation.y = -PI * 0.5
	for i in range(2):
		await process_frame
	gs.emit_signal("dialog_started", room.get_node_or_null("DrRush"), [])
	await _settle(80)   # glide into the wide shot
	var cam_node: Node = room.get_node_or_null("StandoffCamera")
	print("[cinema] StandoffCamera %s" % ("ACTIVE" if cam_node != null else "MISSING"))
	await _shot("wide_open")

	gs.emit_signal("dialog_action", "standoff_greer")
	await _settle(70)
	await _shot("greer_charge")
	await _settle(80)
	await _shot("greer_aim")

	gs.emit_signal("dialog_action", "standoff_scott")
	await _settle(110)
	await _shot("scott_in")

	gs.emit_signal("dialog_action", "standoff_clear")
	await _settle(60)
	await _shot("stand_down")

	# Dialog closes → camera hands control back to the gameplay view.
	gs.emit_signal("dialog_closed")
	await _settle(10)
	var restored: bool = root.get_viewport().get_camera_3d() != null \
		and room.get_node_or_null("StandoffCamera") == null
	print("[cinema] gameplay camera restored: %s" % restored)
	await _shot("restored_gameplay")

	print("=== done: %d shots ===" % _shots)
	quit()


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://cinema_%02d_%s.png" % [_shots, label]
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(path)
	print("[shot] %s err=%s abs=%s" % [path, err, ProjectSettings.globalize_path(path)])
	_shots += 1
