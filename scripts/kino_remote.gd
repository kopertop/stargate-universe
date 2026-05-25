extends Node

# Autoload. Owns the Kino Remote overlay UI — a five-page menu styled to
# match the in-fiction handheld prop: a vertical strip of 5 blue buttons on
# the left, an oval-styled "screen" panel on the right that shows the
# active page's content. Available globally once GameState.kino_acquired
# is true. Constructs its UI tree programmatically (no scene dependency)
# so it can attach to every scene's root without per-scene wiring.

const PAGE_MAP: int = 0
const PAGE_STATUS: int = 1
const PAGE_QUEST: int = 2
const PAGE_LOG: int = 3
const PAGE_INVENTORY: int = 4
# Short labels rendered on the 5 blue buttons (Ancient operator typically
# reads these in an unknown alphabet — for now plain ASCII).
const PAGE_LABELS: PackedStringArray = ["MAP", "STATUS", "QUEST", "LOG", "INV"]

# Map projection padding: leaves a small margin around each deck's bounding box
# so rooms at the edge don't render flush against the panel border.
const MAP_PADDING: float = 0.04
# Half-height of each deck panel inside the Map tab. Two decks stack vertically,
# with floor 1 on top, floor 0 on the bottom.
const DECK_SPAN_Y: float = 0.43

const PLAYER_MARKER_COLOR: Color = Color(0.55, 0.95, 1.0, 1.0)
const QUEST_TARGET_COLOR: Color = Color(1.0, 0.82, 0.36, 1.0)
const CUSTOM_TARGET_COLOR: Color = Color(0.45, 0.75, 1.0, 1.0)
const ROUTE_DOT_RADIUS: float = 3.0
const ROUTE_DOT_SPACING: float = 14.0  # pixels between dots along a segment

var _layer: CanvasLayer
var _root: Control
var _screen: PanelContainer
var _pages: Array[Control] = []
var _buttons: Array[Button] = []
var _active_page: int = PAGE_MAP
var _open: bool = false
var _initialized: bool = false
# Optional override target — set when the player clicks a room on the map.
# Empty string means "follow the active quest target" instead.
var _custom_target_id: String = ""
# room_id -> Vector2(anchor_x, anchor_y) in deck space (0..1 inside the page).
# Populated each refresh from the same projection math _draw_deck uses for
# room rectangles, so the overlay route can plot dots through the same coords.
var _room_anchors: Dictionary = {}
# The overlay Control that owns the route polyline + markers. Re-created on
# every _refresh_map call (simpler than incrementally diffing).
var _map_overlay: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Build UI deferred so it lands on top of every scene's layers.
	call_deferred("_init_ui")
	GameState.current_room_changed.connect(_on_current_room_changed)


func _on_current_room_changed(_room_id: String) -> void:
	# Cheap: redraw the map if the remote is open so the player dot follows
	# them between rooms without needing to reopen the menu.
	if _open:
		_refresh_map()

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

	# Outer frame — dark backdrop with cyan border, kino-remote scaled.
	var frame: PanelContainer = PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -560
	frame.offset_top = -340
	frame.offset_right = 560
	frame.offset_bottom = 340
	frame.add_theme_stylebox_override("panel", _panel_stylebox())
	_root.add_child(frame)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	var header: Label = Label.new()
	header.text = "KINO REMOTE — ANCIENT INTERFACE"
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1))
	header.add_theme_font_size_override("font_size", 20)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Body row: [button strip] | [oval screen]
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	vbox.add_child(body)

	# Left button strip — 5 blue Kino-Remote buttons stacked vertically.
	var btn_col: VBoxContainer = VBoxContainer.new()
	btn_col.custom_minimum_size = Vector2(140, 0)
	btn_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.add_theme_constant_override("separation", 14)
	body.add_child(btn_col)
	for i in range(PAGE_LABELS.size()):
		var b: Button = Button.new()
		b.text = PAGE_LABELS[i]
		b.custom_minimum_size = Vector2(124, 70)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_stylebox_override("normal", _button_stylebox(false))
		b.add_theme_stylebox_override("hover", _button_stylebox_hover())
		b.add_theme_stylebox_override("pressed", _button_stylebox(true))
		b.add_theme_stylebox_override("focus", _button_stylebox(true))
		b.pressed.connect(_on_page_button.bind(i))
		btn_col.add_child(b)
		_buttons.append(b)

	# Right oval "screen" panel — high corner radius reads as a flattened
	# oval display when seen against the surrounding dark frame.
	_screen = PanelContainer.new()
	_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen.custom_minimum_size = Vector2(0, 500)
	_screen.add_theme_stylebox_override("panel", _screen_stylebox())
	body.add_child(_screen)

	# A MarginContainer keeps page content inside the oval bounds.
	var screen_margin: MarginContainer = MarginContainer.new()
	screen_margin.add_theme_constant_override("margin_left", 28)
	screen_margin.add_theme_constant_override("margin_right", 28)
	screen_margin.add_theme_constant_override("margin_top", 22)
	screen_margin.add_theme_constant_override("margin_bottom", 22)
	_screen.add_child(screen_margin)

	# Pages live inside this stack; only the active page is visible.
	var page_stack: Control = Control.new()
	page_stack.name = "PageStack"
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_margin.add_child(page_stack)

	_build_map_page(page_stack)
	_build_status_page(page_stack)
	_build_quest_page(page_stack)
	_build_log_page(page_stack)
	_build_inventory_page(page_stack)

	var footer: Label = Label.new()
	footer.text = "[Tab] Close  •  [Esc] Resume"
	footer.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.75))
	footer.add_theme_font_size_override("font_size", 12)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)

	_select_page(PAGE_MAP)

