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
#     { "speaker": String, "text": String,
#       "choices": Array[Dictionary] of { "text": String, "next": int|"exit" } }
#   `next = "exit"` ends the conversation. `next = <int>` jumps to that index.

signal closed()

const CHARACTERS_PATH: String = "res://data/characters.json"

@onready var _speaker_label: Label = $Window/Margin/VBox/Header/SpeakerName
@onready var _line_label: Label = $Window/Margin/VBox/BodyPanel/BodyScroll/Line
@onready var _choices_box: VBoxContainer = $Window/Margin/VBox/ChoicesVBox
@onready var _portrait: TextureRect = $Window/Margin/VBox/Header/PortraitFrame/Portrait

var _target: Node3D = null
var _tree: Array = []
var _current_index: int = 0
# Character registry: display-name → { portrait, role, short_name }. Loaded
# once from data/characters.json on first start(). Unknown speakers fall
# through to a blank portrait (TextureRect.texture = null).
static var _characters_cache: Dictionary = {}
# Decoded ImageTexture cache, keyed by res:// path. Portraits are loaded via
# FileAccess+Image (not load()) so they work without .import sidecar files —
# this cache avoids re-decoding the PNG on every dialog node.
static var _portrait_texture_cache: Dictionary = {}

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
# data/characters.json. Returns null for unknown speakers so the frame
# stays empty rather than showing a wrong face.
#
# Portraits are read as raw PNG bytes and wrapped in an ImageTexture — this
# sidesteps Godot's .import pipeline so new portraits can be dropped into
# sprites/portraits/ without re-opening the editor. Cached per-path.
func _portrait_for(speaker: String) -> Texture2D:
	if _characters_cache.is_empty():
		_load_characters()
	var entry: Variant = _characters_cache.get(speaker, null)
	if not (entry is Dictionary):
		return null
	var path: String = String((entry as Dictionary).get("portrait", ""))
	if path == "":
		return null
	if _portrait_texture_cache.has(path):
		return _portrait_texture_cache[path]
	var tex: Texture2D = _load_portrait_texture(path)
	if tex != null:
		_portrait_texture_cache[path] = tex
	return tex


func _load_portrait_texture(path: String) -> Texture2D:
	# Try the imported-resource fast path first: if the editor HAS imported the
	# PNG, load() returns the .ctex which is GPU-uploaded and ideal.
	if FileAccess.file_exists(path + ".import"):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	# Fallback: read PNG bytes and decode in-process. Works for fresh PNGs that
	# the editor hasn't imported yet, and for headless runs.
	if not FileAccess.file_exists(path):
		push_warning("dialog_screen: portrait file not found: %s" % path)
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("dialog_screen: empty portrait file: %s" % path)
		return null
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK:
		push_warning("dialog_screen: failed to decode PNG %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)

func _load_characters() -> void:
	var file: FileAccess = FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	if file == null:
		push_warning("dialog_screen: could not open %s" % CHARACTERS_PATH)
		return
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		_characters_cache = parsed

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
		btn.pressed.connect(_on_choice_pressed.bind(nxt))
		_choices_box.add_child(btn)
	if _choices_box.get_child_count() > 0:
		(_choices_box.get_child(0) as Control).grab_focus()

func _on_choice_pressed(next_value: Variant) -> void:
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
