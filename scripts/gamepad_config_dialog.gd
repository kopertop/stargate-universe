extends Node

# @no-save: UI overlay only. Drives the Gamepad autoload's remap API; holds no
# persistent state of its own (the layout it captures is persisted by Gamepad).
#
# GamepadConfigDialog — the guided face-button mapping wizard (issue #34).
#
# Some controllers ship A/B and X/Y physically swapped (Nintendo vs Xbox). When a
# pad we've never mapped connects, Gamepad.new_controller_detected fires and we
# pop a wizard that walks the player through pressing each face button in turn:
#
#   "Press the BOTTOM face button"  → records the physical JoyButton index
#   "Press the RIGHT face button"   → ...
#   "Press the LEFT face button"    → ...
#   "Press the TOP face button"     → ...
#
# When all four are captured we hand the logical→physical map to
# Gamepad.set_layout(guid, map), which rewrites the InputMap + persists it.
#
# Built programmatically on a high CanvasLayer so it attaches to every scene
# without per-scene wiring (same pattern as PauseMenu/KinoRemote) and is
# pause-immune (PROCESS_MODE_ALWAYS). Pausing the tree while it's open keeps the
# world frozen so the prompts aren't competing with gameplay.

# Logical positions captured in this on-screen order. Seeded in _ready from the
# Gamepad enum rather than a const so the parse order of the two autoloads can't
# bite us (a const initializer would resolve the Gamepad global at class-load).
var _steps: Array[int] = []

var _layer: CanvasLayer
var _root: Control
var _title: Label
var _prompt: Label
var _progress: Label
var _hint: Label

var _open: bool = false
var _initialized: bool = false
var _guid: String = ""
var _device: int = -1
var _step: int = 0
var _captured: Dictionary = {}   # logical(int) → physical(int)
var _was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_steps = [Gamepad.Face.BOTTOM, Gamepad.Face.RIGHT, Gamepad.Face.LEFT, Gamepad.Face.TOP]
	Gamepad.new_controller_detected.connect(_on_new_controller)
	call_deferred("_init_ui")


func _init_ui() -> void:
	if _initialized:
		return
	_initialized = true

	_layer = CanvasLayer.new()
	_layer.layer = 95  # Above pause (90), below fade (100).
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -180
	panel.offset_bottom = 180
	_root.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "CONTROLLER DETECTED"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	vbox.add_child(_title)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_prompt)

	_progress = Label.new()
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.add_theme_font_size_override("font_size", 14)
	_progress.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	vbox.add_child(_progress)

	_hint = Label.new()
	_hint.text = "[Esc] / Start  Skip — use the standard layout"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.7))
	vbox.add_child(_hint)


func _on_new_controller(device: int, guid: String, _name: String) -> void:
	# Headless / test runs have no display; don't pop a modal nobody can answer.
	if DisplayServer.get_name() == "headless":
		return
	open_wizard(device, guid)


# Public entrypoint — also usable from a Settings "Configure controller" button.
func open_wizard(device: int, guid: String) -> void:
	if not _initialized:
		_init_ui()
	_device = device
	_guid = guid
	_step = 0
	_captured = {}
	_open = true
	_root.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_refresh()


func _close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	get_tree().paused = _was_paused


func _refresh() -> void:
	if _step >= _steps.size():
		return
	var logical: int = _steps[_step]
	_prompt.text = "Press the %s face button" % Gamepad.face_label(logical)
	_progress.text = "%d / %d" % [_step + 1, _steps.size()]


# Capture raw joypad button presses while open. _input (not _unhandled_input) so
# a focused Control can't swallow the press, and it's pause-immune via
# PROCESS_MODE_ALWAYS. We accept only the configuring device.
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		if not jb.pressed:
			return
		if _device >= 0 and jb.device != _device:
			return
		# Start/Options skips the wizard and keeps the default layout.
		if jb.button_index == JOY_BUTTON_START:
			get_viewport().set_input_as_handled()
			_skip()
			return
		_capture(jb.button_index)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") or (event is InputEventKey and (event as InputEventKey).pressed
			and (event as InputEventKey).keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_skip()


func _capture(physical_button: int) -> void:
	if _step >= _steps.size():
		return
	var logical: int = _steps[_step]
	_captured[logical] = physical_button
	_step += 1
	if _step >= _steps.size():
		_finish()
	else:
		_refresh()


func _finish() -> void:
	Gamepad.set_layout(_guid, _captured)
	_title.text = "CONTROLLER READY"
	_prompt.text = "Layout saved. You're set."
	_progress.text = ""
	# Brief confirmation beat, then close.
	await get_tree().create_timer(0.9).timeout
	_close()


func _skip() -> void:
	# Keep the default (SDL/Xbox) layout and remember the choice so we don't
	# nag this controller again.
	Gamepad.reset_layout(_guid)
	_close()


func is_open() -> bool:
	return _open


func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.97)
	sb.border_color = Color(0.4, 0.7, 1.0, 0.85)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	return sb
