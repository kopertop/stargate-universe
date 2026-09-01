extends Node

# Cold-open standoff choreography (#136), extracted from room.gd to keep the base
# room class cohesive. Stages Greer + Scott, drives them against Dr Rush on the
# find_rush dialogue cues, and owns the pause-immune StandoffCamera shots.
#
# Lives as a child of the control-interface room and reaches back through `_room`
# for shared services (player ref, DrRush lookup, _spawn_npc, _modular_model,
# room geometry). The host keeps a thin `_run_standoff_cinematic` forwarder so the
# Dr Rush `standoff_runner` Callable wiring is unchanged.
#
# Preload as a const Script in room.gd (no class_name) — class_name registration
# can lag in `-s` headless runs.

const CharacterFactoryRef: Script = preload("res://scripts/character_factory.gd")
const StandoffCameraScript: Script = preload("res://scripts/standoff_camera.gd")
const StandoffCinematicScript: Script = preload("res://scripts/standoff_cinematic.gd")

# The control-interface room that owns this director. All host state/services are
# reached through it so node parenting (StandoffCamera/Cinematic) and node names
# stay identical to the pre-extraction layout.
var _room: Node3D = null

# Cold-open standoff actors. Greer + Scott bodies that physically enter and
# choreograph against Dr Rush during the find_rush dialogue, driven by per-node
# "action" cues on GameState.dialog_action. Both run PROCESS_MODE_ALWAYS so they
# keep moving while the open dialog window has the SceneTree paused.
var _standoff_greer: Node3D = null
var _standoff_scott: Node3D = null
var _standoff_rush_pos: Vector3 = Vector3.ZERO
# Player frame captured when the standoff dialog opens (the actors are restaged
# behind the player THEN, since the player walks up to Rush well after _ready).
var _standoff_player_pos: Vector3 = Vector3.ZERO
var _standoff_player_fwd: Vector3 = Vector3.FORWARD
# Pause-immune cinematic camera live during the standoff dialog (live play
# only — never created under instant_mode).
var _standoff_cam: Node3D = null


func setup(room: Node3D) -> void:
	_room = room


# Build Greer + Scott bodies positioned relative to the player (so Greer is
# literally "right behind us"). They are silent military actors in fatigues
# (soldier.glb), each ALWAYS carrying a sidearm — interaction disabled and off the
# interact layer so the player can only talk to Rush. PROCESS_MODE_ALWAYS lets them
# keep moving while the open dialog window has the tree paused.
func spawn_actors() -> void:
	var rush_node: Node3D = _room.get_node_or_null("DrRush") as Node3D
	_standoff_rush_pos = rush_node.position if rush_node != null else Vector3(5.0, 0.0, 0.0)

	# Both soldiers wait at the SOUTH door (user blocking: they enter from it
	# and step up behind Rush on their cues).
	var door_spot: Vector3 = _south_door_spot()
	var face_rush: float = atan2(-(_standoff_rush_pos.x - door_spot.x),
		-(_standoff_rush_pos.z - door_spot.z))
	_standoff_greer = _spawn_standoff_soldier(
		"StandoffGreer", "Sgt Greer", door_spot + Vector3(0.5, 0.0, 0.0), face_rush)
	_standoff_scott = _spawn_standoff_soldier(
		"StandoffScott", "Lt Scott", door_spot + Vector3(-0.5, 0.0, 0.3), face_rush)
	# Greer arrives already carrying his rifle slung — its aimed mount is the
	# grid-verified one (the pistol never read right on camera).
	var greer_mc: Node = _room._modular_model(_standoff_greer)
	if greer_mc != null:
		greer_mc.call("set_rifle", true, false)

	if not GameState.dialog_action.is_connected(_on_standoff_cue):
		GameState.dialog_action.connect(_on_standoff_cue)
	# Restage the moment the standoff dialog opens (the player has by then
	# walked up to Rush, far from the _ready spawn point).
	if not GameState.dialog_started.is_connected(_standoff_reposition):
		GameState.dialog_started.connect(_standoff_reposition)


