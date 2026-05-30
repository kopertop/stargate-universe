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

const DURATION: float = 180.0      # 3 minutes — first-planet starter pressure
# Three escalating klaxon thresholds, each fires the alarm + a 3-pulse scale
# burst on the countdown label. After the 10 s alarm, the label STAYS red and
# pulses continuously until 0 (when the run-back cutscene takes over).
const WARN_60: float = 60.0
const WARN_30: float = 30.0
const WARN_10: float = 10.0
const RUN_SPEED: float = 13.0      # cutscene dash speed toward the gate
const ARRIVAL_DIST: float = 3.5    # within this of the gate counts as "made it"
const CUTSCENE_MAX_FRAMES: int = 720   # ~12s safety cap if a runner snags

const KLAXON_SOUND: String = "res://sounds/klaxon.ogg"
const PULSE_SCALE: float = 1.20    # peak of each burst pulse (+20 %)
const PULSE_HALF_TIME: float = 0.16   # seconds per half-pulse (up OR down)
const PULSE_BURSTS: int = 3        # how many up/down pulses per threshold

const NORMAL_COL: Color = Color(0.82, 0.92, 1.0, 0.95)
const AMBER_COL: Color = Color(1.0, 0.72, 0.30, 1.0)
const RED_COL: Color = Color(1.0, 0.35, 0.28, 1.0)
const DEEP_RED_COL: Color = Color(1.0, 0.20, 0.18, 1.0)

var _remaining: float = DURATION
var _warn_60_fired: bool = false
var _warn_30_fired: bool = false
var _warn_10_fired: bool = false
var _final_pulse_t: float = 0.0    # elapsed-time accumulator for the persistent post-10s pulse
# During the final 10 s, fire one klaxon per second. The threshold klaxon at
# 10 s counts as the first; subsequent klaxons fire as _remaining crosses
# each lower integer second.
var _last_klaxon_second: int = 999
var _ended: bool = false
var _label: Label = null
var _objective_label: Label = null
var _pulse_tween: Tween = null

func _ready() -> void:
	if SceneRouter.instant_mode:
		set_process(false)
		return
	_build_hud()
	_update_label()
	GameState.add_log("Gate window open — Destiny jumps to FTL in 3 minutes. Mine what lime you can.")

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
	# Scale around the label's centre so the pulse reads symmetrically. The
	# anchor span is 260 px wide; we don't know the rendered text width yet,
	# so use the control's size at the moment of pulse instead.
	_label.pivot_offset = Vector2(130.0, 14.0)
	_label.resized.connect(_recenter_pivot)

	# Lime-objective sub-label — sits just under the countdown so the player
	# can see "Collect at least N lime deposits — X/N" at a glance without
	# opening the Kino remote. Updates live on GameState.resource_changed.
	_objective_label = Label.new()
	_objective_label.name = "LimeObjective"
	_objective_label.anchor_left = 0.5
	_objective_label.anchor_right = 0.5
	_objective_label.offset_left = -180.0
	_objective_label.offset_right = 180.0
	_objective_label.offset_top = 44.0
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 16)
	_objective_label.add_theme_color_override("font_color", NORMAL_COL)
	_objective_label.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.10, 0.9))
	_objective_label.add_theme_constant_override("outline_size", 5)
	layer.add_child(_objective_label)
	_refresh_lime_objective()
	if not GameState.resource_changed.is_connected(_on_resource_changed):
		GameState.resource_changed.connect(_on_resource_changed)


func _exit_tree() -> void:
	# GameState is an autoload that outlives this Node — disconnect explicitly
	# so the signal can't hold a callable into a freed object after the
	# planet scene tears down.
	if GameState.resource_changed.is_connected(_on_resource_changed):
		GameState.resource_changed.disconnect(_on_resource_changed)


func _on_resource_changed(type: String, _count: int) -> void:
	if type == GameState.AIR_LIME_RESOURCE:
		_refresh_lime_objective()


func _refresh_lime_objective() -> void:
	if _objective_label == null:
		return
	var have: int = GameState.resource_count(GameState.AIR_LIME_RESOURCE)
	var need: int = GameState.AIR_LIME_REQUIRED
	if have >= need:
		_objective_label.text = "Lime collected — %d/%d  ✓  head back to the gate" % [have, need]
		_objective_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.50, 1.0))
	else:
		_objective_label.text = "Collect at least %d lime deposits — %d/%d" % [need, have, need]
		_objective_label.add_theme_color_override("font_color", NORMAL_COL)

