class_name ConsolePanel
extends CanvasLayer

# @no-save: transient UI — instanced by a console interact, freed on close.
#
# Shared plumbing for diegetic full-screen console UIs (ship-systems panel,
# room build panel). Follows the Kino Remote pause convention: tree paused
# while open, PROCESS_MODE_ALWAYS so our own controls keep ticking, mouse
# released for clicking and restored on close.
#
# Subclasses override _build_ui() and call close() from their close button.

const BACKDROP_COLOR: Color = Color(0.02, 0.04, 0.06, 0.78)
const PANEL_COLOR: Color = Color(0.05, 0.09, 0.12, 0.96)
const EDGE_COLOR: Color = Color(0.32, 0.72, 1.0, 0.55)      # console tech-blue
const TITLE_COLOR: Color = Color(0.32, 0.72, 1.0)
const TEXT_COLOR: Color = Color(0.85, 0.90, 0.95)
const DIM_TEXT_COLOR: Color = Color(0.55, 0.62, 0.68)
const WARN_COLOR: Color = Color(1.0, 0.45, 0.25)
const OK_COLOR: Color = Color(0.35, 1.0, 0.55)

var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	Audio.play("res://sounds/terminal_boot.ogg")
	_build_ui()


func close() -> void:
	get_tree().paused = false
	Input.mouse_mode = _prev_mouse_mode
	Audio.play("res://sounds/menu_close.ogg")
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_ui() -> void:
	pass


# ---- shared widget builders --------------------------------------------------

# Backdrop + centred panel + titled VBox column subclasses fill rows into.
# Returns the content VBoxContainer.
func build_frame(title: String, panel_width: float = 860.0) -> VBoxContainer:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = BACKDROP_COLOR
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = EDGE_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(panel_width, 560.0)
	centre.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title_label: Label = Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	title_label.add_theme_font_size_override("font_size", 24)
	column.add_child(title_label)
	column.add_child(HSeparator.new())
	return column


func build_close_button(column: VBoxContainer) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	var btn: Button = Button.new()
	btn.text = "Close"
	btn.pressed.connect(close)
	Audio.attach_ui_hover(btn)
	row.add_child(btn)


func make_label(text: String, color: Color = TEXT_COLOR, size: int = 15) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func make_scroll_list(column: VBoxContainer) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 380.0)
	column.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list