# The spot just inside the room's south (+Z) door — the soldiers' entrance.
# Falls back to the south wall midpoint when no +Z door exists.
func _south_door_spot() -> Vector3:
	var d_m: float = float(_room._room_data.get("height", 200)) * ShipLayout.SCALE
	var half_z: float = d_m * 0.5
	var best: Vector3 = Vector3(0.0, 0.0, half_z - 1.2)
	for c in _room.get_children():
		if c is Node3D and (c as Node3D).scene_file_path == "res://objects/door.tscn" \
				and (c as Node3D).position.z > half_z - 1.5:
			best = Vector3((c as Node3D).position.x, 0.0, (c as Node3D).position.z - 1.2)
	return best


# Snap the actors to just behind the player when the DrRush standoff dialog opens
# so Greer is literally "right behind us" wherever the player stopped — the charge
# to Rush then covers a short, punchy distance instead of the whole room.
func _standoff_reposition(npc: Node3D, _tree: Array) -> void:
	if _standoff_greer == null or not is_instance_valid(_standoff_greer):
		return
	if npc == null or npc.name != "DrRush":
		return
	_standoff_restage()
	_standoff_cinema_begin()


# Where Eli ends up for the confrontation: a couple of metres behind-right
# of Rush, watching across real distance (user: nobody crowds anybody).
func _standoff_eli_mark() -> Vector3:
	return _standoff_rush_pos + Vector3(2.0, 0.0, -1.1)


func _standoff_restage() -> void:
	# Everyone enters from the SOUTH: Eli starts just inside the door (his
	# walk-in is kicked off by the cutscene runner); the soldiers hold at
	# the doorway until their cues.
	var player: Node3D = _room.player
	var door_spot: Vector3 = _south_door_spot()
	var eli_mark: Vector3 = _standoff_eli_mark()
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if not (sr != null and sr.get("instant_mode")):
		# Keep his settled Y — snapping to y=0 dropped him a few inches onto
		# the floor collider in plain view (user render note).
		player.position = Vector3(door_spot.x, player.position.y, door_spot.z - 0.7)
		player.rotation.y = atan2(-(eli_mark.x - player.position.x),
			-(eli_mark.z - player.position.z))
	_standoff_player_pos = eli_mark
	_standoff_player_fwd = Vector3(-1.0, 0.0, 0.0)
	var face_rush: float = atan2(-(_standoff_rush_pos.x - door_spot.x),
		-(_standoff_rush_pos.z - door_spot.z))
	_standoff_greer.position = door_spot + Vector3(0.6, 0.0, 0.2)
	_standoff_greer.rotation.y = face_rush
	_standoff_scott.position = door_spot + Vector3(-0.6, 0.0, 0.4)
	_standoff_scott.rotation.y = face_rush


# Eli's entrance: he RUNS in from the south door to his mark shouting the
# warning (cinematic dash = sprint clip, collision-free so he can't snag),
# then squares up to Rush. The dash zeroes the body's collision layers —
# restore them, the cutscene hands the body back at the end.
func _standoff_eli_entrance() -> void:
	var player: Node3D = _room.player
	var mark: Vector3 = _standoff_eli_mark()
	var prev_layer: int = int(player.get("collision_layer"))
	var prev_mask: int = int(player.get("collision_mask"))
	var settled_y: float = player.position.y   # flat room — reuse on arrival
	player.call("cinematic_dash_to", mark, 5.2)
	var guard: int = 0
	while guard < 360 and is_instance_valid(player) \
			and player.position.distance_to(mark) > 0.35:
		await get_tree().process_frame
		guard += 1
	if not is_instance_valid(player):
		return
	player.set("collision_layer", prev_layer)
	player.set("collision_mask", prev_mask)
	# The dash's ground ray lands on the grate mesh top, a few inches above
	# the floor collider — restore the settled height so he doesn't visibly
	# drop when physics resumes (user render note).
	player.position.y = settled_y
	player.call("set_input_locked", true)
	player.rotation.y = atan2(-(_standoff_rush_pos.x - player.position.x),
		-(_standoff_rush_pos.z - player.position.z))


