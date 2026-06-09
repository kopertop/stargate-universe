extends SceneTree

# Visual validation harness for the #136 cold-open standoff choreography.
# Renders the REAL control room (Forward+) and drives the standoff beat-by-beat,
# saving a PNG at each beat so the staging (military fatigues, sidearms, Greer
# charging in behind-right of Rush + aiming, Scott entering) can be eyeballed.
#
# Run NON-headless (needs a real frame to capture pixels):
#   godot --quit-after 2000 -s res://tests/capture/standoff_capture.gd
#
# Output: user://standoff_<NN>_<label>.png (absolute paths printed to stdout).

const ROOM_SCENE: String = "res://scenes/room.tscn"
const VIEW: Vector2i = Vector2i(1280, 720)

var _shots: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== standoff capture ===")
	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if gs == null or router == null:
		push_error("autoloads missing")
		quit()
		return

	# Never touch the real save; never snap-skip the choreography.
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths")
	router.set("instant_mode", false)
	gs.call("reset")   # fresh: met_rush/air_crisis/kino_pilot all false → standoff spawns

	# Build the control room.
	gs.set("next_room_id", "control_interface_room")
	var packed: PackedScene = load(ROOM_SCENE) as PackedScene
	var room: Node = packed.instantiate()
	root.add_child(room)
	for i in range(20):
		await process_frame   # let _ready build geometry + spawn the actors

	# Framing camera: a 3/4 vantage on the player side (west, -X), elevated,
	# looking at the console area so Rush + the behind-right Greer + entering
	# Scott are all in frame.
	var cam: Camera3D = Camera3D.new()
	cam.fov = 55.0
	room.add_child(cam)
	cam.global_position = Vector3(-1.5, 4.6, 6.0)
	cam.look_at(Vector3(4.5, 1.0, -0.4), Vector3.UP)
	cam.make_current()
	for i in range(6):
		await process_frame

	await _shot("initial")                       # Greer behind player, Scott back by entry
	gs.emit_signal("dialog_action", "standoff_greer")
	await _settle(120)                            # let him charge in + level the sidearm
	await _shot("greer_aim")

	# Over-Greer's-shoulder closeup so the aimed sidearm reads against Rush.
	cam.global_position = Vector3(8.1, 1.7, -2.7)
	cam.look_at(Vector3(5.4, 1.0, -0.2), Vector3.UP)
	await _settle(6)
	await _shot("greer_aim_closeup")

	gs.emit_signal("dialog_action", "standoff_scott")
	await _settle(120)                            # Scott walks in
	cam.global_position = Vector3(-1.5, 4.6, 6.0)
	cam.look_at(Vector3(4.5, 1.0, -0.4), Vector3.UP)
	await _settle(6)
	await _shot("scott_in")

	print("=== done: %d shots ===" % _shots)
	quit()


# Let the choreography animate for N rendered frames.
func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(label: String) -> void:
	var path: String = "user://standoff_%02d_%s.png" % [_shots, label]
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(path)
	print("[shot] %s err=%s abs=%s" % [path, err, ProjectSettings.globalize_path(path)])
	_shots += 1
