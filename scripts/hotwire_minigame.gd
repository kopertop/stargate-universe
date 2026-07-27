extends CanvasLayer

# @no-save: transient UI overlay for door hotwire / force-open puzzles.

# Door-hack mini-game (concept: DOOR_HACK tablet). Soft-locked doors call
# `await play()`; returns true on success. Headless smokes set `auto_solve`.
#
# 3 color-matched jacks (left) → 4 right ports (3 live labeled + 1 VOID decoy).
# Click a jack, then its matching port. Containers (not absolute coords) so
# every control is always visible and clickable.

signal finished(success: bool)

var auto_solve: bool = false

const LAYER: int = 95
const LIVE_COUNT: int = 3
const RIGHT_COUNT: int = 4
# Magenta / cyan / gold — matches the concept art palette.
const WIRE_COLORS: Array[Color] = [
	Color(0.95, 0.28, 0.72),
	Color(0.20, 0.90, 0.88),
	Color(0.95, 0.72, 0.22),
]
const WIRE_LABELS: Array[String] = ["PWR_CORE", "DATA_LINK", "SYS_LOCK"]
const DEAD_LABEL: String = "VOID"
const PANEL_SIZE: Vector2 = Vector2(720, 460)

var _busy: bool = false
var _success: bool = false
var _pairs: Array = []  # [{left, right, color, label}]
var _dead_right: int = -1
var _right_meta: Array = []  # [{color, label, live: bool}] per right index
var _selected_left: int = -1
var _connected: Dictionary = {}  # left_idx -> right_idx
var _root: Control = null
var _panel: PanelContainer = null
var _status: Label = null
var _progress: ProgressBar = null
var _lines: Control = null
var _left_btns: Array = []
var _right_btns: Array = []
var _force_open: bool = false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func play(force_open: bool = false) -> bool:
	if _busy:
		return false
	_busy = true
	_force_open = force_open
	_success = false
	_selected_left = -1
	_connected.clear()
	if auto_solve:
		_success = true
		_busy = false
		return true
	_build_pairs()
	_build_ui()
	visible = true
	get_tree().paused = true
	await finished
	get_tree().paused = false
	visible = false
	_teardown_ui()
	_busy = false
	return _success


func _build_pairs() -> void:
	_pairs = []
	_right_meta = []
	var right_slots: Array = [0, 1, 2, 3]
	right_slots.shuffle()
	_dead_right = int(right_slots[0])
	var live_rights: Array = [int(right_slots[1]), int(right_slots[2]), int(right_slots[3])]
	live_rights.shuffle()
	for _i in RIGHT_COUNT:
		_right_meta.append({"color": Color(0.1, 0.1, 0.11), "label": DEAD_LABEL, "live": false})
	for i in LIVE_COUNT:
		var right_i: int = int(live_rights[i])
		_right_meta[right_i] = {
			"color": WIRE_COLORS[i],
			"label": WIRE_LABELS[i],
			"live": true,
		}
		_pairs.append({
			"left": i,
			"right": right_i,
			"color": WIRE_COLORS[i],
			"label": WIRE_LABELS[i],
		})