# Play the cold-open standoff as a true CUTSCENE (user direction: it offers
# only one course forward, so no dialog box) — letterbox + Space-advanced
# captions from the same tree, choreography cues + StandoffCamera shots
# underneath. Invoked by standoff_rush.gd on the live first meet only;
# instant_mode/repeat talks keep the classic dialog path.
func run_cinematic(tree: Array) -> void:
	var player: Node3D = _room.player
	if _standoff_greer == null or not is_instance_valid(_standoff_greer):
		# Actors missing (edge: reload mid-beat) — fall back to the dialog.
		GameState.dialog_started.emit(_room.get_node_or_null("DrRush") as Node3D, tree)
		return
	_standoff_restage()
	_standoff_cinema_begin(false)   # sequencer ends the camera, not dialog_closed
	_standoff_shot_rush_intro()     # cold open ON Rush working — player off-frame
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", true)
	_standoff_eli_entrance()        # Eli RUNS in from the south, shouting
	# Track the run-in once it's underway — the camera FOLLOWS him to Rush.
	get_tree().create_timer(1.0, true).timeout.connect(_standoff_shot_eli_run)
	var seq: Node = StandoffCinematicScript.new()
	seq.name = "StandoffCinematic"
	_room.add_child(seq)
	seq.call("play", tree)
	await Signal(seq, "finished")
	if player != null and is_instance_valid(player) and player.has_method("set_input_locked"):
		player.call("set_input_locked", false)
	_standoff_cinema_end()
	seq.queue_free()


# A silent standoff actor: a normal NPC (so it inherits the CharacterFactory
# ship dress — duty blacks + sidearm) PLUS a standoff-only combat helmet and the
# silent-actor flags (non-interactable, off the interact layer, ALWAYS process so
# it keeps moving while the open dialog has the tree paused).
func _spawn_standoff_soldier(npc_name: String, char_name: String, pos: Vector3, yaw: float) -> StaticBody3D:
	var body: StaticBody3D = _room._spawn_npc(npc_name, char_name, pos, yaw,
		CharacterFactoryRef.model_for(char_name, "res://models/characters/scott.glb"), [])
	# Ship dress only — NO helmets aboard Destiny (user rule); the duty
	# blacks + sidearm from the ship loadout are the whole kit.
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	body.set("enabled", false)
	body.collision_layer = 0
	return body


# Per-node dialogue cue dispatcher. Each standoff node carries an "action" that
# DialogScreen fires on GameState.dialog_action the instant it renders. Under
# instant_mode (headless playthrough) we snap end-states instead of animating so
# the sacred e1_playthrough never has to pump frames.
func _on_standoff_cue(action_id: String) -> void:
	if _standoff_greer == null or not is_instance_valid(_standoff_greer):
		return
	var instant: bool = false
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		instant = true
	match action_id:
		"standoff_greer":
			_standoff_advance_greer(instant)
		"standoff_scott":
			_standoff_enter_scott(instant)
		"standoff_rush_talks":
			_standoff_rush_talks(instant)
		"standoff_rush_leaves":
			_standoff_rush_leaves(instant)
		"standoff_eli_console":
			_standoff_eli_console(instant)
		"standoff_clear":
			_standoff_clear(instant)


# --- Standoff cinema (#136 polish) -------------------------------------------
# The standoff used to play entirely behind the open dialog panel — the camera
# stayed in gameplay framing, so Greer's charge and the drawn sidearm were
# invisible. A pause-immune StandoffCamera now pulls back at dialog-open and
# re-frames on every cue. Presentation only: instant_mode never creates it.

