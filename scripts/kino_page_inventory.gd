class_name KinoPageInventory
extends Node

# Inventory page for the Kino Remote. Slot grid (left) + selected-item detail
# panel (right). Both rebuilt from Inventory.entries() — the page never names
# a specific item, so any catalog item appears automatically.

const INVENTORY_COLUMNS: int = 5
const INVENTORY_SLOT_SIZE: Vector2 = Vector2(92, 92)
const INVENTORY_CATEGORY_COLORS: Dictionary = {
	"tool": Color(0.30, 0.55, 0.85),
	"resource": Color(0.30, 0.62, 0.42),
	"story_item": Color(0.80, 0.62, 0.28),
}

var _coordinator: Node
var _page: Control

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "Inventory"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 10)
	parent.add_child(_page)
	_label(_page, "ITEMS", 16, Color(0.55, 0.85, 1.0, 1.0))

	# Slot grid (left) + selected-item detail panel (right). Both rebuilt by
	# refresh from Inventory.entries() — the page never names a specific
	# item, so any catalog item appears automatically.
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "InventoryBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	_page.add_child(body)

	var grid: GridContainer = GridContainer.new()
	grid.name = "SlotGrid"
	grid.columns = INVENTORY_COLUMNS
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)

	var detail: VBoxContainer = VBoxContainer.new()
	detail.name = "DetailPanel"
	detail.custom_minimum_size = Vector2(340, 0)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	body.add_child(detail)
	return _page

func refresh() -> void:
	var grid: GridContainer = _page.get_node_or_null("InventoryBody/SlotGrid") as GridContainer
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	# Single generic pass over the unified inventory model. Every carried
	# item — Kino Remote, rations, lime, AND the looted fuses — comes back
	# from one enumerable surface, so nothing can silently fail to render
	# (the looted-fuse bug, #41). Item metadata is data (data/items.json).
	var entries: Array = Inventory.entries()
	for entry in entries:
		grid.add_child(_make_inventory_slot(entry))
	if entries.is_empty():
		_label(grid, "(empty)", 14, Color(0.7, 0.7, 0.7, 0.85))
		_show_item_hint("Your pack is empty.")
	else:
		# Auto-select the first item so the detail panel isn't blank.
		_show_item_detail(entries[0]["def"], int(entries[0]["count"]))

func is_available() -> bool:
	return true

# Build one inventory slot: category-tinted tile, icon (texture if the catalog
# provides one, else a procedural glyph), a stack-count badge, a hover tooltip,
# and click-to-inspect wiring.
func _make_inventory_slot(entry: Dictionary) -> Control:
	var def: Dictionary = entry["def"]
	var id: String = String(entry["id"])
	var cnt: int = int(entry["count"])
	var item_name: String = String(def.get("name", id.capitalize()))
	var category: String = String(def.get("category", "resource"))
	var base: Color = INVENTORY_CATEGORY_COLORS.get(category, Color(0.42, 0.44, 0.5))

	var slot: Panel = Panel.new()
	slot.custom_minimum_size = INVENTORY_SLOT_SIZE
	slot.tooltip_text = "%s\n%s" % [item_name, String(def.get("description", ""))]
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(base.r, base.g, base.b, 0.22)
	sb.border_color = Color(base.r, base.g, base.b, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	slot.add_theme_stylebox_override("panel", sb)

	var icon_path: String = String(def.get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex: TextureRect = TextureRect.new()
		tex.texture = load(icon_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.anchor_right = 1.0
		tex.anchor_bottom = 1.0
		tex.offset_left = 8
		tex.offset_top = 8
		tex.offset_right = -8
		tex.offset_bottom = -8
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex)
	else:
		var glyph: Label = Label.new()
		glyph.text = _item_glyph(item_name)
		glyph.add_theme_font_size_override("font_size", 32)
		glyph.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.anchor_right = 1.0
		glyph.anchor_bottom = 1.0
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(glyph)

	if cnt > 1:
		var badge: Label = Label.new()
		badge.text = "×%d" % cnt
		badge.add_theme_font_size_override("font_size", 15)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.anchor_left = 1.0
		badge.anchor_top = 1.0
		badge.anchor_right = 1.0
		badge.anchor_bottom = 1.0
		badge.offset_left = -36
		badge.offset_top = -26
		badge.offset_right = -6
		badge.offset_bottom = -4
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(badge)

	slot.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_item_detail(def, cnt))
	return slot

# First 1–2 letters of the item name, for the procedural icon when no texture
# is supplied. Real art drops in later via the catalog `icon` field.
func _item_glyph(item_name: String) -> String:
	var first_word: String = item_name.strip_edges().split(" ")[0]
	return first_word.substr(0, 2).capitalize() if first_word.length() >= 2 else first_word.to_upper()

func _show_item_detail(def: Dictionary, cnt: int) -> void:
	var detail: VBoxContainer = _page.get_node_or_null("InventoryBody/DetailPanel") as VBoxContainer
	if detail == null:
		return
	for c in detail.get_children():
		c.queue_free()
	var title: String = String(def.get("name", ""))
	if cnt > 1:
		title += "  ×%d" % cnt
	_label(detail, title, 18, Color(0.85, 0.93, 1.0))
	var cat: String = String(def.get("category", "")).replace("_", " ").capitalize()
	_label(detail, cat, 12, Color(0.55, 0.75, 0.95))
	detail.add_child(HSeparator.new())
	var desc: Label = _label(detail, String(def.get("description", "")), 13, Color(0.82, 0.86, 0.92))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(320, 0)

func _show_item_hint(text: String) -> void:
	var detail: VBoxContainer = _page.get_node_or_null("InventoryBody/DetailPanel") as VBoxContainer
	if detail == null:
		return
	for c in detail.get_children():
		c.queue_free()
	_label(detail, text, 13, Color(0.7, 0.7, 0.7, 0.85))

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l