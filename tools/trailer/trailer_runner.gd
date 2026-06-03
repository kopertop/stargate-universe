extends Node

# Automated gameplay-trailer driver.
#
# Drives the REAL gameplay pipeline AS IF A PLAYER WERE PLAYING: the character
# physically walks across each room to a door and presses "interact" (the same
# Door.interact() the player triggers with E, which opens the leaves, walks the
# last step, and cross-fades), walks up to NPCs/consoles before talking, and
# steps through the Stargate on foot. The third-person follow camera trails the
# movement, so the footage shows continuous play, not teleport cuts.
#
# Recording is Godot's built-in Movie Maker (the launcher passes --write-movie);
# this script drives the action AND renders all trailer text in-engine (captions,
# title/end cards) so Movie Maker bakes it into the footage. It also emits a
# caption beat sidecar (user://trailer_beats.json) used for the draft social post.
#
# Lives as a direct child of /root (sibling to autoloads) so it survives
# SceneRouter.change_to() freeing current_scene. Bootstrapped from
# tools/trailer/trailer.tscn (see tools/trailer/bootstrap.gd).
#
# Env knobs (set by the launcher, mirroring the PLAYTHROUGH_* convention):
#   TRAILER_REEL       "e1_highlight" (default) | "e1_full"
#   TRAILER_FPS        fixed-fps the launcher passed to --fixed-fps (default 60)
#   TRAILER_BEATS      absolute path for the beat sidecar
#   TRAILER_CAPTIONS   "0" to disable on-screen captions
#   TRAILER_GAME_NAME / TRAILER_TAGLINE / TRAILER_CTA  card text

const SETTLE_FRAMES: int = 6
const TIMEOUT_SEC: float = 360.0
# Brisk travel pace. Movement is physics-based (move_and_slide in _physics_process),
# which Movie Maker steps at a FIXED rate independent of Engine.time_scale — so the
# walk speed itself (m/s), not time_scale, is what compresses traversal frames. A
# higher value = fewer recorded frames crossing each room (reads as a fast jog).
const WALK_SPEED: float = 12.0
# A walk that hasn't arrived after this many frames is force-stopped so the reel
# can't hang on a snagged prop (the door/interact still fires from where we are).
const WALK_MAX_FRAMES: int = 600
# Baseline Engine.time_scale for the reel body. Under Movie Maker this compresses
# PROCESS-based time (scene-router cross-fades, the gate-room arrival cinematic,
# animation playback) — NOT physics movement (that's governed by WALK_SPEED). Kept
# modest so fades read as quick rather than glitchy; dialogue/captions drop to 1.0.
# Bumped to 3.0 to match the ~12 m/s travel pace (keeps the walk-anim cadence in
# step with the faster movement so the feet don't slide).
const WALK_SPEEDUP: float = 3.0
# How long a caption holds when nothing else is happening (most captions ride
# through the following walk, so this stays short).
const HOLD_SEC: float = 1.0

var _reel: String = "e1_highlight"
var _fps: float = 60.0
var _beats_path: String = "user://trailer_beats.json"
var _beats: Array[Dictionary] = []

# Branding (set by the launcher). All trailer text is rendered IN-ENGINE and
# baked into the recording by Movie Maker — ffmpeg `drawtext` is an optional
# build feature missing from many ffmpeg builds, so we never depend on it.
var _captions_on: bool = true
var _game_name: String = "STARGATE UNIVERSE"
var _tagline: String = ""
var _title_sub: String = ""   # title-card subtitle (e.g. "Real gameplay footage, captured <date>")
var _cta: String = "Wishlist now"

# Video timeline in seconds. Movie Maker records exactly ONE frame per rendered
# frame, so OUTPUT seconds = frames / fps — independent of Engine.time_scale
# (which changes how much WORLD time passes per frame, i.e. walk speed, not the
# output frame count). Counting frames (not summing delta) keeps the beat sidecar
# aligned with the real MP4 even while traversals are time-lapsed.
var _frames: int = 0
var _video_time: float = 0.0
var _started: bool = false
var _done: bool = false
# Baseline Engine.time_scale for the reel body: travel, fades, scene loads and
# settles all run time-lapsed at this rate. Caption holds + dialogue drop to 1.0
# (see _hold / _walk_to_node) so the viewer can read them. Set after the title.
var _base_scale: float = 1.0

