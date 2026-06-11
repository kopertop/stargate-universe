class_name DialogScreen
extends Control

# Fable-style conversation screen (user design goal 2026-06-11). Spawned by
# hud.gd when GameState.dialog_started fires. The world stays visible:
#   • a pause-immune OTS camera (DialogCinema) shifts to whoever is SPEAKING,
#     and frames ELI whenever a real choice (>= 2 options) is offered;
#   • the spoken line reads as a bottom-centre subtitle;
#   • choices float as a minimal gold-highlighted text list on the right —
#     no parchment panel.
# The legacy Window/Header/BodyPanel nodes remain (hidden) so tests that
# reach `Window/Margin/VBox/ChoicesVBox` keep working; the tree still pauses
# while the conversation is open (participant MODELS keep animating via
# PROCESS_MODE_ALWAYS, managed by DialogCinema).
#
# Number keys 1-9 trigger choices; Esc closes.
#
# Dialog tree shape (passed to start()):
#   tree: Array[Dictionary] — each node:
#     { "speaker": String, "text": String, "action": String?,
#       "choices": Array[Dictionary] of
#         { "text": String, "next": int|"exit", "action": String? } }
#   `next = "exit"` ends the conversation. `next = <int>` jumps to that index.
#   An optional `action` on a NODE fires when the node is shown; an optional
#   `action` on a CHOICE fires when that choice is picked. Both emit
#   GameState.dialog_action (the negotiation trade payoff rides the choice form).

signal closed()

@onready var _speaker_label: Label = $Window/Margin/VBox/Header/SpeakerName
@onready var _line_label: Label = $Window/Margin/VBox/BodyPanel/BodyScroll/Line
@onready var _choices_box: VBoxContainer = $Window/Margin/VBox/ChoicesVBox
@onready var _portrait: TextureRect = $Window/Margin/VBox/Header/PortraitFrame/Portrait
@onready var _sub_speaker: Label = $Subtitle/SubSpeaker
@onready var _sub_line: Label = $Subtitle/SubLine