func _panel_stylebox() -> StyleBoxFlat:
	# Outer frame — sharp-cornered dark panel framing the whole remote.
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.7, 1.0, 0.65)
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_right = 18
	sb.corner_radius_bottom_left = 18
	return sb


func _screen_stylebox() -> StyleBoxFlat:
	# Oval screen — high corner radius so the panel reads as a flat oval
	# display rather than a rectangle. Cyan emissive border, dark interior.
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.10, 1)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(0.4, 0.78, 1.0, 0.85)
	sb.corner_radius_top_left = 80
	sb.corner_radius_top_right = 80
	sb.corner_radius_bottom_right = 80
	sb.corner_radius_bottom_left = 80
	return sb


func _button_stylebox(active: bool) -> StyleBoxFlat:
	# Bright blue button — the Kino Remote's side-control accent strip.
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.36, 0.72, 1.0, 0.95) if active else Color(0.18, 0.44, 0.78, 0.9)
	sb.border_color = Color(0.65, 0.92, 1.0, 1.0) if active else Color(0.4, 0.72, 1.0, 0.85)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_right = 18
	sb.corner_radius_bottom_left = 18
	return sb


func _button_stylebox_hover() -> StyleBoxFlat:
	var sb: StyleBoxFlat = _button_stylebox(false)
	sb.bg_color = Color(0.28, 0.58, 0.92, 0.95)
	sb.border_color = Color(0.55, 0.85, 1.0, 1.0)
	return sb


func _build_map_page(parent: Control) -> void:
	var page: Control = Control.new()
	page.name = "Map"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(page)
	_pages.append(page)
	# Map nodes are placed deferred each open via _refresh_map so newly
	# discovered rooms appear without rebuilding the page.