# In-engine overlay: title/end card + bottom caption, above every gameplay layer.
var _overlay: CanvasLayer = null
var _card: ColorRect = null
var _card_title: Label = null
var _card_sub: Label = null
var _caption: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_begin")


func _process(_delta: float) -> void:
	if _started and not _done:
		_frames += 1
		_video_time = float(_frames) / _fps


func _begin() -> void:
	if _started:
		return
	_started = true
	_reel = OS.get_environment("TRAILER_REEL")
	if _reel == "":
		_reel = "e1_highlight"
	var fps_env: String = OS.get_environment("TRAILER_FPS")
	if fps_env != "" and fps_env.is_valid_float():
		_fps = maxf(fps_env.to_float(), 1.0)
	var beats_env: String = OS.get_environment("TRAILER_BEATS")
	if beats_env != "":
		_beats_path = beats_env
	_captions_on = OS.get_environment("TRAILER_CAPTIONS") != "0"
	var name_env: String = OS.get_environment("TRAILER_GAME_NAME")
	if name_env != "":
		_game_name = name_env
	_tagline = OS.get_environment("TRAILER_TAGLINE")
	_title_sub = OS.get_environment("TRAILER_TITLE_SUB")
	if _title_sub == "":
		_title_sub = _tagline
	var cta_env: String = OS.get_environment("TRAILER_CTA")
	if cta_env != "":
		_cta = cta_env

	print("=== gameplay trailer runner — reel '", _reel, "' @ ", _fps, "fps ===")
	_build_overlay()

	# Visible fades, letterbox and in-engine cinematics — full presentation.
	SceneRouter.instant_mode = false
	# Isolate save I/O BEFORE any autosave fires. Movie Maker runs NON-headless,
	# so SaveManager's headless auto-redirect does NOT trigger — without this the
	# trailer would autosave over the player's real save.
	SaveManager.configure_test_paths("trailer_save")
	# ignore_time_scale=true so the walk time-lapse can't shorten the safety net.
	get_tree().create_timer(TIMEOUT_SEC, true, false, true).timeout.connect(_on_timeout)
	GameState.reset()

	match _reel:
		"e1_full":
			await _drive_full()
		_:
			await _drive_highlight()

	await _finish()


# --- reels ---------------------------------------------------------------

# Curated reel: walk the opening on foot (arrival → Scott → corridors → Rush),
# then jump to the gate-open beat and walk the away-mission payoff (Stargate →
# alien world → mine → home). Real movement throughout; the camera trails.
func _drive_highlight() -> void:
	await _title_card(2.0)
	_set_base(WALK_SPEEDUP)   # time-lapse the body; holds/dialogue drop to 1.0

	await _arrive("res://scenes/gate_room.tscn", "FromGate")
	await _beat("Stranded billions of light-years from home.")
	await _hold(HOLD_SEC)

	await _walk_to_node(_find_node_named("LtScott"), "talk to Scott")
	var scott: Node = _find_node_named("LtScott")
	if scott != null:
		scott.set("auto_greet", false)
		scott.set_process(false)
	await _beat("The crew of Destiny needs a way to survive.")
	await _hold(HOLD_SEC)

	await _travel_path([
		"stargate_corridor_east_connector", "east_corridor", "north_corridor",
		"control_approach_north", "control_interface_room",
	])
	await _walk_to_node(_find_node_named("DrRush"), "talk to Rush")
	await _beat("Dr Rush has a desperate plan.")
	await _hold(HOLD_SEC)

	# Jump the quest to the gate-open away mission (skip the crisis middle), then
	# walk the payoff on foot.
	_setup_gate_open_state()
	await _travel_path([
		"control_approach_north", "north_corridor", "east_corridor",
		"stargate_corridor_east_connector", "gate_room",
	])
	await _beat("The Stargate dials an uncharted world.")
	await _hold(HOLD_SEC)

	await _activate_gate(_find_planet_gate("to_planet"), "step through the gate")
	await _beat("Step through to a world never before charted.")
	await _hold(HOLD_SEC)

	await _beat("Mine the lime that keeps Destiny breathing.")
	var mined: int = 0
	for node in _find_resource_nodes():
		await _walk_to_node(node, "mine lime")
		mined += 1
		if GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
			break
	await _hold(HOLD_SEC)

	await _activate_gate(_find_planet_gate("to_ship"), "return home")
	await _beat("Home — for now.")
	await _hold(HOLD_SEC)


