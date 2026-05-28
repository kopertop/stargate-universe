class_name PlanetDepartureTimer
extends Node

# Phase F: the planet departure countdown for a lime-mining run. Destiny WILL
# jump back to FTL, so the away team has a limited window on the surface. This
# is a focused, planet-only countdown (NOT the full event-bus Timer service in
# design/gdd/timer-pressure-system.md). At 0:00 it plays a short "rush back
# through the gate" letterbox cutscene, then recalls the team to the ship with
# whatever lime they gathered — E1 has NO stranding.
#
# Added to the planet scene by planet.gd only on the player mining run (quest
# MINE_LIME, never the Kino scout). Skips itself entirely in instant_mode so
# headless tests don't run a live clock or cinematic.

const DURATION: float = 600.0      # 10 minutes
const WARN_AMBER: float = 120.0    # 2 min — first warning
const WARN_RED: float = 30.0       # final warning
const RUN_SPEED: float = 13.0      # cutscene dash speed toward the gate
const ARRIVAL_DIST: float = 3.5    # within this of the gate counts as "made it"
const CUTSCENE_MAX_FRAMES: int = 720   # ~12s safety cap if a runner snags

const NORMAL_COL: Color = Color(0.82, 0.92, 1.0, 0.95)
const AMBER_COL: Color = Color(1.0, 0.72, 0.30, 1.0)
const RED_COL: Color = Color(1.0, 0.35, 0.28, 1.0)

var _remaining: float = DURATION
var _amber_fired: bool = false
var _red_fired: bool = false
var _ended: bool = false
var _label: Label = null

func _ready() -> void:
	if SceneRouter.instant_mode:
		set_process(false)
		return
	_build_hud()
	_update_label()
	GameState.add_log("Gate window open — Destiny jumps to FTL in 10 minutes. Mine what lime you can.")

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "DepartureTimerLayer"
	layer.layer = 11
	add_child(layer)
	_label = Label.new()
	_label.name = "Countdown"
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -130.0
	_label.offset_right = 130.0
	_label.offset_top = 14.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", NORMAL_COL)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.10, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)

func _process(delta: float) -> void:
	if _ended:
		return
	_remaining = maxf(0.0, _remaining - delta)
	_update_label()
	if not _amber_fired and _remaining <= WARN_AMBER:
		_amber_fired = true
		GameState.add_log("Two minutes to FTL jump. Start wrapping up.")
		Audio.play("res://sounds/radio_click.ogg")
	if not _red_fired and _remaining <= WARN_RED:
		_red_fired = true
		GameState.add_log("Thirty seconds! Everyone back to the gate!")
		Audio.play("res://sounds/radio_click.ogg")
	if _remaining <= 0.0:
		_ended = true
		_begin_departure()

func _update_label() -> void:
	if _label == null:
		return
	var mins: int = int(_remaining) / 60
	var secs: int = int(_remaining) % 60
	_label.text = "GATE WINDOW   %d:%02d" % [mins, secs]
	if _remaining <= WARN_RED:
		_label.add_theme_color_override("font_color", RED_COL)
	elif _remaining <= WARN_AMBER:
		_label.add_theme_color_override("font_color", AMBER_COL)

# Time's up: letterbox cutscene of the team scrambling back through the gate,
# then recall to the ship. Forgiving — the team keeps whatever lime they have.
func _begin_departure() -> void:
	if SceneRouter.instant_mode:
		_recall_to_ship()
		return
	await _play_departure_cutscene()
	_recall_to_ship()

func _play_departure_cutscene() -> void:
	GameState.add_log("Destiny is jumping — the away team scrambles back through the gate!")
	Audio.play("res://sounds/radio_off.ogg")
	await Cinematic.letterbox_in(0.4)
	Cinematic.set_caption("Hurry, we need to make it back before Destiny jumps to FTL!")
	var gate: Node3D = _find_return_gate()
	var gate_pos: Vector3 = gate.global_position if gate != null else Vector3.ZERO
	# High, slightly-angled overhead shot framing the gate + the team racing in.
	if gate != null:
		Cinematic.begin_camera(gate_pos + Vector3(0.0, 0.0, 10.0))
		if "active" in gate:
			gate.set("active", true)
	var runners: Array = _muster_runners(gate_pos)
	# Let them actually run the distance — wait until the lead runner reaches the
	# gate (capped, in case someone snags on terrain).
	await _await_arrival(gate_pos)
	# They vanish through the event horizon.
	for r in runners:
		if is_instance_valid(r):
			(r as Node3D).visible = false
	Cinematic.set_caption("")   # they're through — drop the "hurry" subtitle
	await Cinematic.flash(Color(0.6, 0.85, 1.0), 0.6)
	# Everyone's through — the gate shuts down behind them.
	if gate != null and "active" in gate:
		gate.set("active", false)
	Audio.play("res://sounds/break.ogg")   # gate-shutdown SFX (matches gate_room)
	await get_tree().create_timer(0.8).timeout
	# Keep the bars up THROUGH the recall; SceneRouter lifts them once the gate
	# room has faded in, so the cut reads as one continuous cinematic.
	Cinematic.close_on_next_scene_change()

# Send the player + away team dashing to the gate. Returns the runner nodes so
# the caller can hide them once they reach the event horizon.
func _muster_runners(gate_pos: Vector3) -> Array:
	var runners: Array = []
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		if player.has_method("set_input_locked"):
			player.call("set_input_locked", true)
		var target: Vector3 = gate_pos + Vector3(0.8, 0.0, 1.5)
		# Collision-free dash so the runner can't snag on terrain mid-cutscene.
		if player.has_method("cinematic_dash_to"):
			player.call("cinematic_dash_to", target, RUN_SPEED)
		elif player.has_method("auto_walk_to"):
			player.call("auto_walk_to", target, RUN_SPEED)
		runners.append(player)
	# Companions (Phase F) rush too, fanning out so they don't stack.
	var i: int = 0
	for c in get_tree().get_nodes_in_group("away_team"):
		if c is Node3D and c.has_method("rush_to"):
			c.call("rush_to", gate_pos + Vector3(-1.0 + float(i) * 1.0, 0.0, 1.5))
			i += 1
			runners.append(c)
	return runners

# Poll until the player gets to the gate (or the safety cap fires).
func _await_arrival(gate_pos: Vector3) -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var frames: int = 0
	while frames < CUTSCENE_MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
		if player == null or not is_instance_valid(player):
			return
		var planar: float = Vector2(
			player.global_position.x - gate_pos.x,
			player.global_position.z - gate_pos.z).length()
		if planar <= ARRIVAL_DIST:
			return

func _recall_to_ship() -> void:
	# Keep whatever lime was gathered. If it's enough, complete the run; else the
	# team returns empty-handed and can re-dial. Never strands anyone.
	if GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
		GameState.return_from_lime_planet()
	SceneRouter.change_to("res://scenes/gate_room.tscn", "FromGate")

func _find_return_gate() -> Node3D:
	for n in get_tree().get_nodes_in_group("planet_gate"):
		if n is Node3D and String(n.get("mode")) == "to_ship":
			return n
	return null
