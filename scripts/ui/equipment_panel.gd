extends CanvasLayer

# Paper-doll equipment panel (#74). Shows a character silhouette with five
# equipment slots (helmet, vest, backpack, pants, boots). Click a slot to
# unequip; click an item in the browse list to equip it into its slot.
#
# Built programmatically (no .tscn) so it attaches to any scene. Toggled with
# [E]; respects input-order and mouse-mode gotchas (same pattern as
# character_panel.gd / PauseMenu / KinoRemote).
#
# This panel reads from an EquipmentSystem instance (injected or auto-created).
# It does NOT touch the legacy Inventory autoload — this is the new 5-slot
# gameplay-facing gear UI with stat modifiers.
#
# @no-save: UI overlay only. The loadout is owned by EquipmentSystem.

signal panel_toggled(open: bool)

const ACCENT: Color = Color(0.60, 0.78, 0.95, 0.85)
const ACCENT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)
const ACCENT_GOLD_DIM: Color = Color(0.52, 0.42, 0.21, 1.0)
const PANEL_BG: Color = Color(0.04, 0.06, 0.09, 0.96)
const SLOT_BG: Color = Color(0.06, 0.10, 0.15, 0.85)
const SLOT_BG_FILLED: Color = Color(0.10, 0.16, 0.22, 0.9)
const TEXT_PRIMARY: Color = Color(0.95, 0.98, 1.0, 1.0)
const TEXT_DIM: Color = Color(0.70, 0.82, 0.95, 0.85)
const TEXT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)
const SILHOUETTE_COLOR: Color = Color(0.12, 0.18, 0.24, 0.7)
const SILHOUETTE_OUTLINE: Color = Color(0.3, 0.5, 0.7, 0.5)

const SLOT_SIZE: Vector2 = Vector2(64, 64)
const PANEL_WIDTH: int = 580
const PANEL_HEIGHT: int = 540

# Slot display metadata: label, glyph (empty-slot placeholder), and position
# on the paper-doll grid (row 0 = top of the silhouette).
const SLOT_META: Dictionary = {
	"helmet": {"label": "Helmet", "glyph": "⛑", "row": 0},
	"vest": {"label": "Vest", "glyph": "\\U0001f9ba", "row": 1},
	"backpack": {"label": "Backpack", "glyph": "\\U0001f392", "row": 1},
	"pants": {"label": "Pants", "glyph": "\\U0001f456", "row": 2},
	"boots": {"label": "Boots", "glyph": "\\U0001f45f", "row": 3},
}

var _root: Control
var _panel: PanelContainer
var _slot_widgets: Dictionary = {}
var _item_list: VBoxContainer
var _stat_label: Label
var _empty_label: Label

var _open: bool = false
var _initialized: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

# The EquipmentSystem this panel reads from. Auto-resolved if null.
var _equip_sys: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_init_ui")


