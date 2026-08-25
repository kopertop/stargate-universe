class_name KinoPageLog
extends Node

# Mission Log page for the Kino Remote. Shows the player's accumulated
# log entries in reverse chronological order inside a scroll container.

var _coordinator: Node
var _page: Control

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "Log"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 8)
	parent.add_child(_page)
	_label(_page, "MISSION LOG", 16, Color(0.55, 0.85, 1.0, 1.0))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(scroll)
	var log_box: VBoxContainer = VBoxContainer.new()
	log_box.name = "LogBox"
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log_box)
	return _page

func refresh() -> void:
	var box: VBoxContainer = _page.find_child("LogBox", true, false) as VBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	var entries: Array[String] = GameState.log_entries.duplicate()
	entries.reverse()
	for line in entries:
		_label(box, "  • " + line, 13, Color(0.85, 0.92, 1.0, 0.9))

func is_available() -> bool:
	return true

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l