func _standoff_cinema_begin(hook_dialog_close: bool = true) -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	if _standoff_cam != null and is_instance_valid(_standoff_cam):
		return
	_standoff_cam = StandoffCameraScript.new()
	_standoff_cam.name = "StandoffCamera"
	_room.add_child(_standoff_cam)
	# Cutscene captions sit bottom-CENTER (no side panel) — subjects belong
	# in the middle of the frame, not biased off-axis.
	_standoff_cam.call("configure", 55.0, 0.0)
	_standoff_cam.call("activate")
	# Dialog path: the standoff plays inside ONE dialog; its close ends the
	# scene. The cinematic path ends the camera itself instead.
	if hook_dialog_close:
		GameState.dialog_closed.connect(_standoff_cinema_end, CONNECT_ONE_SHOT)
	_standoff_shot_wide()


func _standoff_cinema_end() -> void:
	if _standoff_cam != null and is_instance_valid(_standoff_cam):
		_standoff_cam.call("release")
		_standoff_cam.queue_free()
	_standoff_cam = null


func _standoff_cam_live() -> bool:
	return _standoff_cam != null and is_instance_valid(_standoff_cam)


# Cold open: Rush alone, hunched over his glowing console (also hides the
# player's snap to the south door — he stays off-frame until the wide).
func _standoff_shot_rush_intro() -> void:
	if not _standoff_cam_live():
		return
	var look: Vector3 = _standoff_rush_pos + Vector3.UP * 1.2
	_standoff_cam.call("frame", look + Vector3(-1.9, 0.5, -1.7), look, 0.1, 0.04)


# Opening two-shot: the player and Rush from the open side, pulled WIDE
# (user note: the old framing was too tight to read the scene).
func _standoff_shot_wide() -> void:
	if not _standoff_cam_live():
		return
	var eli_p: Vector3 = _standoff_player_pos + Vector3.UP * 1.2
	var rush_p: Vector3 = _standoff_rush_pos + Vector3.UP * 1.2
	var mid: Vector3 = (eli_p + rush_p) * 0.5
	var open: Dictionary = _standoff_open_side(mid, rush_p - eli_p)
	var d: float = clampf(float(open["clear"]) - 0.8, 4.5, 7.5)
	_standoff_cam.call("frame", mid + (open["dir"] as Vector3) * d + Vector3.UP * (0.8 + 0.4 * d), mid, 2.0, 0.10)


# Eli's run-in: TRACK him across the room so he stays centred all the way
# to Rush (static lane shots let walkers leave the frame — user note).
func _standoff_shot_eli_run() -> void:
	var player: Node3D = _room.player
	if not _standoff_cam_live() or player == null:
		return
	var open: Dictionary = _standoff_open_side(player.position + Vector3.UP * 1.1,
		_standoff_rush_pos - player.position)
	var d: float = clampf(float(open["clear"]) - 0.8, 4.0, 5.5)
	_standoff_cam.call("follow", player,
		(open["dir"] as Vector3) * d + Vector3.UP * (0.6 + 0.3 * d), 1.2)


# Greer's charge: TRACK him from the door to his mark behind Rush.
func _standoff_shot_greer() -> void:
	if not _standoff_cam_live() or not is_instance_valid(_standoff_greer):
		return
	var a: Vector3 = _standoff_greer.position + Vector3.UP * 1.1
	var b: Vector3 = _standoff_rush_pos + Vector3.UP * 1.25
	var open: Dictionary = _standoff_open_side((a + b) * 0.5, b - a)
	var d: float = clampf(float(open["clear"]) - 0.8, 4.0, 5.5)
	_standoff_cam.call("follow", _standoff_greer,
		(open["dir"] as Vector3) * d + Vector3.UP * (0.6 + 0.3 * d), 1.3)


# Once Greer has actually arrived and leveled the sidearm: closer two-shot of
# him squared off against Rush (the cue-time shot framed the charge lane; by
# arrival he has crossed it).
func _standoff_shot_greer_aim() -> void:
	if not _standoff_cam_live() or not is_instance_valid(_standoff_greer):
		return
	var a: Vector3 = _standoff_greer.position + Vector3.UP * 1.25
	var b: Vector3 = _standoff_rush_pos + Vector3.UP * 1.25
	var mid: Vector3 = (a + b) * 0.5
	var open: Dictionary = _standoff_open_side(mid, b - a)
	_standoff_cam.call("frame", mid + (open["dir"] as Vector3) * 3.6 + Vector3.UP * 1.3, mid, 1.4, 0.12)