# Faithful end-to-end run of the E1 spine, walked on foot throughout.
func _drive_full() -> void:
	await _title_card(2.0)
	_set_base(WALK_SPEEDUP)

	await _arrive("res://scenes/gate_room.tscn", "FromGate")
	await _beat("The crew wakes to a failing ship.")
	await _hold(HOLD_SEC)
	await _walk_to_node(_find_node_named("LtScott"), "talk to Scott")
	var scott: Node = _find_node_named("LtScott")
	if scott != null:
		scott.set("auto_greet", false)
		scott.set_process(false)
	await _beat("Lieutenant Scott sends you to find Dr Rush.")
	await _hold(HOLD_SEC)

	await _travel_path([
		"stargate_corridor_east_connector", "east_corridor", "north_corridor",
		"control_approach_north", "control_interface_room",
	])
	await _walk_to_node(_find_node_named("DrRush"), "talk to Rush")
	await _beat("Rush: the air won't last. Rest, then we work.")
	await _hold(HOLD_SEC)

	await _travel_path(["cr_corridor_2", "eli_quarters"])
	await _walk_to_node(_find_node_named("KinoPickup"), "pick up the Kino")
	await _wait_until(func() -> bool: return Inventory.has("kino_remote"), "Kino acquisition", 120)
	await _beat("A Kino — Destiny's flying recon eye.")
	await _hold(HOLD_SEC)
	await _walk_to_node(_find_node_named("Bed"), "rest")
	await _beat("Then the air crisis hits.")
	await _hold(HOLD_SEC)

	await _travel_path(["cr_corridor_2", "control_interface_room"])
	await _walk_to_node(_find_node_named("ControlConsoleEast"), "work the terminal")
	KinoRemote.close_remote()
	await _beat("Life support is venting. Find the breach.")
	await _hold(HOLD_SEC)

	await _travel_path(["control_approach_south", "south_corridor", "south_spur", "breached_section_south"])
	await _walk_to_node(_find_node_named("ShuttleDoorPanel"), "examine the dead panel")
	await _walk_to_node(_find_node_named("ShuttleCrate2"), "search for a fuse")
	await _walk_to_node(_find_node_named("ShuttleDoorPanel"), "seal the breach")
	await _beat("Seal the breach.")
	await _hold(HOLD_SEC)

	await _travel_path(["south_spur", "south_corridor"])
	await _walk_to_node(_find_node_named("ScrubberRush"), "the scrubber reveal")
	await _beat("Only lime can fix the scrubber — and the gate just dialed itself.")
	await _hold(HOLD_SEC)

	await _travel_path(["east_corridor", "stargate_corridor_east_connector", "gate_room"])
	GameState.acquire_kino_orb()
	GameState.complete_kino_scout()
	await _beat("Scout the world. Open the gate.")
	await _hold(HOLD_SEC)

	await _activate_gate(_find_planet_gate("to_planet"), "step through the gate")
	await _beat("Step through to an uncharted world.")
	await _hold(HOLD_SEC)
	var mined: int = 0
	for node in _find_resource_nodes():
		await _walk_to_node(node, "mine lime")
		mined += 1
		if GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
			break
	await _beat("Mine the lime that keeps Destiny alive.")
	await _hold(HOLD_SEC)

	await _activate_gate(_find_planet_gate("to_ship"), "return home")
	await _travel_path(["stargate_corridor_east_connector", "east_corridor", "south_corridor"])
	await _walk_to_node(_find_node_named("CO2Scrubber"), "repair the scrubber")
	await _beat("Destiny breathes again.")
	await _hold(HOLD_SEC)