var _target: Node3D = null
var _tree: Array = []
var _current_index: int = 0
# True while a node rendered with "hold": true is waiting for GameState.dialog_release.
# Choice buttons + number keys are inert until the release fires (staged
# choreography must land before the player can advance).
var _held: bool = false
# Fable presentation: OTS speaker camera + face-each-other staging. Null in
# instant_mode, for radio/self dialogs, or when no player body exists.
var _cinema: Node = null
# Portrait + character-registry loading lives in PortraitLoader (shared with the
# HUD unit frame) so the .import-sidestep PNG decoder is implemented once.
const PortraitLoaderScript := preload("res://scripts/portrait_loader.gd")
const DialogCinemaScript := preload("res://scripts/dialog_cinema.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start(target: Node3D, tree: Array) -> void:
	_target = target
	_tree = tree
	_current_index = 0
	get_tree().paused = true
	_maybe_begin_cinema()
	_render_node()


# Conversation camera + staging — live play with a real NPC target only.
# Radio/self dialogs (target IS the player) keep the gameplay framing, and
# instant_mode (headless suites) never installs presentation.
func _maybe_begin_cinema() -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		return
	if _target == null or not is_instance_valid(_target):
		return
	if _target.is_in_group("player"):
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or player == _target:
		return
	_cinema = DialogCinemaScript.new()
	_cinema.name = "DialogCinema"
	var scene: Node = get_tree().current_scene
	if scene != null:
		scene.add_child(_cinema)
	else:
		add_child(_cinema)
	_cinema.call("begin", _target, player)

func _render_node() -> void:
	if _current_index < 0 or _current_index >= _tree.size():
		close()
		return
	var node: Dictionary = _tree[_current_index]
	var speaker: String = String(node.get("speaker", ""))
	_speaker_label.text = speaker
	_portrait.texture = _portrait_for(speaker)
	_line_label.text = String(node.get("text", ""))
	# Fable presentation: the spoken line reads as a bottom-centre subtitle.
	_sub_speaker.text = speaker
	_sub_line.text = "\"%s\"" % String(node.get("text", ""))
	# Data-driven side effects: a node may carry an "action" id that fires when
	# it's shown (e.g. the FTL-drop blur on Brody's line). Listeners hook
	# GameState.dialog_action.
	# A held node disables its choices until GameState.dialog_release. Set the flag
	# BEFORE emitting the action so the cue listener (which may emit dialog_release
	# synchronously in instant_mode) can release it immediately.
	_held = node.get("hold", false) == true
	if _held and not GameState.dialog_release.is_connected(_release_hold):
		GameState.dialog_release.connect(_release_hold, CONNECT_ONE_SHOT)
	var action: String = String(node.get("action", ""))
	if action != "":
		GameState.dialog_action.emit(action)
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		choices = [{"text": "Goodbye.", "next": "exit"}]
	# Fable rhythm, two beats: the camera holds on the SPEAKER while their
	# line reads; for a real decision (>= 2 options) the choices then reveal
	# WITH a cut to Eli after a reading delay. Single-continue nodes keep the
	# speaker framed and show their continue immediately. Without cinema
	# (instant_mode/headless/radio) choices appear at once — structural tests
	# press them right after start().
	if _cinema != null and is_instance_valid(_cinema):
		_cinema.call("frame_node", speaker, false)
		if choices.size() >= 2:
			_reveal_choices_after_read(choices, String(node.get("text", "")))
			return
	_lay_out_choices(choices)


# Beat 2: after the line has had reading time, cut to the responder (Eli)
# and float the choices in. A token cancels stale reveals if the node
# advances or the screen closes mid-delay.
var _reveal_token: int = 0

func _reveal_choices_after_read(choices: Array, line: String) -> void:
	_reveal_token += 1
	var token: int = _reveal_token
	var delay: float = clampf(0.7 + float(line.length()) * 0.025, 0.9, 3.0)
	await get_tree().create_timer(delay, true).timeout
	if token != _reveal_token or not is_inside_tree():
		return
	if _cinema != null and is_instance_valid(_cinema):
		_cinema.call("frame_node", "Eli", true)
	_lay_out_choices(choices)

# Resolve a speaker display name to the portrait Texture2D defined in
# data/characters.json. Delegates to PortraitLoader (shared with the HUD unit
# frame) which handles the .import-sidestep PNG decode + caching.
func _portrait_for(speaker: String) -> Texture2D:
	return PortraitLoaderScript.portrait_for(speaker)

# Vertical list of floating text options, top-to-bottom (Fable look: plain
# outlined text, gold + arrow on the focused one). Slot 0 = key 1, etc.
func _lay_out_choices(choices: Array) -> void:
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn: Button = Button.new()
		var base_text: String = String(choice.get("text", ""))
		btn.set_meta("base_text", base_text)
		btn.text = "     " + base_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nxt: Variant = choice.get("next", "exit")
		var act: String = String(choice.get("action", ""))
		btn.pressed.connect(_on_choice_pressed.bind(nxt, act))
		btn.disabled = _held   # inert until the held node is released
		# Hover = focus so mouse and keyboard share one highlight, and the
		# gold arrow marks whichever option is live.
		btn.focus_entered.connect(_mark_focused.bind(btn, true))
		btn.focus_exited.connect(_mark_focused.bind(btn, false))
		btn.mouse_entered.connect(btn.grab_focus)
		Audio.attach_ui_hover(btn)
		_choices_box.add_child(btn)
	if not _held and _choices_box.get_child_count() > 0:
		(_choices_box.get_child(0) as Control).grab_focus()


func _mark_focused(btn: Button, focused: bool) -> void:
	var base_text: String = String(btn.get_meta("base_text", btn.text))
	btn.text = ("➤  " if focused else "     ") + base_text


# Release a held node: re-enable the choice buttons and focus the first one.
func _release_hold() -> void:
	_held = false
	for c in _choices_box.get_children():
		if c is Button:
			(c as Button).disabled = false
	if _choices_box.get_child_count() > 0:
		(_choices_box.get_child(0) as Control).grab_focus()

func _on_choice_pressed(next_value: Variant, action: String = "") -> void:
	# A choice may carry its own data-driven side effect (e.g. a negotiation
	# "trade:<resource>:<amount>" payoff, issue #90). Fire it before advancing so
	# listeners (npc.gd::_on_dialog_action) react while the conversation is open.
	# This mirrors the node-level action in _render_node — choices and nodes share
	# the GameState.dialog_action channel.
	if action != "":
		GameState.dialog_action.emit(action)
	if next_value is String and String(next_value) == "exit":
		close()
		return
	if typeof(next_value) == TYPE_INT or typeof(next_value) == TYPE_FLOAT:
		var idx: int = int(next_value)
		if idx >= 0 and idx < _tree.size():
			_current_index = idx
			_render_node()
			return
	close()

func close() -> void:
	if _cinema != null and is_instance_valid(_cinema):
		_cinema.call("end")
		_cinema.queue_free()
	_cinema = null
	get_tree().paused = false
	closed.emit()
	# Surface the close globally so non-NPC triggers (kino_pickup, etc.) can
	# await dialog completion without needing a handle to this instance.
	GameState.dialog_closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		if _held:
			get_viewport().set_input_as_handled()
			return
		var idx: int = key.keycode - KEY_1
		if idx < _choices_box.get_child_count():
			(_choices_box.get_child(idx) as Button).emit_signal("pressed")
			get_viewport().set_input_as_handled()