func _build_ui() -> void:
	_teardown_ui()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", _metal_panel_style())
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	var title := Label.new()
	title.text = "DOOR_HACK_v2.7" if not _force_open else "FORCE_OPEN_v2.7"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.35, 0.95, 0.92))
	root_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "// CONNECT WIRES TO MATCH PROTOCOL — skip VOID"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.30, 0.75, 0.72))
	root_vbox.add_child(subtitle)

	# Play field: jacks | wire canvas | ports
	var field := HBoxContainer.new()
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 12)
	root_vbox.add_child(field)

	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(160, 0)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	left_col.add_theme_constant_override("separation", 14)
	field.add_child(left_col)

	_lines = Control.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_wires)
	field.add_child(_lines)

	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(180, 0)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.add_theme_constant_override("separation", 10)
	field.add_child(right_col)

	_left_btns = []
	_right_btns = []
	for i in LIVE_COUNT:
		var jack: Button = _make_jack(i, WIRE_COLORS[i])
		left_col.add_child(jack)
		_left_btns.append(jack)

	for i in RIGHT_COUNT:
		var meta: Dictionary = _right_meta[i] as Dictionary
		var port: Button = _make_port(
			i,
			meta["color"] as Color,
			String(meta["label"]),
			not bool(meta["live"])
		)
		right_col.add_child(port)
		_right_btns.append(port)

	_status = Label.new()
	_status.text = "Select a jack on the left, then its matching port on the right."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
	root_vbox.add_child(_status)

	var sec := Label.new()
	sec.text = "SECURITY LEVEL: MEDIUM"
	sec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec.add_theme_font_size_override("font_size", 12)
	sec.add_theme_color_override("font_color", Color(0.90, 0.70, 0.30))
	root_vbox.add_child(sec)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 16)
	_progress.min_value = 0.0
	_progress.max_value = float(LIVE_COUNT)
	_progress.value = 0.0
	_progress.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.20, 0.85, 0.82)
	fill.set_corner_radius_all(2)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.10, 0.12)
	bg.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", bg)
	root_vbox.add_child(_progress)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(footer)
	var cancel := Button.new()
	cancel.text = "ABORT"
	cancel.custom_minimum_size = Vector2(120, 34)
	cancel.add_theme_stylebox_override("normal", _btn_style(Color(0.18, 0.12, 0.12), Color(0.55, 0.25, 0.25)))
	cancel.add_theme_stylebox_override("hover", _btn_style(Color(0.28, 0.14, 0.14), Color(0.85, 0.35, 0.35)))
	cancel.add_theme_color_override("font_color", Color(0.95, 0.75, 0.75))
	cancel.pressed.connect(_on_cancel)
	footer.add_child(cancel)

	# Let the layout settle, then redraw wires in correct space.
	call_deferred("_refresh_lines")


func _metal_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.10, 0.11, 0.13, 0.98)
	s.border_color = Color(0.45, 0.52, 0.58)
	s.set_border_width_all(4)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 12
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _make_jack(index: int, color: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 52)
	b.text = "━●  JACK_%d" % (index + 1)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", color)
	var normal := _btn_style(Color(0.12, 0.13, 0.15), color)
	var hover := _btn_style(Color(0.16, 0.18, 0.22), color.lightened(0.15))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(_on_left.bind(index))
	b.set_meta("wire_color", color)
	return b


func _make_port(index: int, color: Color, label: String, is_dead: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 48)
	b.add_theme_font_size_override("font_size", 14)
	if is_dead:
		b.text = "■  %s" % label
		b.add_theme_color_override("font_color", Color(0.40, 0.40, 0.42))
		var dead := _btn_style(Color(0.04, 0.04, 0.05), Color(0.20, 0.20, 0.22))
		b.add_theme_stylebox_override("normal", dead)
		b.add_theme_stylebox_override("hover", dead)
		b.add_theme_stylebox_override("pressed", dead)
	else:
		b.text = "⬡  %s" % label
		b.add_theme_color_override("font_color", color)
		var normal := _btn_style(Color(0.08, 0.09, 0.11), color)
		var hover := _btn_style(Color(0.12, 0.14, 0.16), color.lightened(0.2))
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(_on_right.bind(index))
	b.set_meta("wire_color", color)
	b.set_meta("is_dead", is_dead)
	return b


func _refresh_lines() -> void:
	if _lines != null:
		_lines.queue_redraw()
	_refresh_jack_selection()


func _refresh_jack_selection() -> void:
	for i in _left_btns.size():
		var b: Button = _left_btns[i] as Button
		var color: Color = WIRE_COLORS[i]
		var selected: bool = i == _selected_left
		var connected: bool = _connected.has(i)
		if connected:
			b.disabled = true
			b.modulate = Color(0.55, 0.55, 0.55)
		else:
			b.disabled = false
			b.modulate = Color.WHITE
		var border: Color = color.lightened(0.35) if selected else color
		var bg := Color(0.20, 0.22, 0.26) if selected else Color(0.12, 0.13, 0.15)
		var style := _btn_style(bg, border)
		if selected:
			style.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", style)
		b.add_theme_stylebox_override("hover", style)
		b.add_theme_stylebox_override("pressed", style)