# Set the minimal world-state to land the quest on MINE_LIME with the gate OPEN,
# without driving the slow crisis middle. QuestLog re-derives the active step
# purely from predicates over these flags (quest_log.gd::_evaluate_predicate),
# so satisfying every predicate up to (not including) mine_lime's lands us there.
func _setup_gate_open_state() -> void:
	var gs: Object = GameState
	gs.met_scott = true
	gs.met_rush = true
	gs.eli_quarters_visited = true
	gs.air_crisis_started = true
	gs.control_room_returned = true
	gs.life_support_diagnosed = true
	(gs.breaches_sealed as Array).append("breach_a")
	gs.scrubber_diagnosed = true
	gs.ftl_drop_triggered = true
	gs.reported_to_gate = true
	gs.kino_scout_done = true
	gs.lime_planet_dialed = true
	gs.away_party_briefed = true
	if not Inventory.has("kino_remote"):
		Inventory.add_item("kino_remote", 1)
	gs.build_air_lime_spec()
	gs.advance_air_quest()
	if gs.quest_step != gs.QUEST_MINE_LIME:
		push_warning("trailer: expected quest_step MINE_LIME, got '%s'" % gs.quest_step)


# --- movement (drives the player on foot, as a player would) -------------

# Enter a hand-authored scene (gate room) the first time. Door-to-door legs use
# the real Door.interact() path instead (see _go_through_door).
func _arrive(scene_path: String, spawn: String) -> void:
	SceneRouter.change_to(scene_path, spawn)
	await SceneRouter.scene_changed
	await _settle()


# Walk the player to a node and press interact — the same thing a player does:
# cross the floor on foot, then trigger the interactable. The follow camera is
# swung behind the approach so the walk reads cleanly.
func _walk_to_node(node: Node, label: String) -> void:
	if node == null:
		push_warning("trailer: " + label + ": missing interactable")
		return
	if not (node is Node3D):
		push_warning("trailer: " + label + ": not a Node3D")
		return
	var target: Vector3 = (node as Node3D).global_position
	await _walk_near(target, 1.7)
	_aim_camera_at(target)
	# Drop to real time for the interaction/dialogue beat so it's readable.
	Engine.time_scale = 1.0
	if node.has_method("interact"):
		node.call("interact", _player())
	# A choice-tree NPC opens a DialogScreen (spawned DEFERRED by hud.gd, which is
	# why dismissing immediately used to race it and leave it lingering). Wait for
	# it, show it a length-scaled 1-3s, then close() it cleanly.
	var screen: Node = await _await_dialog_screen(20)
	if screen != null:
		await _hold(_dialog_seconds(screen), false)   # keep the box up for the beat
		if screen.has_method("close"):
			screen.call("close")
	_dismiss_dialogs()
	await _settle()
	Engine.time_scale = _base_scale


# Walk across the current room, right up to the door leading to `target_room_id`,
# then cross-fade through. We drive the approach walk ourselves (frame-capped, so
# a snag can never hang the reel) and trigger the transition directly rather than
# via Door.interact() — Door._transition() does `await auto_walk_finished`, which
# deadlocks the recording if the player snags on geometry (the reason the QA
# playthrough bypasses door walk-ups). SceneRouter's spawn-side walk still steps
# the player OUT into the next room, so arrivals read as real play too.
func _go_through_door(target_room_id: String) -> void:
	var door: Door = _find_door_to_room(target_room_id)
	if door == null:
		push_warning("trailer: could not find door to room " + target_room_id)
		return
	# Approach the door HEAD-ON, never from the side, and stop a SAFE distance out
	# so the player never pushes into the (closed) door collider and "bounces". The
	# leaves face the door's local ±Z, so the pass-through axis is basis.z — walk to
	# a point on that axis on the player's side. Then swing the leaves open for the
	# shot and let the cross-fade sell the step-through (we never need to physically
	# reach the door, which is what caused the collision bounce).
	var front: Vector3 = _door_front_approach(door, 1.7)
	await _walk_near(front, 0.3)
	_aim_camera_at(door.global_position)
	if door.has_method("_toggle"):
		door.call("_toggle")            # animate the leaves open
	await _hold(0.5, false)             # let them open before the fade
	_route_through(door)
	await SceneRouter.scene_changed
	await _settle()