func _build_status_page(parent: Control) -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Status"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	_pages.append(page)
	_label(page, "VITALS", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(page, "  Crew member: Eli Wallace", 14, Color.WHITE)
	_label(page, "  Vessel: Destiny (Ancient)", 14, Color.WHITE)
	_label(page, "  Status: stranded, ambulatory", 14, Color.WHITE)
	var q: Label = _label(page, "  Quest: —", 14, Color.WHITE)
	q.name = "QuestStepLabel"
	page.add_child(HSeparator.new())
	_label(page, "READINGS", 16, Color(0.55, 0.85, 1.0, 1.0))
	var h: Label = _label(page, "  Health: —", 14, Color.WHITE)
	h.name = "HealthLabel"
	var o: Label = _label(page, "  Oxygen: —", 14, Color.WHITE)
	o.name = "OxygenLabel"
	var r: Label = _label(page, "  Lime: —", 14, Color.WHITE)
	r.name = "LimeLabel"
	var scan: Label = _label(page, "  Planet scan: —", 14, Color(0.82, 0.92, 1.0, 0.9))
	scan.name = "PlanetScanLabel"

func _build_quest_page(parent: Control) -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Quest"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.add_theme_constant_override("separation", 8)
	parent.add_child(page)
	_pages.append(page)
	_label(page, "CURRENT", 16, Color(0.55, 0.85, 1.0, 1.0))
	var cur: Label = _label(page, "  —", 14, Color.WHITE)
	cur.name = "CurrentObjective"
	page.add_child(HSeparator.new())
	_label(page, "NEXT STEP", 14, Color(0.55, 0.85, 1.0, 0.85))
	var hint: Label = _label(page, "  —", 13, Color(0.8, 0.88, 1.0, 0.85))
	hint.name = "QuestHint"

func _build_log_page(parent: Control) -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Log"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.add_theme_constant_override("separation", 8)
	parent.add_child(page)
	_pages.append(page)
	_label(page, "MISSION LOG", 16, Color(0.55, 0.85, 1.0, 1.0))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var log_box: VBoxContainer = VBoxContainer.new()
	log_box.name = "LogBox"
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(log_box)

func _build_inventory_page(parent: Control) -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "Inventory"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.add_theme_constant_override("separation", 8)
	parent.add_child(page)
	_pages.append(page)
	_label(page, "ITEMS", 16, Color(0.55, 0.85, 1.0, 1.0))
	var inv: VBoxContainer = VBoxContainer.new()
	inv.name = "InventoryBox"
	page.add_child(inv)


func _on_page_button(idx: int) -> void:
	_select_page(idx)


func _select_page(idx: int) -> void:
	_active_page = idx
	for i in range(_pages.size()):
		_pages[i].visible = (i == idx)
	for i in range(_buttons.size()):
		_buttons[i].add_theme_stylebox_override("normal", _button_stylebox(i == idx))

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
	# Reset mouselook through view.gd — closing the Kino doesn't restore
	# Input.mouse_mode on its own, so RMB-held-during-open leaves the cursor
	# visible until the next RMB tap.
	GameState.kino_closed.emit()

func _refresh() -> void:
	_refresh_map()
	_refresh_status()
	_refresh_quest()
	_refresh_log()
	_refresh_inventory()

func _refresh_map() -> void:
	var page: Control = _pages[PAGE_MAP]
	for c in page.get_children():
		c.queue_free()
	_room_anchors.clear()
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.06, 0.12, 1)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	page.add_child(bg)
	# Floor 1 (upper) on top, floor 0 (main) below — matches deck stacking on Destiny.
	_draw_deck(page, 1, MAP_PADDING, MAP_PADDING + DECK_SPAN_Y, "DECK 1 — UPPER")
	_draw_deck(page, 0, 1.0 - DECK_SPAN_Y - MAP_PADDING, 1.0 - MAP_PADDING, "DECK 0 — MAIN")
	_install_map_overlay(page)


# Single overlay Control that spans the full Map page. It owns the player dot,
# the quest-target diamond, the custom-target marker (if any), and the dotted
# route polyline. _draw is called once per _refresh_map; the overlay queues
# itself for redraw whenever the anchors change.
func _install_map_overlay(page: Control) -> void:
	_map_overlay = Control.new()
	_map_overlay.name = "MapOverlay"
	_map_overlay.anchor_right = 1.0
	_map_overlay.anchor_bottom = 1.0
	_map_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_map_overlay)
	# Reparent to the front so dots draw above room rectangles.
	page.move_child(_map_overlay, page.get_child_count() - 1)
	_map_overlay.draw.connect(_on_overlay_draw)
	_map_overlay.resized.connect(_map_overlay.queue_redraw)
	_map_overlay.queue_redraw()


# Anchor-space (0..1 in page coords) → pixel position inside the overlay.
func _anchor_to_px(anchor: Vector2) -> Vector2:
	if _map_overlay == null:
		return Vector2.ZERO
	return Vector2(anchor.x * _map_overlay.size.x, anchor.y * _map_overlay.size.y)


# Route resolution: custom target wins over quest target. Returns "" if neither
# is set or if the player is already in the target room.
func _active_route_target() -> String:
	var target: String = _custom_target_id
	if target == "":
		var quest: Dictionary = GameState.quest_target()
		target = String(quest.get("room", ""))
	var from_id: String = GameState.current_room_id
	if from_id == "" or target == "" or target == from_id:
		return ""
	return target


