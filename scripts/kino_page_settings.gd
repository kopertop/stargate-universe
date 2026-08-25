class_name KinoPageSettings
extends Node

# COMPASS settings page for the Kino Remote. Per-category toggles for the
# always-on HUD direction compass. Persisted via GameState/Settings flags.

var _coordinator: Node
var _page: Control
var _settings_checks: Dictionary = {}

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "Settings"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 10)
	parent.add_child(_page)
	_label(_page, "COMPASS MARKERS", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(_page, "  Choose what the direction compass displays.", 13, Color(0.82, 0.92, 1.0, 0.9))
	_page.add_child(HSeparator.new())
	_settings_check(_page, "Lime deposits", "compass_show_lime", Settings)
	_settings_check(_page, "Points of interest", "compass_show_pois", Settings)
	_settings_check(_page, "Kino drones", "compass_show_kinos", Settings)
	_settings_check(_page, "Companions / away-team", "compass_show_companions", Settings)
	_settings_check(_page, "Gate & objective", "compass_show_gate", Settings)
	return _page

func refresh() -> void:
	for flag in _settings_checks:
		var cb: CheckButton = _settings_checks[flag]
		if is_instance_valid(cb):
			# Read from the same source that was used on creation. For compass
			# flags that's Settings; for any legacy flags that's GameState.
			var source: Node = Settings if Settings.get(flag) != null else GameState
			cb.button_pressed = source.get(flag) == true

func is_available() -> bool:
	return true

func _settings_check(parent: Control, label: String, flag: String, source: Node = null) -> void:
	if source == null:
		source = GameState
	var cb: CheckButton = CheckButton.new()
	cb.text = label
	cb.button_pressed = source.get(flag) == true
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_color_override("font_color", Color.WHITE)
	cb.add_theme_color_override("font_pressed_color", Color.WHITE)
	cb.add_theme_color_override("font_hover_color", Color.WHITE)
	cb.add_theme_font_size_override("font_size", 15)
	cb.toggled.connect(func(on: bool) -> void: source.set(flag, on))
	Audio.attach_ui_hover(cb)
	parent.add_child(cb)
	_settings_checks[flag] = cb

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l