# A point `offset` metres directly in FRONT of the door, on whichever side the
# player currently stands. The door's pass-through axis is its local Z; projecting
# onto it (instead of the raw player→door line) keeps the approach square to the
# doorway so the player walks THROUGH the front rather than into the side/wall.
func _door_front_approach(door: Door, offset: float) -> Vector3:
	var axis: Vector3 = door.global_transform.basis.z
	axis.y = 0.0
	var p: CharacterBody3D = _player()
	if axis.length() < 0.01 or p == null:
		# Degenerate basis — fall back to the player→door line.
		var fb: Vector3 = (p.global_position - door.global_position) if p != null else Vector3.FORWARD
		fb.y = 0.0
		if fb.length() < 0.01:
			fb = Vector3.FORWARD
		return door.global_position + fb.normalized() * offset
	axis = axis.normalized()
	var to_player: Vector3 = p.global_position - door.global_position
	to_player.y = 0.0
	var side: float = signf(to_player.dot(axis))
	if side == 0.0:
		side = 1.0
	var pt: Vector3 = door.global_position + axis * side * offset
	pt.y = p.global_position.y
	return pt


# Trigger a door's scene transition directly (mirrors Door._route_to_destination)
# WITHOUT the awaited walk-up coroutine.
func _route_through(door: Door) -> void:
	if door.source_room_id != "" and door.target_room_id != "":
		GameState.mark_door_traversed(door.source_room_id, door.target_room_id)
	if door.target_room_id != "":
		if door.target_room_id == "gate_room":
			SceneRouter.change_to("res://scenes/gate_room.tscn", door.target_spawn)
		else:
			GameState.next_room_id = door.target_room_id
			SceneRouter.change_to("res://scenes/room.tscn", door.target_spawn)
	else:
		SceneRouter.change_to(door.target_scene, door.target_spawn)


func _travel_path(room_ids: Array) -> void:
	for room_id in room_ids:
		await _go_through_door(String(room_id))


# Walk the player to a point `stop_dist` short of `world_target`, on the player's
# side, with the follow camera trailing.
#
# Arrival is EVENT/THRESHOLD based, not "let auto_walk decide": at high WALK_SPEED
# the per-frame step (speed/fps) exceeds the body's _auto_walk_arrive_dist (0.18),
# so auto_walk overshoots and ping-pongs around the target (the "bounce"). We watch
# the distance ourselves and stop the instant we're within an arrival BAND sized to
# the step length, then re-target to the current position so _drive_auto_walk
# settles to idle in a single frame — no overshoot, no oscillation.
func _walk_near(world_target: Vector3, stop_dist: float) -> void:
	var p: CharacterBody3D = _player()
	if p == null:
		return
	var flat_target: Vector3 = Vector3(world_target.x, p.global_position.y, world_target.z)
	var to_target: Vector3 = flat_target - p.global_position
	to_target.y = 0.0
	# Arrival band: must exceed one per-frame step or the body can't land inside it.
	var band: float = maxf(0.30, WALK_SPEED / _fps * 1.6)
	if to_target.length() <= stop_dist + band:
		_aim_camera_at(world_target)
		return
	var approach: Vector3 = flat_target - to_target.normalized() * stop_dist
	_aim_camera_at(world_target)
	Engine.time_scale = WALK_SPEEDUP        # time-lapse the traversal only
	var debug: bool = OS.get_environment("TRAILER_DEBUG_WALK") != ""
	p.call("auto_walk_to", approach, WALK_SPEED)
	var f: int = 0
	while f < WALK_MAX_FRAMES:
		await get_tree().process_frame
		f += 1
		if p.get("_auto_walking") != true:
			break                           # auto_walk arrived on its own (low speed)
		var d: float = _flat_dist(p.global_position, approach)
		if debug:
			print("    [walk] f=%d d=%.3f" % [f, d])
		if d <= band:
			break                           # within band — stop BEFORE the overshoot cycle
	if p.get("_auto_walking") == true:
		# Clean halt: target the current spot so the next frame settles to idle
		# (dist 0 < arrive_dist) instead of stepping past and reversing.
		p.call("auto_walk_to", p.global_position, WALK_SPEED)
		await get_tree().process_frame
	Engine.time_scale = _base_scale         # back to the reel baseline


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# Walk to the Stargate / return gate on foot, then trigger the crossing — the
# walk sells the approach, the cross-fade sells the step-through.
func _activate_gate(gate: Node, label: String) -> void:
	if gate == null:
		push_warning("trailer: " + label + ": missing gate trigger")
		return
	if gate is Node3D:
		await _walk_near((gate as Node3D).global_position, 2.0)
	var mode: String = String(gate.get("mode"))
	var scene_path: String = String(gate.get("target_scene"))
	var spawn: String = String(gate.get("target_spawn"))
	if scene_path == "":
		push_warning("trailer: " + label + ": gate has no target_scene")
		return
	if mode == "to_planet":
		if not GameState.can_travel_to_lime_planet():
			push_warning("trailer: " + label + ": travel not allowed")
			return
	elif mode == "to_ship":
		GameState.return_from_lime_planet()
	SceneRouter.change_to(scene_path, spawn)
	await SceneRouter.scene_changed
	await _settle()


