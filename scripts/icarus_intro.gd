extends Node3D

# IcarusIntro — the pre-E1 tutorial / opening sequence.
#
# Three acts played as a linear cinematic-with-tutorial-beats:
#   Act 1 — Eli's apartment: the puzzle, the knock, recruitment
#   Act 2 — Icarus Base: meet Young + Rush, learn controls, solve the math
#   Act 3 — Evacuation: attack, run to gate room, dial the 9th chevron, step through
#
# The sequence ends by transitioning to the existing gate_room.tscn cold open,
# which picks up with the crew arriving on Destiny and the E1 "Air" quest chain.
#
# Data-driven: loads steps from data/icarus_intro.json. Each step is one of:
#   narration     — speaker "" → white narration text, advance on input
#   dialogue      — character speech, advance on input
#   tutorial_hint — instructional prompt, advance on a trigger (input or action)
#   puzzle        — a "solve" beat, advance on puzzle_solved signal
#
# In instant_mode (headless tests) every step auto-advances synchronously,
# the scene never builds visual nodes, and _ready() runs all steps then
# transitions immediately. This keeps the 184+ test suite unblocked.
#
# Skip: hold Jump (Space) for SKIP_HOLD_SEC to skip the entire intro and go
# straight to the gate room cold open.

signal intro_finished()
signal act_started(act_id: String)
signal step_shown(step_id: String)

const INTRO_DATA_PATH: String = "res://data/icarus_intro.json"
const GATE_ROOM_SCENE: String = "res://scenes/gate_room.tscn"
const SKIP_HOLD_SEC: float = 1.0

# Visual nodes (null in instant_mode).
var _caption_layer: CanvasLayer = null
var _caption_label: Label = null
var _speaker_label: Label = null
var _title_label: Label = null
var _skip_indicator: Label = null
var _fade_rect: ColorRect = null
var _scene_root: Node3D = null

# Intro data.
var _acts: Array = []
var _current_act_index: int = 0
var _current_step_index: int = -1
var _current_step: Dictionary = {}
var _advance_requested: bool = false
var _skip_hold_t: float = 0.0
var _skipping: bool = false

# Instant mode: skip all visuals and timers. Set by tests.
var instant_mode: bool = false

# Puzzle state — when a puzzle step is active, this is true until solved.
var _puzzle_active: bool = false
var _puzzle_solved: bool = false

# Tutorial action triggers — set externally (by the scene's interactable
# proxies or test harness) to advance steps that wait on a specific action.
var _trigger_reached_young: bool = false
var _trigger_interact_console: bool = false
var _trigger_reached_gate_room: bool = false
var _trigger_entered_gate: bool = false
var _trigger_puzzle_solved: bool = false

var _initialized: bool = false


func _ready() -> void:
	if instant_mode:
		_run_instant()
		return
	_build_visuals()
	_load_data()
	_start_act(0)


# ── Instant mode (headless tests) ───────────────────────────────────────────

func _run_instant() -> void:
	_load_data()
	# Walk every act / step, auto-advancing. Emit signals so tests can verify.
	for act_i in range(_acts.size()):
		var act: Dictionary = _acts[act_i]
		act_started.emit(String(act.get("id", "")))
		var steps: Array = act.get("steps", [])
		for step_i in range(steps.size()):
			var step: Dictionary = steps[step_i]
			step_shown.emit(String(step.get("id", "")))
	# Mark intro complete and transition.
	GameState.intro_complete = true
	intro_finished.emit()
	# In instant mode, don't actually change scenes — tests verify state.
	# The real transition is handled by the test harness or title.gd.


# ── Data loading ─────────────────────────────────────────────────────────────

