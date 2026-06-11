extends SceneTree

# Visual validation for the standoff CUTSCENE path: interacting with Dr Rush in
# live play now runs the letterboxed, Space-advanced cinematic (standoff_rush ->
# room._run_standoff_cinematic -> StandoffCinematic + StandoffCamera). This
# harness drives the REAL interact entry point and advances beats via the
# sequencer's request_advance() — every PNG is exactly what the player sees.
#
# Run NON-headless (needs a real frame to capture pixels):
#   godot --quit-after 4000 -s res://tests/capture/standoff_cinema.gd
#
# Output: user://cinema_<NN>_<label>.png (absolute paths printed to stdout).

const ROOM_SCENE: String = "res://scenes/room.tscn"

var _shots: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== standoff cinematic capture ===")
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

	# Player walked up to Rush, then the REAL interact starts the cutscene.
	var pl: Node3D = room.get_node_or_null("Player") as Node3D
	if pl != null:
		pl.position = Vector3(2.6, 0.0, 0.0)
		pl.rotation.y = -PI * 0.5
	for i in range(2):
		await process_frame
	var rush: Node = room.get_node_or_null("DrRush")
	if rush == null or not rush.has_method("interact"):
		push_error("DrRush missing")
		quit()
		return
	rush.call("interact", pl)
	await _settle(50)   # letterbox in + wide shot glide
	print("[cinema] sequencer %s, camera %s, met_rush=%s" % [
		"ACTIVE" if room.get_node_or_null("StandoffCinematic") != null else "MISSING",
		"ACTIVE" if room.get_node_or_null("StandoffCamera") != null else "MISSING",
		gs.get("met_rush")])
	await _shot("eli_warning")          # node 0: Eli's line, wide two-shot

	_advance(room)                       # -> node 1: Greer charges (hold)
	await _settle(170)                   # charge + arrival + aim + release
	_dump_greer(room)
	await _shot("greer_aim")

	_advance(room)                       # -> node 2: Scott runs in
	await _settle(130)
	await _shot("scott_in")

	_advance(room)                       # -> node 3: Rush "I've run the numbers"
	await _settle(40)
	await _shot("rush_numbers")

	_advance(room)                       # -> node 4: stand-down + walk-out
	await _settle(90)
	await _shot("stand_down")

	_advance(room)                       # -> finished: letterbox out
	await _settle(50)
	var seq_gone: bool = room.get_node_or_null("StandoffCinematic") == null \
		or (room.get_node_or_null("StandoffCinematic") as Node).is_queued_for_deletion()
	print("[cinema] finished: sequencer freed=%s camera_freed=%s" % [
		seq_gone, room.get_node_or_null("StandoffCamera") == null])
	await _shot("restored_gameplay")

	print("=== done: %d shots ===" % _shots)
	quit()


func _advance(room: Node) -> void:
	var seq: Node = room.get_node_or_null("StandoffCinematic")
	if seq != null:
		seq.call("request_advance")


# Numbers check for the draw-and-aim beat: Greer must FACE Rush (forward dot
# to-Rush ~1.0) and be playing the pistol_aim clip — the live-play regression
# was idle-facing-nowhere (walk_to stomped the pose).
func _dump_greer(room: Node) -> void:
	var greer: Node3D = room.get_node_or_null("StandoffGreer") as Node3D
	var rush: Node3D = room.get_node_or_null("DrRush") as Node3D
	if greer == null or rush == null:
		print("[greer] MISSING")
		return
	var fwd: Vector3 = Vector3(-sin(greer.rotation.y), 0.0, -cos(greer.rotation.y))
	var to_rush: Vector3 = rush.global_position - greer.global_position
	to_rush.y = 0.0
	var clip: String = ""
	var stack: Array = [greer]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			clip = (n as AnimationPlayer).current_animation
			break
		for c in n.get_children():
			stack.append(c)
	print("[greer] facing_dot=%.2f (1.0 = dead-on Rush) clip=%s pos=%s" % [
		fwd.normalized().dot(to_rush.normalized()), clip, greer.global_position])


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