# Scott's entrance: TRACK him from the door to his backup mark.
func _standoff_shot_scott(anchor: Vector3) -> void:
	if not _standoff_cam_live() or not is_instance_valid(_standoff_scott):
		return
	var a: Vector3 = _standoff_scott.position + Vector3.UP * 1.1
	var open: Dictionary = _standoff_open_side((a + anchor + Vector3.UP * 1.1) * 0.5, anchor - a)
	var d: float = clampf(float(open["clear"]) - 0.8, 4.0, 5.5)
	_standoff_cam.call("follow", _standoff_scott,
		(open["dir"] as Vector3) * d + Vector3.UP * (0.6 + 0.3 * d), 1.3)


# Rush rounding on Eli: dead-center portrait from Eli's side of the line.
func _standoff_shot_rush_talks() -> void:
	if not _standoff_cam_live():
		return
	var rush_node: Node3D = _room.get_node_or_null("DrRush") as Node3D
	if rush_node == null:
		return
	var look: Vector3 = rush_node.position + Vector3.UP * 1.3
	var dir: Vector3 = _standoff_player_pos - rush_node.position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.05 else Vector3.RIGHT
	# BETWEEN the two and off the line (Eli stands ~2.3 m out — going the
	# full distance parks the camera inside his head), Rush dead-center.
	var side: Vector3 = dir.cross(Vector3.UP)
	_standoff_cam.call("frame", look + dir * 1.8 + side * 0.9 + Vector3.UP * 0.3, look, 1.4, 0.0)


# Rush walking off: TRACK him out toward the south door so the shrug and the
# walk-away stay centred.
func _standoff_shot_rush_leaves() -> void:
	if not _standoff_cam_live():
		return
	var rush_node: Node3D = _room.get_node_or_null("DrRush") as Node3D
	if rush_node == null:
		return
	var a: Vector3 = rush_node.position + Vector3.UP * 1.25
	var b: Vector3 = _south_door_spot() + Vector3.UP * 1.1
	var open: Dictionary = _standoff_open_side(a.lerp(b, 0.35), b - a)
	var d: float = clampf(float(open["clear"]) - 0.8, 3.6, 5.0)
	_standoff_cam.call("follow", rush_node,
		(open["dir"] as Vector3) * d + Vector3.UP * 1.5, 1.8)


# Eli stepping up to the abandoned console: shot from the console's far side
# looking back at him over the live screen. HARD CUT — a glide from the
# exit-lane shot sweeps straight through the central pillar's glow.
func _standoff_shot_eli_console() -> void:
	if not _standoff_cam_live():
		return
	var look: Vector3 = _standoff_rush_pos + Vector3.UP * 1.25
	_standoff_cam.call("frame", look + Vector3(-2.6, 0.55, -1.5), look, 0.05, 0.0)


# Resolution: hold on Eli at the console (the emotional center now — Rush has
# walked off) while the soldiers disperse out the south door behind him.
func _standoff_shot_clear() -> void:
	if not _standoff_cam_live():
		return
	var look: Vector3 = _standoff_rush_pos + Vector3.UP * 1.25
	var open: Dictionary = _standoff_open_side(look, _standoff_rush_pos - _south_door_spot())
	var d: float = clampf(float(open["clear"]) - 0.8, 3.6, 5.0)
	_standoff_cam.call("frame", look + (open["dir"] as Vector3) * d + Vector3.UP * 1.4, look, 2.4, 0.0)


# Horizontal unit vector perpendicular to `axis` — the camera's "stand to the
# side of the action" direction. Falls back to +X for degenerate axes.
func _flat_side(axis: Vector3) -> Vector3:
	axis.y = 0.0
	if axis.length() < 0.01:
		return Vector3.RIGHT
	return axis.normalized().cross(Vector3.UP)


