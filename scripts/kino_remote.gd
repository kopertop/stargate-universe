extends Node

# Autoload. Owns the Kino Remote overlay UI — a Pip-Boy-style four-tab pause menu
# available globally once GameState.kino_acquired is true. Constructs its UI tree
# programmatically (no scene dependency) so it can attach to every scene's root
# without needing per-scene wiring.

const TAB_MAP: int = 0
const TAB_STATUS: int = 1
const TAB_OBJECTIVES: int = 2
const TAB_INVENTORY: int = 3

# Map projection padding: leaves a small margin around each deck's bounding box
# so rooms at the edge don't render flush against the panel border.
const MAP_PADDING: float = 0.04
# Half-height of each deck panel inside the Map tab. Two decks stack vertically,
# with floor 1 on top, floor 0 on the bottom.
const DECK_SPAN_Y: float = 0.43

var _layer: CanvasLayer
var _root: Control
var _tabs: TabContainer
var _open: bool = false
var _initialized: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Build UI deferred so it lands on top of every scene's layers.
	call_deferred("_init_ui")

func _init_ui() -> void:
	if _initialized:
		return
	_initialized = true
	_layer = CanvasLayer.new()
	_layer.layer = 80
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.06, 0.92)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_root.add_child(bg)

	var frame: PanelContainer = PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -520
	frame.offset_top = -320
	frame.offset_right = 520
	frame.offset_bottom = 320
	frame.add_theme_stylebox_override("panel", _panel_stylebox())
	_root.add_child(frame)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	frame.add_child(vbox)

	var header: Label = Label.new()
	header.text = "KINO REMOTE — ANCIENT INTERFACE"
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1))
	header.add_theme_font_size_override("font_size", 20)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 520)
	vbox.add_child(_tabs)

	_build_map_tab()
	_build_status_tab()
	_build_objectives_tab()
	_build_inventory_tab()

	var footer: Label = Label.new()
	footer.text = "[Tab] Close  •  [Esc] Resume"
	footer.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.75))
	footer.add_theme_font_size_override("font_size", 12)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)

func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.7, 1.0, 0.65)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _build_map_tab() -> void:
	var page: Control = Control.new()
	page.name = "Map"
	page.custom_minimum_size = Vector2(0, 480)
	_tabs.add_child(page)
	# Map nodes are placed deferred each open via _refresh_map so newly discovered
	# rooms appear without rebuilding the tab.

