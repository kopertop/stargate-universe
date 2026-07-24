extends SceneTree

# Movie Maker: REAL ship demo — gate_room + Mixamo Eli + Target Lock + drone kill.
# Uses the lit Destiny gate room (not the black arena void). Does not steal the OS mouse.
#
#   tools/record_mixamo_drone_combat_demo.sh

const OUT_DIR: String = "res://screenshots/result/mixamo_drone_combat_demo"
const FPS: float = 30.0
const DRONE_SCRIPT: Script = preload("res://scripts/combat_target_drone.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mixamo_drone_combat_demo_movie (gate_room) ===")
	set_meta("demo_capture", true)
	# Prefer Eli host pack when present (falls back via MixamoHostCatalog).
	set_meta("demo_prefer_host", "eli")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "mixamo_drone_combat_demo")

	if not (
		ResourceLoader.exists("res://models/mixamo_openbot/Eli_rifle_combat.glb")
		or ResourceLoader.exists("res://models/mixamo_openbot/Swat_rifle_combat.glb")
		or ResourceLoader.exists("res://models/mixamo_openbot/YBot_rifle_combat.glb")
	):
		push_error("mixamo_drone_combat_demo: no Mixamo combat pack — rebuild locally")
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		if gs.has_method("discover_room"):
			gs.call("discover_room", "gate_room", "Gate Room")
		gs.set("met_scott", true)
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed: PackedScene = load("res://scenes/gate_room.tscn") as PackedScene
	var gate: Node = packed.instantiate()
	root.add_child(gate)
	current_scene = gate
	await _settle(50)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Hide gameplay HUD so the demo reads as combat, not pause/quest chrome.
	var hud: Node = gate.get_node_or_null("HUDLayer")
	if hud != null:
		hud.visible = false

	var player: Node3D = gate.get_node_or_null("Player") as Node3D
	var view: Node3D = gate.get_node_or_null("View") as Node3D
	if player == null:
		push_error("mixamo_drone_combat_demo: no Player")
		quit(1)
		return
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", false)

	var mixamo: Node = _find_mixamo(player)
	if mixamo == null or not bool(mixamo.call("is_combat_ready")):
		push_error("mixamo_drone_combat_demo: Mixamo not ready (expected Eli host)")
		quit(1)
		return

	# Place a hostile drone ahead of the player in the gate room corridor.
	var drone: Node3D = DRONE_SCRIPT.new() as Node3D
	drone.name = "HostileDrone"
	# ~3s+ of FIRE_RATE (0.11s) fire to kill — keep the burst readable on camera.
	drone.set("max_hp", 30)
	drone.set("drift_radius", 0.15)
	var ahead: Vector3 = player.global_position + Vector3(0.0, 1.55, -7.0)
	# Set transform before add_child so _ready caches the correct hover origin.
	drone.position = ahead
	gate.add_child(drone)
	drone.global_position = ahead
	drone.set("_origin", ahead)

	DisplayServer.window_set_size(Vector2i(1280, 720))
	if view != null and view.has_method("snap_to_target"):
		view.call("snap_to_target")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Ensure ship bed is audible in Movie Maker (gate_room ambient + Music bus).
	var md: Node = root.get_node_or_null("MusicDirector")
	if md != null and md.has_method("set_mood"):
		md.call("set_mood", "ship_calm", 0.1)

	print("[demo] gate_room + Eli + drone ready")
	print("[demo] mixamo pack=", mixamo.get("_host"))

	# Beat 1: establish character in ship
	await _settle(_frames(1.0))
	if not await _assert_character_visible("01_idle"):
		quit(1)
		return

	# Beat 2: ADS crouch ONLY — let shoulder/follow-height settle before lock.
	# Soft-point the camera at the drone without acquiring Target Lock yet.
	if player.has_method("set_demo_combat"):
		player.call("set_demo_combat", true, false)
	if view != null and view.has_method("set_combat_aiming"):
		view.call("set_combat_aiming", true, true)
	if view != null and view.has_method("snap_toward_aim_point"):
		view.call("snap_toward_aim_point", drone.call("get_lock_point"))
	await _settle(_frames(2.0))
	await _shot("02_ads_crouch")

	# Beat 3: acquire Target Lock once ADS framing is stable (crosshair == target).
	if player.has_method("set_demo_lock_target"):
		player.call("set_demo_lock_target", drone)
	if view != null and view.has_method("snap_toward_aim_point"):
		view.call("snap_toward_aim_point", drone.call("get_lock_point"))
	await _settle(_frames(1.2))
	await _shot("03_target_lock")

	# Beat 4: fire until destroyed (bolts to lock point / screen center).
	# Budget ≥3s of continuous fire (hp 30 @ 0.11s). Capture MID-burst while
	# lock is still live — a post-kill still shows free-aim floor bolts.
	if player.has_method("set_demo_combat"):
		player.call("set_demo_combat", true, true)
	var frames_left: int = _frames(5.5)
	var mid_shot_at: int = _frames(2.0)
	var took_mid: bool = false
	while frames_left > 0 and is_instance_valid(drone) and bool(drone.call("is_alive")):
		await process_frame
		frames_left -= 1
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not took_mid and frames_left <= (_frames(5.5) - mid_shot_at):
			await _shot("04_firing")
			took_mid = true
	if not took_mid:
		await _shot("04_firing")
	await _settle(_frames(0.5))

	# Beat 5: aftermath — wait long enough for scraps to hit the deck.
	if player.has_method("clear_demo_combat"):
		player.call("clear_demo_combat")
	if view != null and view.has_method("set_combat_aiming"):
		view.call("set_combat_aiming", false)
	await _settle(_frames(2.4))
	await _shot("05_destroyed")

	# Beat 6: walk toward scrap field
	Input.action_press("move_forward")
	await _settle(_frames(1.8))
	Input.action_release("move_forward")
	await _settle(_frames(0.6))
	await _shot("06_end")

	print("=== mixamo_drone_combat_demo_movie done ===")
	await _settle(_frames(0.5))
	quit(0)


func _assert_character_visible(label: String) -> bool:
	await _shot(label)
	var path: String = ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, label])
	var img: Image = Image.load_from_file(path)
	if img == null:
		push_error("demo: failed to load beat frame %s" % path)
		return false
	# Reject near-black frames (previous arena failure mode).
	var w: int = img.get_width()
	var h: int = img.get_height()
	var step: int = 8
	var bright: int = 0
	var samples: int = 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c: Color = img.get_pixel(x, y)
			var luma: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			samples += 1
			if luma > 0.08:
				bright += 1
	var ratio: float = float(bright) / float(maxi(1, samples))
	print("[demo] %s bright_ratio=%.3f" % [label, ratio])
	if ratio < 0.04:
		push_error("demo: frame too dark / no character visible (%s)" % label)
		return false
	return true


func _shot(label: String) -> void:
	await process_frame
	await process_frame
	var path: String = "%s/%s.png" % [OUT_DIR, label]
	var img: Image = root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(path))
		print("[shot] %s size=%s" % [path, str(img.get_size())])


func _frames(seconds: float) -> int:
	return maxi(1, int(round(seconds * FPS)))


func _settle(n: int) -> void:
	for _i in n:
		await process_frame
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _find_mixamo(n: Node) -> Node:
	if n.has_method("is_combat_ready") and n.has_method("tick"):
		return n
	for c in n.get_children():
		var f: Node = _find_mixamo(c)
		if f != null:
			return f
	return null