# Pick whichever perpendicular of `axis` has more open space (chest-height ray
# from the action midpoint, world layer 1) so shots pull back into the room
# instead of into the nearest console/wall — the "zoomed in too much" fix.
# Returns {"dir": Vector3, "clear": float}.
func _standoff_open_side(mid: Vector3, axis: Vector3) -> Dictionary:
	var base: Vector3 = _flat_side(axis)
	var best_dir: Vector3 = base
	var best_clear: float = 3.0
	var w3d: World3D = _room.get_world_3d()
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state if w3d != null else null
	for s in [1.0, -1.0]:
		var d: Vector3 = base * s
		var clear: float = 12.0
		if space != null:
			var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				mid + Vector3.UP * 0.3, mid + Vector3.UP * 0.3 + d * 12.0, 1)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.has("position"):
				clear = mid.distance_to(hit["position"] as Vector3)
		if clear > best_clear:
			best_clear = clear
			best_dir = d
	return {"dir": best_dir, "clear": best_clear}


# Nudge a staging spot off any geometry it would intersect (consoles, walls,
# other bodies): capsule-probe the candidate, then spiral outward in 8
# directions until clear. `ignore` bodies (the actors being staged) don't
# block their own spots.
func _clear_spot(want: Vector3, ignore: Array = []) -> Vector3:
	var player: Node3D = _room.player
	var w3d: World3D = _room.get_world_3d()
	if w3d == null:
		return want
	var space: PhysicsDirectSpaceState3D = w3d.direct_space_state
	if space == null:
		return want
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.6
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1 | 4
	var excludes: Array[RID] = []
	for body in ignore:
		if body is CollisionObject3D and is_instance_valid(body):
			excludes.append((body as CollisionObject3D).get_rid())
	if player is CollisionObject3D:
		excludes.append((player as CollisionObject3D).get_rid())
	params.exclude = excludes
	for radius in [0.0, 0.5, 1.0, 1.5, 2.0]:
		for k in range(8 if radius > 0.0 else 1):
			var ang: float = TAU * float(k) / 8.0
			var candidate: Vector3 = want + Vector3(cos(ang), 0.0, sin(ang)) * radius
			params.transform = Transform3D(Basis.IDENTITY, candidate + Vector3.UP * 0.9)
			if space.intersect_shape(params, 1).is_empty():
				return candidate
	return want


# Greer's cue: CHARGE in to the right of Rush (behind him), square off, and level
# the sidearm to aim at him. The dialogue node is held (player can't continue)
# until GameState.dialog_release fires here — i.e. until Greer has actually
# arrived and aimed.
func _standoff_advance_greer(instant: bool) -> void:
	# Well behind Rush (he faces -X; behind = +X) with the gun levelled
	# across real distance — review note: nobody crowds anybody.
	var anchor: Vector3 = _clear_spot(
		Vector3(_standoff_rush_pos.x + 2.6, 0.0, _standoff_rush_pos.z + 0.45),
		[_standoff_greer, _standoff_scott, _room.get_node_or_null("DrRush")])
	var face: float = atan2(-(_standoff_rush_pos.x - anchor.x), -(_standoff_rush_pos.z - anchor.z))
	if instant:
		_standoff_greer.position = anchor
		_standoff_greer.rotation.y = face
		_standoff_aim(_standoff_greer, true)     # sidearm to hand, leveled at Rush
		GameState.dialog_release.emit()
		return
	_standoff_shot_greer()
	_standoff_greer.call("walk_to", anchor, 6.0, 0.0)   # charge
	# Poll arrival — process_frame fires even while the dialog has the tree paused.
	# Frame ceiling guards against a soft-lock if he can't reach the anchor.
	var guard: int = 0
	while guard < 240 and is_instance_valid(_standoff_greer) \
			and _standoff_greer.position.distance_to(anchor) > 0.45:
		await get_tree().process_frame
		guard += 1
	if not is_instance_valid(_standoff_greer):
		return
	# Kill the walker BEFORE posing: its remaining arrival steps re-face the
	# travel direction and stomp the clip back to walk/idle, which is how
	# Greer ended up beside Rush, unposed, facing nowhere (live-play bug).
	_standoff_greer.call("stop_walk")
	_standoff_greer.position = anchor            # clean final mark (spot is pre-cleared)
	_standoff_greer.rotation.y = face            # square off at Rush
	_standoff_aim(_standoff_greer, true)         # draw + level the sidearm at Rush
	_standoff_shot_greer_aim()                   # tighten on the drawn weapon
	GameState.dialog_release.emit()              # now the player may continue