func _on_overlay_draw() -> void:
	# Player marker (cyan dot).
	var current_anchor: Variant = _room_anchors.get(GameState.current_room_id, null)
	if current_anchor is Vector2:
		var px: Vector2 = _anchor_to_px(current_anchor as Vector2)
		_map_overlay.draw_circle(px, 6.0, Color(PLAYER_MARKER_COLOR.r, PLAYER_MARKER_COLOR.g, PLAYER_MARKER_COLOR.b, 0.35))
		_map_overlay.draw_circle(px, 4.0, PLAYER_MARKER_COLOR)

	# Quest-target diamond (gold).
	var quest: Dictionary = GameState.quest_target()
	var quest_room: String = String(quest.get("room", ""))
	if quest_room != "" and _room_anchors.has(quest_room):
		var qpx: Vector2 = _anchor_to_px(_room_anchors[quest_room])
		_draw_diamond(qpx, 7.0, QUEST_TARGET_COLOR)

	# Custom-target marker (blue ring around the target if set).
	if _custom_target_id != "" and _room_anchors.has(_custom_target_id):
		var cpx: Vector2 = _anchor_to_px(_room_anchors[_custom_target_id])
		_map_overlay.draw_arc(cpx, 11.0, 0.0, TAU, 32, CUSTOM_TARGET_COLOR, 2.0, true)

	# Dotted route.
	var target_id: String = _active_route_target()
	if target_id == "":
		return
	var path: PackedStringArray = ShipLayout.path_through_rooms(GameState.current_room_id, target_id)
	var dot_color: Color = CUSTOM_TARGET_COLOR if _custom_target_id != "" else QUEST_TARGET_COLOR
	# Iterate consecutive pairs, drop dots along each segment. Skip segments
	# where either endpoint is on a different deck (cross-floor — we mark
	# those with the elevator indicator instead). For now elevator is always
	# rendered as a straight hop; players still see the path is contiguous.
	for i in range(path.size() - 1):
		var a_id: String = path[i]
		var b_id: String = path[i + 1]
		if not (_room_anchors.has(a_id) and _room_anchors.has(b_id)):
			continue
		var a: Vector2 = _anchor_to_px(_room_anchors[a_id])
		var b: Vector2 = _anchor_to_px(_room_anchors[b_id])
		_draw_dotted_segment(a, b, dot_color)


func _draw_diamond(centre: Vector2, radius: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		centre + Vector2(0.0, -radius),
		centre + Vector2(radius, 0.0),
		centre + Vector2(0.0, radius),
		centre + Vector2(-radius, 0.0),
	])
	_map_overlay.draw_colored_polygon(pts, color)


func _draw_dotted_segment(a: Vector2, b: Vector2, color: Color) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.5:
		return
	var dir: Vector2 = (b - a) / dist
	var steps: int = int(floor(dist / ROUTE_DOT_SPACING))
	for s in range(steps + 1):
		var p: Vector2 = a + dir * float(s) * ROUTE_DOT_SPACING
		_map_overlay.draw_circle(p, ROUTE_DOT_RADIUS, color)

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
		var room_id: String = String(room["id"])
		var rx0: float = (float(room["startX"]) - min_x) / span_x
		var rx1: float = (float(room["endX"])   - min_x) / span_x
		var ry0: float = (float(room["startY"]) - min_y) / span_y
		var ry1: float = (float(room["endY"])   - min_y) / span_y
		var anchor_l: float = deck_left + rx0 * deck_w
		var anchor_r: float = deck_left + rx1 * deck_w
		var anchor_t: float = deck_top  + ry0 * deck_h
		var anchor_b: float = deck_top  + ry1 * deck_h
		# Record centre for the overlay (player/target dots, route polyline).
		_room_anchors[room_id] = Vector2(
			(anchor_l + anchor_r) * 0.5,
			(anchor_t + anchor_b) * 0.5,
		)
		# Use a Button so the room is clickable — click toggles _custom_target_id.
		# Visually it's still a flat panel; the Button is just an interactive shell.
		var rect: Button = Button.new()
		rect.anchor_left   = anchor_l
		rect.anchor_right  = anchor_r
		rect.anchor_top    = anchor_t
		rect.anchor_bottom = anchor_b
		rect.flat = true
		rect.focus_mode = Control.FOCUS_NONE
		rect.text = ""
		var discovered: bool = GameState.rooms_discovered.has(room_id)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		var sb_hover: StyleBoxFlat = StyleBoxFlat.new()
		if discovered:
			sb.bg_color = Color(0.2, 0.5, 0.85, 0.7)
			sb.border_color = Color(0.6, 0.85, 1.0, 0.95)
			sb_hover.bg_color = Color(0.32, 0.66, 0.95, 0.85)
			sb_hover.border_color = Color(0.85, 0.95, 1.0, 1.0)
		else:
			sb.bg_color = Color(0.08, 0.1, 0.14, 0.55)
			sb.border_color = Color(0.3, 0.4, 0.55, 0.5)
			sb_hover.bg_color = Color(0.16, 0.18, 0.22, 0.7)
			sb_hover.border_color = Color(0.45, 0.55, 0.65, 0.7)
		for box in [sb, sb_hover]:
			box.border_width_left = 1
			box.border_width_top = 1
			box.border_width_right = 1
			box.border_width_bottom = 1
			box.corner_radius_top_left = 2
			box.corner_radius_top_right = 2
			box.corner_radius_bottom_right = 2
			box.corner_radius_bottom_left = 2
		# Mark the current room with a brighter border so it never gets lost
		# behind the overlay's dots.
		if room_id == GameState.current_room_id:
			sb.border_color = PLAYER_MARKER_COLOR
		rect.add_theme_stylebox_override("normal", sb)
		rect.add_theme_stylebox_override("hover", sb_hover)
		rect.add_theme_stylebox_override("pressed", sb_hover)
		rect.add_theme_stylebox_override("focus", sb_hover)
		# Click handler: toggle this room as the custom route target. Clicking
		# an already-selected room clears the override and reverts to the
		# active-quest route.
		rect.pressed.connect(_on_room_clicked.bind(room_id))
		var l: Label = Label.new()
		l.anchor_right = 1.0
		l.anchor_bottom = 1.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text = String(room.get("name", "???")) if discovered else "???"
		l.add_theme_font_size_override("font_size", 9)
		l.add_theme_color_override("font_color", Color.WHITE if discovered else Color(0.5, 0.55, 0.6, 0.9))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.add_child(l)
		page.add_child(rect)


