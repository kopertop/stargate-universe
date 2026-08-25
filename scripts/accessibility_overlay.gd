extends Control

# Accessibility overlay — a code-built settings panel for all accessibility
# options. Designed to be inserted into the pause menu and title screen
# settings overlay the same way the controller config button is built in
# title.gd. All widgets are created in code so no .tscn changes are needed.
#
# Sections:
#   1. Colorblind correction (Off / Protanopia / Deuteranopia / Tritanopia)
#   2. Subtitles (Size, Color, Speaker Labels, Background)
#   3. Aim Assist (Strength slider, Snap toggle, Friction toggle)
#   4. Puzzle Hints (Enable, Delay slider, Detail level)
#   5. Auto-Fail Retry (Enable, Max retries, Restart mode)
#   6. Input Remapping (scrollable action list with rebind buttons)

signal closed()

var _panel: PanelContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _back_btn: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Root fills the screen so clicks outside the panel are swallowed.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -340
	_panel.offset_right = 340
	_panel.offset_top = -320
	_panel.offset_bottom = 320
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var outer_vbox: VBoxContainer = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(outer_vbox)

	var header: Label = Label.new()
	header.text = "ACCESSIBILITY"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	outer_vbox.add_child(header)

	# Scrollable content area.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 420)
	outer_vbox.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 14)
	_scroll.add_child(_content)

	_build_colorblind_section()
	_build_subtitle_section()
	_build_aim_assist_section()
	_build_hint_section()
	_build_auto_retry_section()
	_build_remap_section()

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(280, 44)
	_back_btn.add_theme_font_size_override("font_size", 16)
	_back_btn.add_theme_color_override("font_color", Color.WHITE)
	_back_btn.pressed.connect(_on_back)
	outer_vbox.add_child(_back_btn)

	visible = false


# ── Section builders ──────────────────────────────────────────────────────────────

func _build_colorblind_section() -> void:
	_add_section_header("Colorblind Correction")
	var acc: Node = _acc()
	var options: Array[String] = ["Off", "Protanopia", "Deuteranopia", "Tritanopia"]
	var opt := OptionButton.new()
	for o in options:
		opt.add_item(o)
	opt.selected = acc.colorblind_mode if acc != null else 0
	opt.item_selected.connect(func(i: int): acc.set_colorblind_mode(i))
	_content.add_child(opt)


func _build_subtitle_section() -> void:
	_add_section_header("Subtitles")
	var acc: Node = _acc()

	# Subtitle size
	_add_label("Subtitle Size")
	var size_opts: Array[String] = ["Small", "Medium", "Large", "Extra Large"]
	var size_opt := OptionButton.new()
	for o in size_opts:
		size_opt.add_item(o)
	size_opt.selected = acc.subtitle_size if acc != null else 1
	size_opt.item_selected.connect(func(i: int): acc.set_subtitle_size(i))
	_content.add_child(size_opt)

	# Subtitle color
	_add_label("Subtitle Color")
	var color_opts: Array[String] = ["White", "Yellow", "Cyan", "Green"]
	var color_opt := OptionButton.new()
	for o in color_opts:
		color_opt.add_item(o)
	color_opt.selected = acc.subtitle_color if acc != null else 0
	color_opt.item_selected.connect(func(i: int): acc.set_subtitle_color(i))
	_content.add_child(color_opt)

	# Speaker labels
	var speaker_cb := CheckBox.new()
	speaker_cb.text = "Show Speaker Labels"
	speaker_cb.button_pressed = acc.speaker_labels if acc != null else true
	speaker_cb.toggled.connect(func(b: bool): acc.set_speaker_labels(b))
	_content.add_child(speaker_cb)

	# Subtitle background
	var bg_cb := CheckBox.new()
	bg_cb.text = "Subtitle Background"
	bg_cb.button_pressed = acc.subtitle_background if acc != null else true
	bg_cb.toggled.connect(func(b: bool): acc.set_subtitle_background(b))
	_content.add_child(bg_cb)


func _build_aim_assist_section() -> void:
	_add_section_header("Aim Assist")
	var acc: Node = _acc()

	_add_label("Aim Assist Strength")
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = acc.aim_assist_strength if acc != null else 0.0
	slider.custom_minimum_size = Vector2(300, 20)
	slider.value_changed.connect(func(v: float): acc.set_aim_assist_strength(v))
	_content.add_child(slider)

	var snap_cb := CheckBox.new()
	snap_cb.text = "Snap to Target"
	snap_cb.button_pressed = acc.aim_assist_snap if acc != null else false
	snap_cb.toggled.connect(func(b: bool): acc.set_aim_assist_snap(b))
	_content.add_child(snap_cb)

	var friction_cb := CheckBox.new()
	friction_cb.text = "Aim Friction (Slow Near Targets)"
	friction_cb.button_pressed = acc.aim_assist_friction if acc != null else false
	friction_cb.toggled.connect(func(b: bool): acc.set_aim_assist_friction(b))
	_content.add_child(friction_cb)