func _load_data() -> void:
	if _initialized:
		return
	_initialized = true
	var f: FileAccess = FileAccess.open(INTRO_DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("IcarusIntro: cannot open %s" % INTRO_DATA_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("IcarusIntro: %s did not parse to a Dictionary" % INTRO_DATA_PATH)
		return
	_acts = parsed.get("acts", [])
	if _acts.is_empty():
		push_error("IcarusIntro: no acts defined in %s" % INTRO_DATA_PATH)


# ── Visual build ─────────────────────────────────────────────────────────────

func _build_visuals() -> void:
	# CanvasLayer above everything for captions.
	_caption_layer = CanvasLayer.new()
	_caption_layer.name = "IntroCaptionLayer"
	_caption_layer.layer = 50
	add_child(_caption_layer)

	# Full-screen fade rect (for act transitions).
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.anchor_right = 1.0
	_fade_rect.anchor_bottom = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_layer.add_child(_fade_rect)

	# Title label (act title, top-center).
	_title_label = Label.new()
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.anchor_top = 0.0
	_title_label.anchor_bottom = 0.0
	_title_label.offset_top = 60.0
	_title_label.offset_bottom = 110.0
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 36)
	_title_label.add_theme_color_override("font_color", Color(0.83, 0.66, 0.32, 1.0))
	_title_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_caption_layer.add_child(_title_label)

	# Speaker label (bottom-center, above caption).
	_speaker_label = Label.new()
	_speaker_label.anchor_left = 0.0
	_speaker_label.anchor_right = 1.0
	_speaker_label.anchor_top = 1.0
	_speaker_label.anchor_bottom = 1.0
	_speaker_label.offset_top = -160.0
	_speaker_label.offset_bottom = -130.0
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_speaker_label.add_theme_font_size_override("font_size", 22)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42, 1.0))
	_caption_layer.add_child(_speaker_label)

	# Caption label (bottom-center).
	_caption_label = Label.new()
	_caption_label.name = "Caption"
	_caption_label.anchor_left = 0.05
	_caption_label.anchor_right = 0.95
	_caption_label.anchor_top = 1.0
	_caption_label.anchor_bottom = 1.0
	_caption_label.offset_top = -130.0
	_caption_label.offset_bottom = -50.0
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_caption_label.add_theme_font_size_override("font_size", 20)
	_caption_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.80, 1.0))
	_caption_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_caption_label.add_theme_constant_override("shadow_offset_x", 1)
	_caption_label.add_theme_constant_override("shadow_offset_y", 1)
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_label.text = ""
	_caption_layer.add_child(_caption_label)

	# Skip indicator (bottom-right).
	_skip_indicator = Label.new()
	_skip_indicator.anchor_left = 1.0
	_skip_indicator.anchor_right = 1.0
	_skip_indicator.anchor_top = 1.0
	_skip_indicator.anchor_bottom = 1.0
	_skip_indicator.offset_left = -200.0
	_skip_indicator.offset_top = -30.0
	_skip_indicator.offset_right = -10.0
	_skip_indicator.offset_bottom = -10.0
	_skip_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_indicator.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_skip_indicator.add_theme_font_size_override("font_size", 14)
	_skip_indicator.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.7))
	_skip_indicator.text = "Hold SPACE to skip"
	_caption_layer.add_child(_skip_indicator)

	# Simple 3D scene root for the visual backdrop.
	_scene_root = Node3D.new()
	_scene_root.name = "SceneRoot"
	add_child(_scene_root)


# ── Act / step sequencing ────────────────────────────────────────────────────

func _start_act(act_index: int) -> void:
	if act_index >= _acts.size():
		_finish_intro()
		return
	_current_act_index = act_index
	_current_step_index = -1
	var act: Dictionary = _acts[act_index]
	act_started.emit(String(act.get("id", "")))
	# Show act title.
	if _title_label != null:
		_title_label.text = String(act.get("title", ""))
		_title_label.visible = true
	# Fade in.
	if _fade_rect != null:
		_fade_rect.color = Color.BLACK
		var tween: Tween = create_tween()
		tween.tween_property(_fade_rect, "color:a", 0.0, 0.8)
		await tween.finished
	# Hide title after 2 seconds.
	await get_tree().create_timer(2.0).timeout
	if _title_label != null:
		_title_label.visible = false
	_advance_step()


func _advance_step() -> void:
	_current_step_index += 1
	var act: Dictionary = _acts[_current_act_index]
	var steps: Array = act.get("steps", [])
	if _current_step_index >= steps.size():
		# End of act — fade out, start next act.
		if _fade_rect != null:
			var tween: Tween = create_tween()
			tween.tween_property(_fade_rect, "color:a", 1.0, 0.6)
			await tween.finished
		_start_act(_current_act_index + 1)
		return
	_current_step = steps[_current_step_index]
	_advance_requested = false
	_puzzle_active = false
	_puzzle_solved = false
	_show_step(_current_step)


func _show_step(step: Dictionary) -> void:
	var step_id: String = String(step.get("id", ""))
	step_shown.emit(step_id)
	var speaker: String = String(step.get("speaker", ""))
	var text: String = String(step.get("text", ""))
	var step_type: String = String(step.get("type", "narration"))

	# Update caption.
	if _speaker_label != null:
		_speaker_label.text = speaker
		_speaker_label.visible = speaker != ""
	if _caption_label != null:
		_caption_label.text = text

	# Log to GameState journal.
	if GameState != null:
		if speaker == "":
			GameState.narrate(text)
		else:
			GameState.say(speaker, text)

	# Determine advance condition.
	var advance_on: String = String(step.get("advance_on", "input"))
	match advance_on:
		"input":
			# Wait for player input (Space / E / click).
			await _wait_advance()
		"interact_laptop":
			await _wait_trigger("_trigger_interact_console")
		"reached_young":
			await _wait_trigger("_trigger_reached_young")
		"reached_gate_room":
			await _wait_trigger("_trigger_reached_gate_room")
		"interact_console":
			await _wait_trigger("_trigger_interact_console")
		"entered_gate":
			await _wait_trigger("_trigger_entered_gate")
		"puzzle_solved":
			_puzzle_active = true
			await _wait_trigger("_trigger_puzzle_solved")
			_puzzle_active = false
		_:
			await _wait_advance()

	_advance_step()