# Swing the third-person follow camera behind the direction the player is about
# to walk, so the move is framed from behind instead of side-on. view.gd lerps
# rotation toward camera_rotation, so this reads as a smooth camera settle.
func _aim_camera_at(world_target: Vector3) -> void:
	var p: Node = _player()
	if p == null:
		return
	var v: Node = p.get("view")
	if v == null or not (p is Node3D):
		return
	var dir: Vector3 = world_target - (p as Node3D).global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	var cr: Vector3 = v.get("camera_rotation")
	cr.y = rad_to_deg(atan2(-dir.x, -dir.z))
	v.set("camera_rotation", cr)


func _set_base(scale: float) -> void:
	_base_scale = scale
	Engine.time_scale = scale


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
		_dismiss_dialogs()


func _wait_until(predicate: Callable, label: String, max_frames: int = 120) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await get_tree().process_frame
	_dismiss_dialogs()
	push_warning("trailer: " + label + " timed out")
	return false


# --- beat clock + sidecar ------------------------------------------------

func _beat(caption: String) -> void:
	_beats.append({"t": _video_time, "caption": caption})
	if _captions_on and _caption != null:
		_caption.text = caption
		_caption.visible = true
	print("  beat @ %.2fs  %s" % [_video_time, caption])


func _hold(seconds: float, dismiss: bool = true) -> void:
	# Holds are caption/card moments — show them at real time so they read,
	# regardless of the travel time-lapse baseline. `dismiss` clears stray dialog
	# panels each frame; pass false to HOLD an open DialogScreen (the dialog beat).
	var prev: float = Engine.time_scale
	Engine.time_scale = 1.0
	var frames: int = int(round(seconds * _fps))
	for i in frames:
		await get_tree().process_frame
		if dismiss:
			_dismiss_dialogs()
	Engine.time_scale = prev


func _write_beats() -> void:
	var doc: Dictionary = {
		"fps": _fps,
		"duration": _video_time,
		"reel": _reel,
		"beats": _beats,
	}
	var f: FileAccess = FileAccess.open(_beats_path, FileAccess.WRITE)
	if f == null:
		print("  beat sidecar FAILED to open → ", _beats_path)
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("  beat sidecar → ", _beats_path, " (", _beats.size(), " beats, ", "%.2fs" % _video_time, ")")


func _finish() -> void:
	_set_base(1.0)                          # end card at real time; never leave ramped
	await _end_card(2.5)
	_done = true
	_write_beats()
	print("=== trailer reel complete — quitting ===")
	get_tree().quit(0)