func _process(delta: float) -> void:
	if _ended:
		return
	_remaining = maxf(0.0, _remaining - delta)
	_update_label()
	if not _warn_60_fired and _remaining <= WARN_60:
		_warn_60_fired = true
		GameState.add_log("One minute to FTL jump. Start wrapping up.")
		_fire_threshold_alarm(AMBER_COL)
	if not _warn_30_fired and _remaining <= WARN_30:
		_warn_30_fired = true
		GameState.add_log("Thirty seconds! Wrap it up — head for the gate.")
		_fire_threshold_alarm(RED_COL)
	if not _warn_10_fired and _remaining <= WARN_10:
		_warn_10_fired = true
		_last_klaxon_second = 10   # threshold klaxon counts as the first per-second hit
		GameState.add_log("Ten seconds! Everyone back to the gate NOW!")
		_fire_threshold_alarm(DEEP_RED_COL)
	if _warn_10_fired:
		# Per-second klaxon during the final 10 s: fire whenever the integer
		# second crosses below the last-fired one. With the threshold counted as
		# 10, we get klaxons at 10 / 9 / 8 / 7 / 6 / 5 / 4 / 3 / 2 / 1 — ten
		# total — escalating the urgency into the cutscene.
		var current_second: int = int(ceil(_remaining))
		if current_second < _last_klaxon_second and current_second >= 1:
			Audio.play(KLAXON_SOUND)
			_last_klaxon_second = current_second
		# Persistent pulse for the final 10 s — drives the label's scale via a
		# sin() so it breathes between 1.0× and 1.2× until the cutscene fires.
		_final_pulse_t += delta
		if _label != null:
			var s: float = 1.0 + 0.1 * (1.0 + sin(_final_pulse_t * 9.0))
			# 1.0 + 0.1*(1+sin) → [1.0, 1.2] envelope
			_label.scale = Vector2(s, s)
	if _remaining <= 0.0:
		_ended = true
		_begin_departure()


# Sound + 3-pulse scale burst on the countdown label. Pulses run on a Tween,
# so they don't block _process. Color step is applied immediately — the
# threshold's "base" color persists between bursts.
func _fire_threshold_alarm(base_color: Color) -> void:
	Audio.play(KLAXON_SOUND)
	if _label == null:
		return
	_label.add_theme_color_override("font_color", base_color)
	# Cancel any prior burst-pulse so a new threshold restarts cleanly. The
	# persistent post-10s pulse uses _process directly, not a Tween, so
	# killing the Tween here doesn't affect it.
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	# The persistent post-10s pulse takes over _label.scale via _process; while
	# it's active, a Tween-based burst would fight it. The threshold ordering
	# (60 → 30 → 10) means each threshold's burst finishes BEFORE the persistent
	# pulse kicks in (the 10s alarm starts both at the same instant, and the
	# burst is short — ~1 s — but the persistent _process write would clobber
	# the Tween every frame). Avoid the conflict by skipping the burst at the
	# 10 s threshold and letting the persistent pulse carry the visual.
	if _warn_10_fired:
		return
	_recenter_pivot()
	_pulse_tween = create_tween()
	for i in PULSE_BURSTS:
		_pulse_tween.tween_property(_label, "scale",
				Vector2(PULSE_SCALE, PULSE_SCALE), PULSE_HALF_TIME)
		_pulse_tween.tween_property(_label, "scale",
				Vector2.ONE, PULSE_HALF_TIME)


# Keep the label's pivot at its visual centre so scale tweens pulse from the
# middle of the text rather than the top-left corner.
func _recenter_pivot() -> void:
	if _label == null:
		return
	_label.pivot_offset = _label.size * 0.5


func _update_label() -> void:
	if _label == null:
		return
	var mins: int = int(_remaining) / 60
	var secs: int = int(_remaining) % 60
	_label.text = "GATE WINDOW   %d:%02d" % [mins, secs]
	# Color steps that PERSIST between threshold flashes (not just the burst).
	if _warn_10_fired:
		_label.add_theme_color_override("font_color", DEEP_RED_COL)
	elif _warn_30_fired:
		_label.add_theme_color_override("font_color", RED_COL)
	elif _warn_60_fired:
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