func _on_left(index: int) -> void:
	if _connected.has(index):
		return
	_selected_left = index
	_status.text = "Jack selected — connect to matching protocol port (not VOID)."
	_status.add_theme_color_override("font_color", WIRE_COLORS[index])
	_refresh_lines()


func _on_right(index: int) -> void:
	if _selected_left < 0:
		_status.text = "Select a jack on the left first."
		_status.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
		return
	if _connected.values().has(index):
		_status.text = "Port already linked."
		return
	if index == _dead_right:
		_status.text = "VOID — dead circuit. No signal on that port."
		_status.add_theme_color_override("font_color", Color(0.70, 0.70, 0.72))
		_selected_left = -1
		_refresh_lines()
		return
	var expected: int = -1
	for p in _pairs:
		if int(p["left"]) == _selected_left:
			expected = int(p["right"])
			break
	if index != expected:
		_status.text = "PROTOCOL MISMATCH — sparks. Match colors / labels."
		_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		_selected_left = -1
		_refresh_lines()
		return
	_connected[_selected_left] = index
	_selected_left = -1
	if _progress != null:
		_progress.value = float(_connected.size())
	_status.text = "LINK ESTABLISHED  (%d/%d)" % [_connected.size(), LIVE_COUNT]
	_status.add_theme_color_override("font_color", Color(0.45, 0.95, 0.70))
	# Disable used port.
	if index < _right_btns.size():
		(_right_btns[index] as Button).disabled = true
		(_right_btns[index] as Button).modulate = Color(0.65, 0.65, 0.65)
	_refresh_lines()
	if _connected.size() >= LIVE_COUNT:
		_success = true
		_status.text = "ACCESS GRANTED"
		_status.add_theme_color_override("font_color", Color(0.35, 0.95, 0.92))
		await get_tree().create_timer(0.55, true, false, true).timeout
		finished.emit(true)


func _on_cancel() -> void:
	_success = false
	finished.emit(false)


func _draw_wires() -> void:
	if _lines == null or not is_instance_valid(_lines):
		return
	# Draw faint guide dashes across the field.
	var h: float = _lines.size.y
	var w: float = _lines.size.x
	if w < 4.0 or h < 4.0:
		return
	for i in LIVE_COUNT:
		var y: float = h * (0.22 + 0.28 * float(i))
		_lines.draw_dashed_line(Vector2(4, y), Vector2(w - 4, y), Color(0.25, 0.35, 0.40, 0.35), 2.0, 8.0)
	for left_i in _connected.keys():
		var right_i: int = int(_connected[left_i])
		var col: Color = WIRE_COLORS[int(left_i)]
		var a: Vector2 = _anchor_in_lines(_left_btns[left_i] as Control, true)
		var b: Vector2 = _anchor_in_lines(_right_btns[right_i] as Control, false)
		_lines.draw_line(a, b, col, 5.0, true)
		_lines.draw_circle(a, 5.0, col)
		_lines.draw_circle(b, 5.0, col)
	if _selected_left >= 0 and _selected_left < _left_btns.size():
		var a2: Vector2 = _anchor_in_lines(_left_btns[_selected_left] as Control, true)
		var mid: Vector2 = Vector2(w * 0.55, a2.y)
		_lines.draw_line(a2, mid, WIRE_COLORS[_selected_left], 3.0, true)
		_lines.draw_circle(a2, 7.0, WIRE_COLORS[_selected_left])


func _anchor_in_lines(ctrl: Control, from_left: bool) -> Vector2:
	if ctrl == null or _lines == null:
		return Vector2.ZERO
	var local: Vector2 = _lines.get_global_transform().affine_inverse() * ctrl.get_global_rect().get_center()
	if from_left:
		local.x = 0.0
	else:
		local.x = _lines.size.x
	return local


func _teardown_ui() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_panel = null
	_status = null
	_progress = null
	_lines = null
	_left_btns = []
	_right_btns = []