func _build_status_tab() -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Status"
	page.add_theme_constant_override("separation", 10)
	_tabs.add_child(page)
	_label(page, "VITALS", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(page, "  Crew member: Eli Wallace", 14, Color.WHITE)
	_label(page, "  Vessel: Destiny (Ancient)", 14, Color.WHITE)
	_label(page, "  Status: stranded, ambulatory", 14, Color.WHITE)
	page.add_child(HSeparator.new())
	_label(page, "READINGS", 16, Color(0.55, 0.85, 1.0, 1.0))
	var h: Label = _label(page, "  Health: —", 14, Color.WHITE)
	h.name = "HealthLabel"
	var o: Label = _label(page, "  Oxygen: —", 14, Color.WHITE)
	o.name = "OxygenLabel"

func _build_objectives_tab() -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Objectives"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	_label(page, "CURRENT", 16, Color(0.55, 0.85, 1.0, 1.0))
	var cur: Label = _label(page, "  —", 14, Color.WHITE)
	cur.name = "CurrentObjective"
	page.add_child(HSeparator.new())
	_label(page, "LOG", 16, Color(0.55, 0.85, 1.0, 1.0))
	var log_box: VBoxContainer = VBoxContainer.new()
	log_box.name = "LogBox"
	page.add_child(log_box)

func _build_inventory_tab() -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Inventory"
	page.add_theme_constant_override("separation", 8)
	_tabs.add_child(page)
	_label(page, "ITEMS", 16, Color(0.55, 0.85, 1.0, 1.0))
	var inv: VBoxContainer = VBoxContainer.new()
	inv.name = "InventoryBox"
	page.add_child(inv)

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("kino_remote") and GameState.kino_acquired:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and _open:
		_close()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_remote()

func _open_remote() -> void:
	if not _initialized:
		_init_ui()
	_open = true
	_root.visible = true
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	get_tree().paused = false

func _refresh() -> void:
	_refresh_map()
	_refresh_status()
	_refresh_objectives()
	_refresh_inventory()

func _refresh_map() -> void:
	var page: Control = _tabs.get_node("Map")
	for c in page.get_children():
		c.queue_free()
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.06, 0.12, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	page.add_child(bg)
	# Floor 1 (upper) on top, floor 0 (main) below — matches deck stacking on Destiny.
	_draw_deck(page, 1, MAP_PADDING, MAP_PADDING + DECK_SPAN_Y, "DECK 1 — UPPER")
	_draw_deck(page, 0, 1.0 - DECK_SPAN_Y - MAP_PADDING, 1.0 - MAP_PADDING, "DECK 0 — MAIN")

func _draw_deck(page: Control, floor_id: int, y_top: float, y_bot: float, title: String) -> void:
	# Gather rooms on this deck and their bounding box in JSON-space.
	var rooms: Array = []
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for room in ShipLayout.all_rooms():
		if int(room.get("floor", 0)) != floor_id:
			continue
		rooms.append(room)
		min_x = min(min_x, float(room["startX"]))
		max_x = max(max_x, float(room["endX"]))
		min_y = min(min_y, float(room["startY"]))
		max_y = max(max_y, float(room["endY"]))
	if rooms.is_empty():
		return
	var span_x: float = max(1.0, max_x - min_x)
	var span_y: float = max(1.0, max_y - min_y)

	# Deck title strip
	var header: Label = Label.new()
	header.text = title
	header.anchor_left = MAP_PADDING
	header.anchor_right = 1.0 - MAP_PADDING
	header.anchor_top = y_top
	header.anchor_bottom = y_top
	header.offset_bottom = 16
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.85))
	page.add_child(header)

	var deck_top: float = y_top + 0.04
	var deck_bot: float = y_bot
	var deck_left: float = MAP_PADDING
	var deck_right: float = 1.0 - MAP_PADDING
	var deck_w: float = deck_right - deck_left
	var deck_h: float = deck_bot - deck_top

	for room in rooms:
		var rx0: float = (float(room["startX"]) - min_x) / span_x
		var rx1: float = (float(room["endX"])   - min_x) / span_x
		var ry0: float = (float(room["startY"]) - min_y) / span_y
		var ry1: float = (float(room["endY"])   - min_y) / span_y
		var rect: Panel = Panel.new()
		rect.anchor_left   = deck_left + rx0 * deck_w
		rect.anchor_right  = deck_left + rx1 * deck_w
		rect.anchor_top    = deck_top  + ry0 * deck_h
		rect.anchor_bottom = deck_top  + ry1 * deck_h
		var discovered: bool = GameState.rooms_discovered.has(room["id"])
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		if discovered:
			sb.bg_color = Color(0.2, 0.5, 0.85, 0.7)
			sb.border_color = Color(0.6, 0.85, 1.0, 0.95)
		else:
			sb.bg_color = Color(0.08, 0.1, 0.14, 0.55)
			sb.border_color = Color(0.3, 0.4, 0.55, 0.5)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_right = 2
		sb.corner_radius_bottom_left = 2
		rect.add_theme_stylebox_override("panel", sb)
		var l: Label = Label.new()
		l.anchor_right = 1.0
		l.anchor_bottom = 1.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text = String(room.get("name", "???")) if discovered else "???"
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_color_override("font_color", Color.WHITE if discovered else Color(0.5, 0.55, 0.6, 0.9))
		rect.add_child(l)
		page.add_child(rect)

func _refresh_status() -> void:
	var page: Node = _tabs.get_node("Status")
	var h: Label = page.get_node_or_null("HealthLabel") as Label
	var o: Label = page.get_node_or_null("OxygenLabel") as Label
	if h != null:
		h.text = "  Health:  %d / 100" % int(GameState.health)
	if o != null:
		o.text = "  Oxygen:  %d / 100" % int(GameState.oxygen)

func _refresh_objectives() -> void:
	var page: Node = _tabs.get_node("Objectives")
	var cur: Label = page.get_node_or_null("CurrentObjective") as Label
	if cur != null:
		cur.text = "  " + GameState.current_objective
	var box: VBoxContainer = page.get_node_or_null("LogBox") as VBoxContainer
	if box != null:
		for c in box.get_children():
			c.queue_free()
		var entries: Array[String] = GameState.log_entries.duplicate()
		entries.reverse()
		for line in entries:
			_label(box, "  • " + line, 13, Color(0.85, 0.92, 1.0, 0.9))

func _refresh_inventory() -> void:
	var page: Node = _tabs.get_node("Inventory")
	var box: VBoxContainer = page.get_node_or_null("InventoryBox") as VBoxContainer
	if box != null:
		for c in box.get_children():
			c.queue_free()
		if GameState.kino_acquired:
			_label(box, "  • Kino Remote", 14, Color.WHITE)
		if GameState.breaches_sealed.size() > 0:
			_label(box, "  • Emergency Seal — used (%d)" % GameState.breaches_sealed.size(), 14, Color.WHITE)
		if box.get_child_count() == 0:
			_label(box, "  (empty)", 14, Color(0.7, 0.7, 0.7, 0.85))