func _build_hint_section() -> void:
	_add_section_header("Puzzle Hints")
	var acc: Node = _acc()

	var hints_cb := CheckBox.new()
	hints_cb.text = "Enable Puzzle Hints"
	hints_cb.button_pressed = acc.hints_enabled if acc != null else true
	hints_cb.toggled.connect(func(b: bool): acc.set_hints_enabled(b))
	_content.add_child(hints_cb)

	_add_label("Hint Delay (seconds)")
	var delay_slider := HSlider.new()
	delay_slider.min_value = 0.0
	delay_slider.max_value = 120.0
	delay_slider.step = 5.0
	delay_slider.value = acc.hint_delay_seconds if acc != null else 30.0
	delay_slider.custom_minimum_size = Vector2(300, 20)
	delay_slider.value_changed.connect(func(v: float): acc.set_hint_delay(v))
	_content.add_child(delay_slider)

	_add_label("Hint Detail Level")
	var detail_opts: Array[String] = ["Brief", "Detailed", "Full Solution"]
	var detail_opt := OptionButton.new()
	for o in detail_opts:
		detail_opt.add_item(o)
	detail_opt.selected = acc.hint_detail if acc != null else 0
	detail_opt.item_selected.connect(func(i: int): acc.set_hint_detail(i))
	_content.add_child(detail_opt)


func _build_auto_retry_section() -> void:
	_add_section_header("Auto-Fail Retry")
	var acc: Node = _acc()

	var retry_cb := CheckBox.new()
	retry_cb.text = "Enable Auto-Retry on Failure"
	retry_cb.button_pressed = acc.auto_retry_enabled if acc != null else false
	retry_cb.toggled.connect(func(b: bool): acc.set_auto_retry_enabled(b))
	_content.add_child(retry_cb)

	_add_label("Max Retries")
	var max_slider := HSlider.new()
	max_slider.min_value = 1.0
	max_slider.max_value = 10.0
	max_slider.step = 1.0
	max_slider.value = acc.auto_retry_max if acc != null else 3
	max_slider.custom_minimum_size = Vector2(300, 20)
	max_slider.value_changed.connect(func(v: float): acc.set_auto_retry_max(int(v)))
	_content.add_child(max_slider)

	var restart_cb := CheckBox.new()
	restart_cb.text = "Restart from Checkpoint (vs Full Episode Restart)"
	restart_cb.button_pressed = acc.auto_retry_restart if acc != null else false
	restart_cb.toggled.connect(func(b: bool): acc.set_auto_retry_restart(b))
	_content.add_child(restart_cb)


func _build_remap_section() -> void:
	_add_section_header("Input Remapping")
	var remap: Node = get_node_or_null("/root/InputRemap")
	if remap == null:
		_add_label("Input remapping not available.")
		return

	# Reset all button.
	var reset_btn := Button.new()
	reset_btn.text = "Reset All to Defaults"
	reset_btn.custom_minimum_size = Vector2(280, 36)
	reset_btn.pressed.connect(func(): remap.reset_all())
	_content.add_child(reset_btn)

	# Build a row per remappable action.
	for action in InputRemap.REMAPPABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.text = action.replace("_", " ").capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(160, 28)
		row.add_child(label)

		var current := Label.new()
		current.text = remap.binding_label(action)
		current.custom_minimum_size = Vector2(80, 28)
		current.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
		row.add_child(current)

		var rebind_btn := Button.new()
		rebind_btn.text = "Rebind"
		rebind_btn.custom_minimum_size = Vector2(80, 28)
		rebind_btn.pressed.connect(_on_rebind_pressed.bind(action, current, rebind_btn))
		row.add_child(rebind_btn)

		_content.add_child(row)


# ── Rebind flow ────────────────────────────────────────────────────────────────────

var _rebind_action: String = ""
var _rebind_label: Label = null
var _rebind_btn: Button = null

func _on_rebind_pressed(action: String, label: Label, btn: Button) -> void:
	_rebind_action = action
	_rebind_label = label
	_rebind_btn = btn
	btn.text = "Press any key..."
	btn.disabled = true
	# Grab focus so _input receives events on this Control.
	grab_focus()


func _input(event: InputEvent) -> void:
	if _rebind_action == "":
		return
	# Only capture key or joypad button presses.
	if not (event is InputEventKey) and not (event is InputEventJoypadButton):
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		# Ignore Escape — cancels rebind.
		if key_event.keycode == KEY_ESCAPE:
			_cancel_rebind()
			get_viewport().set_input_as_handled()
			return
		# Perform the rebind.
		var remap: Node = get_node_or_null("/root/InputRemap")
		if remap != null:
			remap.rebind(_rebind_action, key_event)
			if _rebind_label != null:
				_rebind_label.text = remap.binding_label(_rebind_action)
		_finish_rebind()
	elif event is InputEventJoypadButton:
		var joy_event: InputEventJoypadButton = event as InputEventJoypadButton
		if not joy_event.pressed:
			return
		var remap: Node = get_node_or_null("/root/InputRemap")
		if remap != null:
			remap.rebind(_rebind_action, joy_event)
			if _rebind_label != null:
				_rebind_label.text = remap.binding_label(_rebind_action)
		_finish_rebind()
	get_viewport().set_input_as_handled()


func _cancel_rebind() -> void:
	_rebind_action = ""
	if _rebind_btn != null:
		_rebind_btn.text = "Rebind"
		_rebind_btn.disabled = false
	_rebind_label = null
	_rebind_btn = null


func _finish_rebind() -> void:
	_cancel_rebind()


# ── Helpers ────────────────────────────────────────────────────────────────────────

func _acc() -> Node:
	return get_node_or_null("/root/AccessibilitySettings")


func _add_section_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.83, 0.66, 0.32, 1.0))
	_content.add_child(label)


func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.85))
	_content.add_child(label)


func _panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.96)
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


func _on_back() -> void:
	visible = false
	closed.emit()


func open() -> void:
	visible = true
	_back_btn.grab_focus()