func _init_ui() -> void:
	if _initialized:
		return
	_initialized = true

	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dim backdrop swallows clicks so they don't bleed into the world.
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -float(PANEL_WIDTH) / 2.0
	_panel.offset_right = float(PANEL_WIDTH) / 2.0
	_panel.offset_top = -float(PANEL_HEIGHT) / 2.0
	_panel.offset_bottom = float(PANEL_HEIGHT) / 2.0
	_root.add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Header
	var header: Label = Label.new()
	header.text = "EQUIPMENT"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", ACCENT_GOLD)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	# Main row: paper-doll on the left, stats + item list on the right.
	var main_row: HBoxContainer = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 20)
	vbox.add_child(main_row)

	# --- Paper-doll (left column) ---
	var doll_vbox: VBoxContainer = VBoxContainer.new()
	doll_vbox.add_theme_constant_override("separation", 12)
	main_row.add_child(doll_vbox)

	var doll_label: Label = Label.new()
	doll_label.text = "Paper Doll"
	doll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	doll_label.add_theme_font_size_override("font_size", 13)
	doll_label.add_theme_color_override("font_color", TEXT_DIM)
	doll_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doll_vbox.add_child(doll_label)

	# Silhouette panel with slots arranged around it.
	var doll: PanelContainer = PanelContainer.new()
	doll.custom_minimum_size = Vector2(220, 360)
	doll.add_theme_stylebox_override("panel", _doll_stylebox())
	doll_vbox.add_child(doll)

	_build_paper_doll_slots(doll)

	# --- Right column: stats + item list ---
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 12)
	main_row.add_child(right_col)

	# Stats summary
	var stats_header: Label = Label.new()
	stats_header.text = "Stats"
	stats_header.add_theme_font_size_override("font_size", 14)
	stats_header.add_theme_color_override("font_color", TEXT_DIM)
	stats_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(stats_header)

	_stat_label = Label.new()
	_stat_label.text = ""
	_stat_label.add_theme_font_size_override("font_size", 12)
	_stat_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	_stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(_stat_label)

	# Separator
	right_col.add_child(HSeparator.new())

	# Equipment browse list
	var eq_header: Label = Label.new()
	eq_header.text = "Available Gear"
	eq_header.add_theme_font_size_override("font_size", 14)
	eq_header.add_theme_color_override("font_color", TEXT_DIM)
	eq_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(eq_header)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(scroll)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_item_list)

	_empty_label = Label.new()
	_empty_label.text = "No gear available."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 12)
	_empty_label.add_theme_color_override("font_color", TEXT_DIM)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.visible = false
	right_col.add_child(_empty_label)

	# Footer
	var footer: Label = Label.new()
	footer.text = "[E] / [Esc] Close"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.7))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(footer)

	_connect_equipment()


# Build the paper-doll: a central silhouette with 5 slots arranged vertically
# (helmet at top, vest + backpack side by side, pants, boots).
func _build_paper_doll_slots(doll: PanelContainer) -> void:
	# Use a VBox with rows for the slot layout.
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	doll.add_child(layout)

	# Row 0: helmet (centered)
	layout.add_child(_make_slot_widget("helmet"))

	# Row 1: vest + backpack (side by side)
	var row1: HBoxContainer = HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	row1.add_theme_constant_override("separation", 16)
	layout.add_child(row1)
	row1.add_child(_make_slot_widget("vest"))
	row1.add_child(_make_slot_widget("backpack"))

	# Row 2: pants (centered)
	layout.add_child(_make_slot_widget("pants"))

	# Row 3: boots (centered)
	layout.add_child(_make_slot_widget("boots"))


