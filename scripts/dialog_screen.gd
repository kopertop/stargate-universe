class_name DialogScreen
extends Control

# Windowed, WoW-style dialog. Spawned by hud.gd when GameState.dialog_started
# fires. The world stays visible — only a parchment panel anchored on the left
# of the viewport is drawn. On start():
#   1. Pauses the tree so the world freezes mid-pose while the player reads.
#   2. Renders the current node's speaker name + portrait placeholder at the
#      top of the window, body text in a scrollable middle panel, and choices
#      as a vertical list of buttons at the bottom.
#
# No cinematic Camera3D is installed — the existing third-person view is
# preserved (this was the explicit ask: don't zoom in and obscure the NPC).
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

var _target: Node3D = null
var _tree: Array = []
var _current_index: int = 0
# Portrait + character-registry loading lives in PortraitLoader (shared with the
# HUD unit frame) so the .import-sidestep PNG decoder is implemented once.
const PortraitLoaderScript := preload("res://scripts/portrait_loader.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start(target: Node3D, tree: Array) -> void:
	_target = target
	_tree = tree
	_current_index = 0
	get_tree().paused = true
	_render_node()

func _render_node() -> void:
	if _current_index < 0 or _current_index >= _tree.size():
		close()
		return
	var node: Dictionary = _tree[_current_index]
	var speaker: String = String(node.get("speaker", ""))
	_speaker_label.text = speaker
	_portrait.texture = _portrait_for(speaker)
	_line_label.text = String(node.get("text", ""))
	# Data-driven side effects: a node may carry an "action" id that fires when
	# it's shown (e.g. the FTL-drop blur on Brody's line). Listeners hook
	# GameState.dialog_action.
	var action: String = String(node.get("action", ""))
	if action != "":
		GameState.dialog_action.emit(action)
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		choices = [{"text": "Goodbye.", "next": "exit"}]
	_lay_out_choices(choices)

# Resolve a speaker display name to the portrait Texture2D defined in
# data/characters.json. Delegates to PortraitLoader (shared with the HUD unit
# frame) which handles the .import-sidestep PNG decode + caching.
func _portrait_for(speaker: String) -> Texture2D:
	return PortraitLoaderScript.portrait_for(speaker)

# Vertical list of buttons, top-to-bottom. Slot 0 = key 1, slot 1 = key 2, etc.
func _lay_out_choices(choices: Array) -> void:
	for i in range(choices.size()):
		var choice: Dictionary = choices[i]
		var btn: Button = Button.new()
		btn.text = "%d. %s" % [i + 1, String(choice.get("text", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nxt: Variant = choice.get("next", "exit")
		var act: String = String(choice.get("action", ""))
		btn.pressed.connect(_on_choice_pressed.bind(nxt, act))
		Audio.attach_ui_hover(btn)
		_choices_box.add_child(btn)
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
		var idx: int = key.keycode - KEY_1
		if idx < _choices_box.get_child_count():
			(_choices_box.get_child(idx) as Button).emit_signal("pressed")
			get_viewport().set_input_as_handled()