# ── Advance waiters ──────────────────────────────────────────────────────────

func _wait_advance() -> void:
	_advance_requested = false
	while not _advance_requested and not _skipping:
		await get_tree().process_frame
	if _skipping:
		return


func _wait_trigger(var_name: String) -> void:
	while not get(var_name) and not _skipping:
		await get_tree().process_frame
	if _skipping:
		return


# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if instant_mode:
		return
	# Skip hold.
	if event.is_action_pressed("jump"):
		_skip_hold_t = 0.0
	elif event.is_action_released("jump"):
		_skip_hold_t = 0.0
	# Advance on Space / E / click.
	if event.is_action_pressed("jump") or event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_accept"):
		_advance_requested = true
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance_requested = true


func _process(delta: float) -> void:
	if instant_mode or _skipping:
		return
	# Skip hold tracking.
	if Input.is_action_pressed("jump"):
		_skip_hold_t += delta
		if _skip_hold_t >= SKIP_HOLD_SEC:
			_skip_intro()
	else:
		_skip_hold_t = 0.0


func _skip_intro() -> void:
	_skipping = true
	_advance_requested = true
	# Reset all triggers so any pending _wait_trigger unblocks.
	_trigger_reached_young = true
	_trigger_interact_console = true
	_trigger_reached_gate_room = true
	_trigger_entered_gate = true
	_trigger_puzzle_solved = true
	_puzzle_active = false


# ── Trigger setters (called by interactable proxies or test harness) ─────────

func trigger_reached_young() -> void:
	_trigger_reached_young = true

func trigger_interact_console() -> void:
	_trigger_interact_console = true

func trigger_reached_gate_room() -> void:
	_trigger_reached_gate_room = true

func trigger_entered_gate() -> void:
	_trigger_entered_gate = true

func trigger_puzzle_solved() -> void:
	_trigger_puzzle_solved = true


# ── Finish and transition ────────────────────────────────────────────────────

func _finish_intro() -> void:
	GameState.intro_complete = true
	intro_finished.emit()
	if instant_mode:
		return
	# Fade to black, then transition to the gate room cold open.
	if _fade_rect != null:
		_fade_rect.color = Color(0, 0, 0, 0)
		var tween: Tween = create_tween()
		tween.tween_property(_fade_rect, "color:a", 1.0, 1.0)
		await tween.finished
	# Transition to the gate room (the existing cold open / E1 quest chain).
	SceneRouter.change_to(GATE_ROOM_SCENE, "FromGate")


# ── Public API for tests ─────────────────────────────────────────────────────

func get_act_count() -> int:
	return _acts.size()

func get_act_ids() -> Array[String]:
	var ids: Array[String] = []
	for act in _acts:
		ids.append(String(act.get("id", "")))
	return ids

func get_step_count(act_index: int) -> int:
	if act_index < 0 or act_index >= _acts.size():
		return 0
	return _acts[act_index].get("steps", []).size()

func get_step_ids(act_index: int) -> Array[String]:
	var ids: Array[String] = []
	if act_index < 0 or act_index >= _acts.size():
		return ids
	for step in _acts[act_index].get("steps", []):
		ids.append(String(step.get("id", "")))
	return ids

func get_step_type(act_index: int, step_index: int) -> String:
	if act_index < 0 or act_index >= _acts.size():
		return ""
	var steps: Array = _acts[act_index].get("steps", [])
	if step_index < 0 or step_index >= steps.size():
		return ""
	return String(steps[step_index].get("type", "narration"))

func get_step_speaker(act_index: int, step_index: int) -> String:
	if act_index < 0 or act_index >= _acts.size():
		return ""
	var steps: Array = _acts[act_index].get("steps", [])
	if step_index < 0 or step_index >= steps.size():
		return ""
	return String(steps[step_index].get("speaker", ""))

func get_step_text(act_index: int, step_index: int) -> String:
	if act_index < 0 or act_index >= _acts.size():
		return ""
	var steps: Array = _acts[act_index].get("steps", [])
	if step_index < 0 or step_index >= steps.size():
		return ""
	return String(steps[step_index].get("text", ""))