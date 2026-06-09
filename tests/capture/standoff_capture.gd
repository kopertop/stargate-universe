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

	# Simulate the player having walked up to Rush (the _ready spawn is at the far
	# door). Stand ~2.5 m west of Rush facing east toward him, then fire
	# dialog_started so the standoff restages the actors behind the player.
	var pl: Node3D = room.get_node_or_null("Player") as Node3D
	if pl != null:
		pl.position = Vector3(2.6, 0.0, 0.0)
		pl.rotation.y = -PI * 0.5   # forward = +X (east, toward Rush at x=5)
	for i in range(2):
		await process_frame
	gs.emit_signal("dialog_started", room.get_node_or_null("DrRush"), [])

	# Disable the player's third-person camera so it can't reclaim `current` from
	# our framing camera each frame.
	_disable_other_cameras(room)

	# Framing camera: a 3/4 vantage on the player side (west, -X), elevated,
	# looking at the console area so Rush + the behind-right Greer + entering
	# Scott are all in frame.
	var cam: Camera3D = Camera3D.new()
	cam.fov = 55.0
	room.add_child(cam)
	_aim_cam(cam, Vector3(-1.5, 4.6, 6.0), Vector3(4.5, 1.0, -0.4))
	for i in range(6):
		await process_frame
	_dump_positions(room, "initial")

	await _shot("initial")                       # Greer behind player, Scott back by entry
	gs.emit_signal("dialog_action", "standoff_greer")
	await _settle(120)                            # let him charge in + level the sidearm
	_dump_positions(room, "greer_aim")
	await _shot("greer_aim")

	# High 3/4 closeup (he ends ~(6.4,-1.36)) above the console so the aimed
	# sidearm reads against Rush at (5,0).
	_aim_cam(cam, Vector3(8.0, 3.1, -3.6), Vector3(5.7, 0.9, -0.7))
	await _settle(6)
	await _shot("greer_aim_closeup")

	# Gameplay-like third-person: behind the player (who stands ~(2.6,0,0) east of
	# the central pillar) looking at the Rush/Greer confrontation.
	_aim_cam(cam, Vector3(1.2, 2.4, 0.2), Vector3(5.8, 1.0, -0.7))
	await _settle(6)
	await _shot("greer_aim_pov")

	gs.emit_signal("dialog_action", "standoff_scott")
	await _settle(120)                            # Scott walks in
	_aim_cam(cam, Vector3(-1.5, 4.6, 6.0), Vector3(4.5, 1.0, -0.4))
	await _settle(6)
	_dump_positions(room, "scott_in")
	await _shot("scott_in")

	print("=== done: %d shots ===" % _shots)
	quit()


# Position + aim our framing camera and (re)assert it as current — the player's
# camera may try to reclaim current each frame.
func _aim_cam(cam: Camera3D, pos: Vector3, target: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.current = true


# Disable every OTHER Camera3D in the tree so our framing camera wins.
func _disable_other_cameras(room: Node) -> void:
	var stack: Array = [room]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Camera3D:
			(n as Camera3D).current = false
		for c in n.get_children():
			stack.append(c)


# Log Greer/Scott world positions so we can confirm the actors actually moved
# even if the framing hides them.
func _dump_positions(room: Node, beat: String) -> void:
	var g: Node3D = room.get_node_or_null("StandoffGreer") as Node3D
	var s: Node3D = room.get_node_or_null("StandoffScott") as Node3D
	var gp: String = str(g.global_position) if g != null else "<none>"
	var sp: String = str(s.global_position) if s != null else "<none>"
	print("[pos] %s  Greer=%s  Scott=%s" % [beat, gp, sp])


# Let the choreography animate for N rendered frames.
func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(label: String) -> void:
	# Wait for the camera move to actually render before reading the framebuffer —
	# process_frame fires BEFORE draw, so capturing there grabs the prior frame.
	await RenderingServer.frame_post_draw
	var path: String = "user://standoff_%02d_%s.png" % [_shots, label]
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: Error = img.save_png(path)
	print("[shot] %s err=%s abs=%s" % [path, err, ProjectSettings.globalize_path(path)])
	_shots += 1