# --- in-engine overlay (captions + cards) --------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "TrailerOverlay"
	_overlay.layer = 70                       # above HUD + Cinematic letterbox (60)
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	_card = ColorRect.new()
	_card.color = Color(0.02, 0.027, 0.051, 1.0)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_overlay.add_child(_card)

	var vb: VBoxContainer = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	_card.add_child(vb)

	_card_title = _make_label(64, Color(0.95, 0.97, 1.0))
	vb.add_child(_card_title)
	_card_sub = _make_label(28, Color(0.62, 0.88, 0.63))
	vb.add_child(_card_sub)

	_caption = _make_label(38, Color(0.95, 0.97, 1.0))
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = 80.0
	_caption.offset_right = -80.0
	_caption.offset_top = -150.0
	_caption.offset_bottom = -64.0
	_caption.visible = false
	_overlay.add_child(_caption)


func _make_label(size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _title_card(seconds: float) -> void:
	if _caption != null:
		_caption.visible = false
	if _card != null:
		_card_title.text = _game_name
		_card_sub.text = _title_sub
		_card.visible = true
	await _hold(seconds)
	if _card != null:
		_card.visible = false


func _end_card(seconds: float) -> void:
	if _caption != null:
		_caption.visible = false
	if _card != null:
		_card_title.text = _game_name
		_card_sub.text = _cta
		_card.visible = true
	await _hold(seconds)


# --- discovery -----------------------------------------------------------

func _player() -> CharacterBody3D:
	var n: Node = get_tree().get_first_node_in_group("player")
	return n as CharacterBody3D


func _find_door_to_room(target_room_id: String) -> Door:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Door and (n as Door).target_room_id == target_room_id:
			return n
	return null


func _find_node_named(node_name: String) -> Node:
	return _find_node_named_in(get_tree().current_scene, node_name)


func _find_node_named_in(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found: Node = _find_node_named_in(child, node_name)
		if found != null:
			return found
	return null


func _find_resource_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group("interactable"):
		var script: Script = n.get_script()
		if script != null and script.resource_path.ends_with("resource_node.gd"):
			out.append(n)
	return out


func _find_planet_gate(mode: String) -> Node:
	for n in get_tree().get_nodes_in_group("planet_gate"):
		if String(n.get("mode")) == mode:
			return n
	return null


# Poll up to max_frames for a DialogScreen to appear (hud spawns it deferred).
# Returns the node, or null if none opens (simple-line / non-dialog interactables).
func _await_dialog_screen(max_frames: int) -> Node:
	for i in max_frames:
		var s: Node = _find_dialog_screen(get_tree().root)
		if s != null:
			return s
		await get_tree().process_frame
	return _find_dialog_screen(get_tree().root)


func _find_dialog_screen(root: Node) -> Node:
	if root == null:
		return null
	var script: Script = root.get_script()
	if script != null and script.resource_path.ends_with("dialog_screen.gd"):
		return root
	for child in root.get_children():
		var found: Node = _find_dialog_screen(child)
		if found != null:
			return found
	return null


# Seconds to hold a dialog box: scaled to the line length (~22 chars/sec reading),
# clamped to 1-3s so a trailer never lingers on a conversation.
func _dialog_seconds(screen: Node) -> float:
	var line: Node = screen.get_node_or_null("Window/Margin/VBox/BodyPanel/BodyScroll/Line")
	var n: int = 0
	if line != null:
		n = String(line.get("text")).length()
	return clampf(float(n) / 22.0, 1.0, 3.0)


func _dismiss_dialogs() -> void:
	if get_tree().paused:
		get_tree().paused = false
	_free_dialog_screens(get_tree().root)


func _free_dialog_screens(root: Node) -> void:
	if root == null:
		return
	var script: Script = root.get_script()
	if script != null and script.resource_path.ends_with("dialog_screen.gd"):
		root.queue_free()
		return
	for child in root.get_children():
		_free_dialog_screens(child)


func _on_timeout() -> void:
	print("\n!!! TIMEOUT after ", TIMEOUT_SEC, "s — trailer run hung")
	_done = true
	_write_beats()
	get_tree().quit(1)
