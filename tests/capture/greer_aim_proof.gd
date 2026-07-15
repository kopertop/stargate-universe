extends SceneTree

# PROOF capture for the Greer aim beat: drives the REAL standoff to the
# moment Greer levels the rifle, screenshots it from a fixed diagnostic
# camera, then ROTATES GREER +35 degrees and screenshots again from the
# same camera — if the rifle is truly bone-mounted, it swings with him.
# Numeric dump: Greer's node yaw vs the rifle's global long-axis yaw.
#   godot --quit-after 4000 -s res://tests/capture/greer_aim_proof.gd

const ROOM_SCENE: String = "res://scenes/room.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== greer aim proof ===")
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

	var pl: Node3D = room.get_node_or_null("Player") as Node3D
	var rush: Node = room.get_node_or_null("DrRush")
	pl.position = Vector3(3.4, 0.0, 0.0)
	pl.rotation.y = -PI * 0.5
	await process_frame
	rush.call("interact", pl)
	await _settle(45)
	_advance(room)                      # -> Greer's beat (hold)
	# Wait until he has actually arrived AND levelled the rifle.
	var greer: Node3D = room.get_node_or_null("StandoffGreer") as Node3D
	var guard: int = 0
	while guard < 600 and is_instance_valid(greer) and _clip_of(greer) != "body/rifle_aim":
		await process_frame
		guard += 1
	await _settle(30)   # blend settles

	# Fixed diagnostic camera: high three-quarter holding Greer AND Rush so
	# the aim line is unambiguous. Disable every other camera first.
	_disable_cameras(root)
	var rush_pos: Vector3 = (rush as Node3D).position
	var mid: Vector3 = (greer.position + rush_pos) * 0.5 + Vector3.UP * 1.1
	var side: Vector3 = (rush_pos - greer.position).normalized().cross(Vector3.UP)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	room.add_child(cam)
	cam.global_position = mid + side * 4.6 + Vector3.UP * 1.8
	cam.look_at(mid, Vector3.UP)
	cam.current = true
	await _settle(6)

	_dump(greer, "A_current")
	await _shot("user://greer_aim_A_current.png")

	# THE TWEAK: rotate Greer 35 deg — bone-mounted gear must swing with him.
	greer.rotation.y += 0.61
	await _settle(6)
	_dump(greer, "B_rotated_+35deg")
	await _shot("user://greer_aim_B_rotated.png")

	print("=== done ===")
	quit()


func _clip_of(actor: Node3D) -> String:
	var stack: Array = [actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return (n as AnimationPlayer).current_animation
		for c in n.get_children():
			stack.append(c)
	return ""


# Numeric proof: node yaw vs the rifle prop's global long-axis (model X) yaw.
func _dump(greer: Node3D, label: String) -> void:
	var rifle: Node3D = null
	var stack: Array = [greer]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "Rifle" and n is Node3D:
			rifle = n
			break
		for c in n.get_children():
			stack.append(c)
	if rifle == null:
		print("[proof] %s: NO RIFLE FOUND" % label)
		return
	var axis: Vector3 = rifle.global_transform.basis.x
	axis.y = 0.0
	var rifle_yaw: float = rad_to_deg(atan2(-axis.x, -axis.z))
	print("[proof] %s: greer_yaw=%.1f rifle_axis_yaw=%.1f" % [
		label, rad_to_deg(greer.rotation.y), rifle_yaw])


func _advance(room: Node) -> void:
	var seq: Node = room.get_node_or_null("StandoffCinematic")
	if seq != null:
		seq.call("request_advance")


func _disable_cameras(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Camera3D:
			(n as Camera3D).current = false
		for c in n.get_children():
			stack.append(c)


func _settle(frames: int) -> void:
	for i in range(frames):
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[shot] %s" % ProjectSettings.globalize_path(path))