# Scott's cue: walk in from behind, stepping up beside the player toward the
# confrontation. His sidearm stays holstered — he's de-escalating, not aiming.
func _standoff_enter_scott(instant: bool) -> void:
	# Behind Greer and well off to one side — backing him up from distance.
	# (Greer's mark is ~2.6 m behind Rush along +X.)
	var anchor: Vector3 = _clear_spot(
		Vector3(_standoff_rush_pos.x + 4.0, 0.0, _standoff_rush_pos.z + 1.6),
		[_standoff_greer, _standoff_scott, _room.get_node_or_null("DrRush")])
	if instant:
		_standoff_scott.position = anchor
		return
	_standoff_shot_scott(anchor)
	_standoff_scott.call("walk_to", anchor, 3.4, 0.0)   # quick — he's urgent
	# Square off at Rush once he lands (walk_to faces travel direction).
	var face: float = atan2(-(_standoff_rush_pos.x - anchor.x), -(_standoff_rush_pos.z - anchor.z))
	var guard: int = 0
	while guard < 240 and is_instance_valid(_standoff_scott) \
			and _standoff_scott.position.distance_to(anchor) > 0.45:
		await get_tree().process_frame
		guard += 1
	if is_instance_valid(_standoff_scott):
		_standoff_scott.call("stop_walk")
		_standoff_scott.rotation.y = face
	# The order lands: Greer LOWERS the rifle (slings it, stands down) the
	# moment Scott is on station.
	_standoff_aim(_standoff_greer, false)


# Rush's speaking cue: he straightens off the console, rounds on Eli, and
# lets him have it — hands waving (argue clip), framed dead-center.
func _standoff_rush_talks(instant: bool) -> void:
	if instant:
		return
	var rush_node: Node3D = _room.get_node_or_null("DrRush") as Node3D
	if rush_node == null:
		return
	rush_node.rotation.y = atan2(-(_standoff_player_pos.x - rush_node.position.x),
		-(_standoff_player_pos.z - rush_node.position.z))
	var mc: Node = _room._modular_model(rush_node)
	if mc != null:
		mc.call("play_clip", "argue")
	_standoff_shot_rush_talks()


# Rush's exit cue: he turns back to the console and STABS the control (the
# point/press reach), the button CLICKS, a beat of silence hangs (his
# "Well. That's that, then." is caption-delayed to match), then he shrugs
# the whole confrontation off and walks toward the south exit.
func _standoff_rush_leaves(instant: bool) -> void:
	if instant:
		return   # presentation only — quest state already flipped at interact
	var rush_node: Node3D = _room.get_node_or_null("DrRush") as Node3D
	if rush_node == null:
		return
	rush_node.rotation.y = PI * 0.5   # back to the console (-X)
	var mc: Node = _room._modular_model(rush_node)
	if mc != null:
		mc.call("play_clip", "interact")   # the pointed press
	await get_tree().create_timer(0.7, true).timeout
	if not is_instance_valid(rush_node) or not _room.is_inside_tree():
		return
	Audio.play("res://sounds/menu_click.ogg")   # the button press
	await get_tree().create_timer(1.5, true).timeout   # ...nothing happens
	if not is_instance_valid(rush_node) or not _room.is_inside_tree():
		return
	_standoff_shot_rush_leaves()
	var door_spot: Vector3 = _south_door_spot()
	rush_node.call("walk_to", door_spot + Vector3(-1.4, 0.0, -1.6), 1.7, 0.5)


