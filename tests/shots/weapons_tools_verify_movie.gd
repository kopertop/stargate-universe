extends SceneTree

# Visual verify: tablet-only start, no rifle, hotwire UI, loading overlay.
# Keyframes → screenshots/result/weapons_tools_verify/
# Movie (optional): tools/record_weapons_tools_verify.sh
#
#   godot --path . -s res://tests/shots/weapons_tools_verify_movie.gd

const OUT_DIR: String = "res://screenshots/result/weapons_tools_verify"
const FPS: float = 30.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== weapons_tools_verify_movie ===")
	set_meta("demo_capture", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "weapons_tools_verify")

	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	var sr: Node = root.get_node_or_null("SceneRouter")
	var mg: Node = root.get_node_or_null("HotwireMinigame")
	if gs == null or inv == null:
		push_error("missing GameState/Inventory")
		quit(1)
		return

	if sr != null:
		# Keep loading UI visible for the transition beat (not instant_mode).
		sr.set("instant_mode", false)
	gs.set("skip_arrival_cinematic", true)
	if save_mgr != null and save_mgr.has_method("start_new_game"):
		save_mgr.call("start_new_game", "weapons_tools_verify")
	else:
		gs.call("reset")

	# Force known-good loadout for the verify (guards against stale test saves).
	if inv.has_method("reset"):
		inv.call("reset")
	if gs.has_method("seed_starter_tools"):
		gs.call("seed_starter_tools")
	print("[verify] hotbar=", [
		inv.call("hotbar_item", 0),
		inv.call("hotbar_item", 1),
		inv.call("hotbar_item", 2),
		inv.call("hotbar_item", 3),
	], " sidearm=", inv.call("has", "sidearm"))

	# --- Assert loadout before scene ---
	if bool(inv.call("has", "sidearm")):
		push_error("FAIL: sidearm present at New Game")
		quit(1)
		return
	if String(inv.call("hotbar_item", 0)) != "tablet":
		push_error("FAIL: hotbar 0 is not tablet")
		quit(1)
		return
	var icon: String = String((inv.call("definition", "tablet") as Dictionary).get("icon", ""))
	if not icon.ends_with("tablet.png"):
		push_error("FAIL: tablet icon path %s" % icon)
		quit(1)
		return

	var packed: PackedScene = load("res://scenes/gate_room.tscn") as PackedScene
	var gate: Node = packed.instantiate()
	root.add_child(gate)
	current_scene = gate
	await _settle(45)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var player: Node3D = gate.get_node_or_null("Player") as Node3D
	var view: Node3D = gate.get_node_or_null("View") as Node3D
	if player == null:
		push_error("no Player")
		quit(1)
		return
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", false)
	if view != null and view.has_method("snap_to_target"):
		view.call("snap_to_target")

	await _settle(_frames(1.2))
	await _shot("01_tablet_only_idle")

	# Rifle must be hidden; tablet prop may be visible.
	var mixamo: Node = _find_mixamo(player)
	if mixamo != null:
		var rifle: Node3D = mixamo.get("_rifle") as Node3D
		var holster: Node3D = mixamo.get("_rifle_holster") as Node3D
		if rifle != null and rifle.visible:
			push_error("FAIL: rifle mesh visible without sidearm")
			quit(1)
			return
		if holster != null and holster.visible:
			push_error("FAIL: holster rifle visible without sidearm")
			quit(1)
			return
	await _shot("02_no_rifle_close")

	# Hotwire mini-game UI (do not auto-solve — show the tablet puzzle).
	if mg != null:
		mg.set("auto_solve", false)
		# Fire-and-forget play; capture mid-puzzle then cancel.
		mg.call("play", false)
		await _settle(_frames(1.5))
		await _shot("03_hotwire_minigame")
		if mg.has_method("_on_cancel"):
			mg.call("_on_cancel")
		await _settle(_frames(0.4))

	# Soft-lock prompt at east exit.
	var door: Node = gate.get_node_or_null("ExitDoor")
	if door != null and player != null:
		player.global_position = (door as Node3D).global_position + Vector3(-1.2, 0.0, 0.0)
		if view != null and view.has_method("snap_to_target"):
			view.call("snap_to_target")
		await _settle(_frames(0.8))
		await _shot("04_access_panel_approach")

	# Loading overlay during a real SceneRouter transition.
	if sr != null and gs != null:
		gs.set("next_room_id", "stargate_corridor_east_connector")
		# Don't await full change — capture while overlay is up.
		sr.call("change_to", "res://scenes/room.tscn", "FromGateRoom")
		await _settle(_frames(0.6))
		await _shot("05_loading_overlay")
		# Wait until transition settles or timeout.
		var waited: int = 0
		while bool(sr.get("is_transitioning")) and waited < _frames(12.0):
			await _settle(1)
			waited += 1
		await _settle(_frames(0.8))
		await _shot("06_after_transition")

	print("=== weapons_tools_verify: keyframes OK → %s ===" % OUT_DIR)
	quit(0)


func _find_mixamo(player: Node) -> Node:
	var model: Node = player.get_node_or_null("Model")
	if model == null:
		return null
	for c in model.get_children():
		if String(c.name).begins_with("Mixamo") or c.has_method("set_weapon_visible"):
			return c
	return null


func _frames(seconds: float) -> int:
	return maxi(1, int(round(seconds * FPS)))


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(name: String) -> void:
	await _settle(2)
	var path: String = "%s/%s.png" % [OUT_DIR, name]
	var img: Image = get_root().get_viewport().get_texture().get_image()
	if img == null:
		push_error("shot %s: no image" % name)
		return
	img.save_png(path)
	print("[shot] ", path)