func _make_slot_widget(slot: String) -> Panel:
	var meta: Dictionary = SLOT_META.get(slot, {})
	var slot_panel: Panel = Panel.new()
	slot_panel.custom_minimum_size = SLOT_SIZE
	slot_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot_panel.add_theme_stylebox_override("panel", _slot_stylebox(false))
	slot_panel.gui_input.connect(_on_slot_input.bind(slot))

	# Empty-slot glyph
	var glyph: Label = Label.new()
	glyph.name = "Glyph"
	glyph.text = String(meta.get("glyph", "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 28)
	glyph.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8, 0.55))
	glyph.anchor_right = 1.0
	glyph.anchor_bottom = 1.0
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(glyph)

	# Equipped-item label (shows item name when filled)
	var item_label: Label = Label.new()
	item_label.name = "ItemLabel"
	item_label.text = ""
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	item_label.add_theme_font_size_override("font_size", 8)
	item_label.add_theme_color_override("font_color", TEXT_GOLD)
	item_label.anchor_right = 1.0
	item_label.anchor_bottom = 1.0
	item_label.offset_top = SLOT_SIZE.y - 14
	item_label.offset_bottom = SLOT_SIZE.y
	item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_label.visible = false
	slot_panel.add_child(item_label)

	# Slot caption
	var caption: Label = Label.new()
	caption.name = "Caption"
	caption.text = String(meta.get("label", slot))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", TEXT_DIM)
	caption.anchor_top = 1.0
	caption.anchor_right = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = 2
	caption.offset_bottom = 16
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(caption)

	_slot_widgets[slot] = slot_panel
	return slot_panel


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("equipment_panel"):
		get_viewport().set_input_as_handled()
		_toggle()
	elif event is InputEventKey and _open:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and (k.keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_toggle()


func _toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if not _initialized:
		_init_ui()
	_open = true
	_root.visible = true
	_refresh()
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t: SceneTree = Engine.get_main_loop() as SceneTree
	if t != null:
		t.paused = true
	panel_toggled.emit(true)


func close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	var t: SceneTree = Engine.get_main_loop() as SceneTree
	if t != null:
		t.paused = false
	Input.mouse_mode = _saved_mouse_mode
	panel_toggled.emit(false)


func is_open() -> bool:
	return _open


# --- equipment wiring + refresh ---------------------------------------------

func _connect_equipment() -> void:
	var sys: Node = _equip_system()
	if sys == null:
		return
	if sys.has_signal("equipment_changed") and not sys.is_connected("equipment_changed", _on_equipment_changed):
		sys.connect("equipment_changed", _on_equipment_changed)
	if sys.has_signal("stats_recomputed") and not sys.is_connected("stats_recomputed", _on_stats_recomputed):
		sys.connect("stats_recomputed", _on_stats_recomputed)


func _equip_system() -> Node:
	if _equip_sys != null and is_instance_valid(_equip_sys):
		return _equip_sys
	# Try to find a registered EquipmentSystem in the scene tree.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var n: Node = tree.root.get_node_or_null("EquipmentSystem")
		if n != null:
			_equip_sys = n
			return n
	return null


# Inject the EquipmentSystem to read from (for testing / manual wiring).
func set_equipment_system(sys: Node) -> void:
	_equip_sys = sys
	if _initialized:
		_connect_equipment()


func _on_equipment_changed(_slot: String, _item_id: String) -> void:
	if _open:
		_refresh()


func _on_stats_recomputed(_derived: Dictionary) -> void:
	if _open:
		_refresh()


func _refresh() -> void:
	_refresh_slots()
	_refresh_item_list()
	_refresh_stats()


func _refresh_slots() -> void:
	var sys: Node = _equip_system()
	for slot in _slot_widgets.keys():
		var widget: Panel = _slot_widgets[slot]
		if widget == null or not is_instance_valid(widget):
			continue
		var item_id: String = ""
		if sys != null and sys.has_method("equipped_in"):
			item_id = String(sys.call("equipped_in", slot))
		var filled: bool = item_id != ""
		var glyph: Label = widget.get_node_or_null("Glyph")
		var item_label: Label = widget.get_node_or_null("ItemLabel")
		if glyph != null:
			glyph.visible = not filled
		if item_label != null:
			item_label.visible = filled
			item_label.text = _short_name(item_id) if filled else ""
		widget.tooltip_text = ("%s  —  click to unequip" % _name_for(item_id)) if filled else ""
		widget.add_theme_stylebox_override("panel", _slot_stylebox(filled))


func _refresh_item_list() -> void:
	if _item_list == null:
		return
	for c in _item_list.get_children():
		_item_list.remove_child(c)
		c.queue_free()
	var sys: Node = _equip_system()
	var rows: int = 0
	if sys != null:
		# List all gear defs from EquipmentDefs (not just held ones — this is
		# the gear catalog; a real inventory filter can be added later).
		var defs: Array = _all_defs()
		for def in defs:
			var id: String = String(def.get("id", ""))
			if id == "":
				continue
			var equipped: bool = sys.has_method("is_equipped") and sys.call("is_equipped", id) == true
			_item_list.add_child(_make_item_row(id, _name_for(id), String(def.get("slot", "")), equipped))
			rows += 1
	if _empty_label != null:
		_empty_label.visible = rows == 0


func _refresh_stats() -> void:
	if _stat_label == null:
		return
	var sys: Node = _equip_system()
	if sys == null or not sys.has_method("derived_stats"):
		_stat_label.text = ""
		return
	var d: Dictionary = sys.call("derived_stats")
	var lines: Array[String] = []
	lines.append("Health:  %.0f" % float(d.get("max_health", 0.0)))
	lines.append("Oxygen:  %.0f" % float(d.get("max_oxygen", 0.0)))
	lines.append("Armor:   %.0f" % float(d.get("armor", 0.0)))
	lines.append("Carry:   %.0f" % float(d.get("carry_capacity", 0.0)))
	lines.append("Speed:   %.1f" % float(d.get("move_speed", 0.0)))
	lines.append("Sprint:  %.1fx" % float(d.get("sprint_multiplier", 0.0)))
	if sys.has_method("has_effect") and sys.call("has_effect", "atmosphere_protection"):
		lines.append("Atmo:    PROTECTED")
	_stat_label.text = "\n".join(lines)


func _make_item_row(item_id: String, item_name: String, slot: String, equipped: bool) -> Button:
	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_color_override("font_color", TEXT_PRIMARY if not equipped else TEXT_GOLD)
	row.add_theme_stylebox_override("normal", _row_stylebox(false))
	row.add_theme_stylebox_override("hover", _row_stylebox(true))
	row.add_theme_stylebox_override("pressed", _row_stylebox(true))
	row.add_theme_stylebox_override("focus", _row_stylebox(true))
	var meta: Dictionary = SLOT_META.get(slot, {})
	var slot_label: String = String(meta.get("label", slot))
	var suffix: String = "  (equipped)" if equipped else ""
	row.text = "  %s  [%s]%s" % [item_name, slot_label, suffix]
	row.pressed.connect(_on_item_pressed.bind(item_id))
	return row


func _on_item_pressed(item_id: String) -> void:
	var sys: Node = _equip_system()
	if sys == null or not sys.has_method("equip"):
		return
	sys.call("equip", item_id)


func _on_slot_input(event: InputEvent, slot: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var sys: Node = _equip_system()
	if sys == null:
		return
	var item_id: String = ""
	if sys.has_method("equipped_in"):
		item_id = String(sys.call("equipped_in", slot))
	if item_id == "":
		return
	if sys.has_method("unequip"):
		sys.call("unequip", slot)


# --- catalog helpers ---------------------------------------------------------

func _all_defs() -> Array:
	var defs_script: Script = load("res://scripts/data/equipment.gd")
	if defs_script == null:
		return []
	var defs: RefCounted = defs_script.new()
	return defs.call("all")


func _name_for(item_id: String) -> String:
	var defs_script: Script = load("res://scripts/data/equipment.gd")
	if defs_script == null:
		return item_id
	var defs: RefCounted = defs_script.new()
	var def: Dictionary = defs.call("by_id", item_id)
	return String(def.get("name", item_id))


func _short_name(item_id: String) -> String:
	var full: String = _name_for(item_id)
	if full.length() <= 12:
		return full
	return full.substr(0, 10) + ".."


# --- styling -----------------------------------------------------------------

func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	return sb


func _doll_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = SILHOUETTE_COLOR
	sb.border_color = SILHOUETTE_OUTLINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb


func _slot_stylebox(filled: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = SLOT_BG_FILLED if filled else SLOT_BG
	sb.border_color = ACCENT_GOLD if filled else ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_bottom = 16
	return sb


func _row_stylebox(active: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.44, 0.78, 0.45) if active else Color(0.06, 0.10, 0.15, 0.7)
	sb.border_color = ACCENT if active else Color(0.4, 0.6, 0.8, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	return sb