func _on_room_clicked(room_id: String) -> void:
	if _custom_target_id == room_id:
		_custom_target_id = ""
	else:
		_custom_target_id = room_id
	if _map_overlay != null:
		_map_overlay.queue_redraw()

func _refresh_status() -> void:
	var page: Node = _pages[PAGE_STATUS]
	var h: Label = page.get_node_or_null("HealthLabel") as Label
	var o: Label = page.get_node_or_null("OxygenLabel") as Label
	var q: Label = page.get_node_or_null("QuestStepLabel") as Label
	var r: Label = page.get_node_or_null("LimeLabel") as Label
	var scan: Label = page.get_node_or_null("PlanetScanLabel") as Label
	if q != null:
		q.text = "  Quest:  %s" % GameState.quest_step_label()
	if h != null:
		h.text = "  Health:  %d / 100" % int(GameState.health)
	if o != null:
		o.text = "  Oxygen:  %d / 100" % int(GameState.oxygen)
	if r != null:
		r.text = "  Lime:  %d / %d" % [
			GameState.resource_count(GameState.AIR_LIME_RESOURCE),
			GameState.AIR_LIME_REQUIRED,
		]
	if scan != null:
		if GameState.lime_planet_dialed:
			scan.text = "  Planet scan: air_lime_world — lime deposits confirmed"
		elif GameState.ftl_drop_triggered:
			scan.text = "  Planet scan: viable address pending gate dial"
		else:
			scan.text = "  Planet scan: no active offworld scan"

func _refresh_quest() -> void:
	var page: Node = _pages[PAGE_QUEST]
	var cur: Label = page.get_node_or_null("CurrentObjective") as Label
	if cur != null:
		cur.text = "  [%s] %s" % [GameState.quest_step_label(), GameState.current_objective]
	var hint: Label = page.get_node_or_null("QuestHint") as Label
	if hint != null:
		var target: Dictionary = GameState.quest_target()
		var room_id: String = String(target.get("room", ""))
		if room_id == "":
			hint.text = "  —"
		else:
			var room_data: Dictionary = ShipLayout.room(room_id)
			var room_name: String = String(room_data.get("name", room_id))
			var anchor: String = String(target.get("anchor", ""))
			if anchor == "":
				hint.text = "  Head to %s." % room_name
			else:
				hint.text = "  In %s — interact with %s." % [room_name, anchor]


func _refresh_log() -> void:
	var page: Node = _pages[PAGE_LOG]
	# LogBox is wrapped in a ScrollContainer; recurse with find_child.
	var box: VBoxContainer = page.find_child("LogBox", true, false) as VBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	var entries: Array[String] = GameState.log_entries.duplicate()
	entries.reverse()
	for line in entries:
		_label(box, "  • " + line, 13, Color(0.85, 0.92, 1.0, 0.9))


func _refresh_inventory() -> void:
	var page: Node = _pages[PAGE_INVENTORY]
	var box: VBoxContainer = page.get_node_or_null("InventoryBox") as VBoxContainer
	if box != null:
		for c in box.get_children():
			c.queue_free()
		if GameState.kino_acquired:
			_label(box, "  • Kino Remote", 14, Color.WHITE)
		if GameState.breaches_sealed.size() > 0:
			_label(box, "  • Emergency Seal — used (%d)" % GameState.breaches_sealed.size(), 14, Color.WHITE)
		for resource_type in GameState.resources.keys():
			var count: int = GameState.resource_count(String(resource_type))
			if count > 0:
				_label(box, "  • %s × %d" % [String(resource_type).capitalize(), count], 14, Color.WHITE)
		if box.get_child_count() == 0:
			_label(box, "  (empty)", 14, Color(0.7, 0.7, 0.7, 0.85))