# Eli's cue: he steps into the operator spot Rush abandoned and works the
# console himself. auto_walk unlocks player input on arrival, so re-lock —
# the cutscene still owns the player until it ends.
func _standoff_eli_console(instant: bool) -> void:
	if instant:
		return
	var player: Node3D = _room.player
	_standoff_shot_eli_console()
	var mark: Vector3 = _standoff_rush_pos
	player.call("auto_walk_to", mark, 1.6)
	var guard: int = 0
	while guard < 240 and is_instance_valid(player) \
			and player.position.distance_to(mark) > 0.35:
		await get_tree().process_frame
		guard += 1
	if not is_instance_valid(player):
		return
	player.call("set_input_locked", true)
	player.rotation.y = PI * 0.5            # square up to the console (-X)
	var pmc: Node = player.get("_mc")
	if pmc != null:
		pmc.call("play_clip", "interact")


# Resolution cue: Greer lowers the weapon, both soldiers walk back out the
# south door they came through, and the actors despawn so re-entry shows
# just-Rush (the repeat dialogue).
func _standoff_clear(instant: bool) -> void:
	if instant:
		_despawn_standoff()
		return
	_standoff_shot_clear()
	_standoff_aim(_standoff_greer, false)        # holster the sidearm, stand down
	var exit_pt: Vector3 = _south_door_spot()
	_standoff_greer.call("walk_to", exit_pt + Vector3(0.45, 0.0, 0.0), 2.6, 0.2)
	_standoff_scott.call("walk_to", exit_pt + Vector3(-0.55, 0.0, 0.3), 2.6, 0.0)
	# Despawn after they have had time to clear. The timer only ticks once the
	# player closes the dialog (tree unpauses), by which point they're at the door.
	await get_tree().create_timer(4.0).timeout
	_despawn_standoff()


func _despawn_standoff() -> void:
	_standoff_cinema_end()
	# Rush has left the building: he walked out during the resolution and is
	# not talkable again until the scrubber beat (re-entry won't respawn him
	# either — _spawn_interactables gates on met_rush).
	var rush_node: Node3D = _room.get_node_or_null("DrRush") as Node3D
	if rush_node != null:
		rush_node.queue_free()
	if GameState.dialog_action.is_connected(_on_standoff_cue):
		GameState.dialog_action.disconnect(_on_standoff_cue)
	if GameState.dialog_started.is_connected(_standoff_reposition):
		GameState.dialog_started.disconnect(_standoff_reposition)
	for actor in [_standoff_greer, _standoff_scott]:
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
	_standoff_greer = null
	_standoff_scott = null


# Raise/lower a standoff actor's RIFLE between the back sling and the aimed
# hand mount (the rifle's hand transform is the grid-verified one — the
# pistol's never read right on camera). Safe under instant_mode.
func _standoff_aim(actor: Node3D, aimed: bool) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var mc: Node = _room._modular_model(actor)
	if mc != null:
		mc.call("set_rifle", true, aimed)
		mc.call("play_clip", "rifle_aim" if aimed else "idle")
		return
	# Legacy mini path.
	var holder: Node = actor.get_node_or_null("Model")
	var skel: Skeleton3D = CharacterFactoryRef._find_skeleton(holder)
	if skel == null:
		return
	CharacterFactoryRef._remove_gear(skel, "Sidearm")
	CharacterFactoryRef.attach_gear(skel, "sidearm", 2.6, aimed)
	var anim: AnimationPlayer = _find_animplayer(holder)
	if anim == null:
		return
	if aimed and anim.has_animation("holding-right-shoot"):
		anim.play("holding-right-shoot")
	elif aimed and anim.has_animation("holding-right"):
		anim.play("holding-right")
	elif anim.has_animation("idle"):
		anim.play("idle")


func _find_animplayer(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
