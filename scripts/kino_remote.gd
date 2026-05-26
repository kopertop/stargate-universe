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
const MAP_AABB_MARGIN_FRAC: float = 0.18
# Pixel reservations inside the Map page for HUD chrome.
const MAP_HUD_TOP: float = 36.0       # title + deck label header
const MAP_HUD_BOTTOM: float = 44.0    # zoom slider + status readouts
const MAP_HUD_SIDE: float = 16.0      # left/right padding

const PLAYER_MARKER_COLOR: Color = Color(0.55, 0.95, 1.0, 1.0)
const QUEST_TARGET_COLOR: Color = Color(1.0, 0.82, 0.36, 1.0)
const CUSTOM_TARGET_COLOR: Color = Color(0.45, 0.75, 1.0, 1.0)
const ROUTE_DOT_RADIUS: float = 3.0
const ROUTE_DOT_SPACING: float = 14.0  # pixels between dots along a segment

# Visual constants for the new MapView pipeline. Match the project's
# established cyan-tech palette (see CLAUDE.md + wall-sconce / console-screen
# code).
const MAP_BG_COLOR: Color = Color(0.02, 0.06, 0.12, 1.0)
const MAP_GRID_COLOR: Color = Color(0.15, 0.30, 0.45, 0.35)
const MAP_GRID_PITCH: float = 50.0
const ROOM_OUTLINE_COLOR: Color = Color(0.55, 0.85, 1.0, 0.95)
const ROOM_FILL_COLOR: Color = Color(0.20, 0.55, 0.95, 0.10)
const ROOM_OUTLINE_CURRENT_COLOR: Color = Color(0.80, 0.95, 1.0, 1.0)
const PIP_OPEN_COLOR: Color = Color(0.55, 0.90, 1.0, 1.0)
const PIP_TRAVERSED_COLOR: Color = Color(0.45, 0.65, 0.85, 0.6)
const PIP_LOCKED_COLOR: Color = Color(1.0, 0.65, 0.20, 1.0)
const PIP_HARDLOCK_COLOR: Color = Color(1.0, 0.30, 0.30, 1.0)
const PIP_LENGTH: float = 14.0   # along-wall dimension
const PIP_DEPTH: float = 5.0     # perpendicular protrusion
const CONNECTION_LINE_COLOR: Color = Color(0.35, 0.60, 0.90, 0.55)
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 2.5
const ZOOM_DEFAULT: float = 1.0

var _layer: CanvasLayer
var _root: Control
var _screen: PanelContainer
var _pages: Array[Control] = []
var _buttons: Array[Button] = []
var _active_page: int = PAGE_MAP
var _open: bool = false
var _initialized: bool = false
# Single Control that owns the entire map geometry — per-room grids,
# outlines + glyphs, door pips, player marker, quest diamond, custom-target
# ring, dotted route, corner brackets, N arrow. Rebuilt each `_refresh_map`.
# Pan/zoom + click/drag/right-click routed through gui_input.
var _map_view: Control = null
# Pixel offset applied AFTER the world→pixel scale projection. Updated by
# left-button drag and wheel zoom. Reset by recompute when a fresh deck is
# entered or _zoom is reset to default.
var _pan_offset: Vector2 = Vector2.ZERO
# Drag tracking for the pan gesture (left mouse button).
var _is_panning: bool = false
var _pan_last_mouse: Vector2 = Vector2.ZERO
# 0.5–2.5 multiplier applied to the AABB→viewport scale.
var _zoom: float = ZOOM_DEFAULT
# Which floor is currently shown. -1 means "track GameState.current_room_id";
# any other value overrides via the level-switcher bar.
var _active_floor_override: int = -1
# Right-click "place marker": persistent map pin. Format:
#   { "floor": int, "world": Vector2 }  or  null
var _placed_marker: Variant = null
# Cached projection for the active floor. {
#   "rect": Rect2 in MapView pixel space (full map area),
#   "origin_world": Vector2 (centre of expanded AABB in JSON units),
#   "scale": float (JSON-units → pixels, pre-pan),
# }. null when no discovered room is on the active floor.
var _deck_transform: Dictionary = {}
# HUD readouts on the map page — refreshed each _refresh_map + via the
# new GameState signals (oxygen_changed / power_changed / hull_changed).
var _status_power: Label = null
var _status_oxygen: Label = null
var _status_hull: Label = null
var _map_deck_label: Label = null
var _zoom_slider: HSlider = null
var _level_bar: VBoxContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Build UI deferred so it lands on top of every scene's layers.
	call_deferred("_init_ui")
	GameState.current_room_changed.connect(_on_current_room_changed)
	GameState.room_discovered.connect(_on_room_discovered)
	GameState.door_traversed.connect(_on_door_traversed)
	GameState.oxygen_changed.connect(_on_status_changed)
	GameState.power_changed.connect(_on_status_changed)
	GameState.hull_changed.connect(_on_status_changed)


func _on_room_discovered(_room_id: String) -> void:
	if _open:
		_refresh_map()


func _on_door_traversed(_key: String) -> void:
	if _open:
		_refresh_map()


func _on_status_changed(_value: float) -> void:
	if _open:
		_refresh_status_readouts()


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

	# Outer frame — dark backdrop with cyan border. Near-fullscreen so the
	# map page has the whole viewport rather than a centered ~1100px window.
	var frame: PanelContainer = PanelContainer.new()
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = 24
	frame.offset_top = 24
	frame.offset_right = -24
	frame.offset_bottom = -24
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

# Rebuild the entire map page: dark backdrop, HUD chrome (title, deck label,
# zoom slider, status readouts), and a single MapView Control whose _draw
# callback owns every piece of map geometry. All discovery / door-traversal
# state is read live from GameState during draw, so this rebuild is idempotent
# and called by every signal that affects the map.
func _refresh_map() -> void:
	var page: Control = _pages[PAGE_MAP]
	for c in page.get_children():
		c.queue_free()

	var bg: ColorRect = ColorRect.new()
	bg.color = MAP_BG_COLOR
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(bg)

	# Header — "DESTINY MAP SYSTEM" + deck banner.
	var title: Label = Label.new()
	title.text = "DESTINY MAP SYSTEM"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	title.position = Vector2(MAP_HUD_SIDE, 4.0)
	page.add_child(title)

	_map_deck_label = Label.new()
	_map_deck_label.add_theme_font_size_override("font_size", 10)
	_map_deck_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.6))
	_map_deck_label.position = Vector2(MAP_HUD_SIDE, 20.0)
	page.add_child(_map_deck_label)
	_map_deck_label.text = _deck_subtitle()

	# Zoom slider along the bottom-left.
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = ZOOM_MIN
	_zoom_slider.max_value = ZOOM_MAX
	_zoom_slider.step = 0.05
	_zoom_slider.value = _zoom
	_zoom_slider.anchor_left = 0.04
	_zoom_slider.anchor_right = 0.40
	_zoom_slider.anchor_top = 1.0
	_zoom_slider.anchor_bottom = 1.0
	_zoom_slider.offset_top = -32.0
	_zoom_slider.offset_bottom = -8.0
	_zoom_slider.value_changed.connect(_on_zoom_changed)
	page.add_child(_zoom_slider)

	var zoom_label: Label = Label.new()
	zoom_label.text = "ZOOM"
	zoom_label.add_theme_font_size_override("font_size", 9)
	zoom_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.7))
	zoom_label.anchor_left = 0.04
	zoom_label.anchor_top = 1.0
	zoom_label.offset_top = -46.0
	zoom_label.offset_right = 60.0
	page.add_child(zoom_label)

	# Status readouts (right side). Future power/hull systems publish via
	# GameState.set_power_percent / set_hull_percent — handled live via
	# the *_changed signals + _on_status_changed.
	_status_power = Label.new()
	_status_power.add_theme_font_size_override("font_size", 10)
	_status_power.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.95))
	_status_power.anchor_left = 0.55
	_status_power.anchor_right = 0.72
	_status_power.anchor_top = 1.0
	_status_power.anchor_bottom = 1.0
	_status_power.offset_top = -28.0
	_status_power.offset_bottom = -8.0
	page.add_child(_status_power)

	_status_oxygen = Label.new()
	_status_oxygen.add_theme_font_size_override("font_size", 10)
	_status_oxygen.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.95))
	_status_oxygen.anchor_left = 0.72
	_status_oxygen.anchor_right = 0.86
	_status_oxygen.anchor_top = 1.0
	_status_oxygen.anchor_bottom = 1.0
	_status_oxygen.offset_top = -28.0
	_status_oxygen.offset_bottom = -8.0
	page.add_child(_status_oxygen)

	_status_hull = Label.new()
	_status_hull.add_theme_font_size_override("font_size", 10)
	_status_hull.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 0.95))
	_status_hull.anchor_left = 0.86
	_status_hull.anchor_right = 0.98
	_status_hull.anchor_top = 1.0
	_status_hull.anchor_bottom = 1.0
	_status_hull.offset_top = -28.0
	_status_hull.offset_bottom = -8.0
	page.add_child(_status_hull)

	_refresh_status_readouts()

	# Level-switcher bar — vertical strip on the right side of the map page,
	# one button per discovered deck. Hidden by default until additional
	# floors come online; rebuilds inside _refresh_map so future floors land
	# automatically (composability).
	_level_bar = VBoxContainer.new()
	_level_bar.name = "LevelBar"
	_level_bar.anchor_left = 1.0
	_level_bar.anchor_right = 1.0
	_level_bar.anchor_top = 0.0
	_level_bar.anchor_bottom = 1.0
	_level_bar.offset_left = -64.0
	_level_bar.offset_right = -MAP_HUD_SIDE
	_level_bar.offset_top = MAP_HUD_TOP + 8.0
	_level_bar.offset_bottom = -MAP_HUD_BOTTOM
	_level_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	_level_bar.add_theme_constant_override("separation", 6)
	page.add_child(_level_bar)
	_rebuild_level_bar()

	# MapView — KinoMapView subclass owns the _draw() override (Godot 4
	# requires draw_* calls to live inside the canvas item's own draw
	# context). It emits needs_geometry; we render to the supplied canvas.
	const MapViewScript: Script = preload("res://scripts/kino_map_view.gd")
	_map_view = MapViewScript.new()
	_map_view.name = "MapView"
	_map_view.anchor_right = 1.0
	_map_view.anchor_bottom = 1.0
	_map_view.offset_top = MAP_HUD_TOP
	_map_view.offset_bottom = -MAP_HUD_BOTTOM
	_map_view.offset_left = MAP_HUD_SIDE
	# Reserve a strip on the right when the level bar is visible (>=2 floors).
	_map_view.offset_right = -MAP_HUD_SIDE - (48.0 if _level_bar.visible else 0.0)
	_map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	(_map_view as Object).connect("needs_geometry", _on_map_view_draw)
	_map_view.gui_input.connect(_on_map_view_input)
	_map_view.resized.connect(_map_view.queue_redraw)
	page.add_child(_map_view)
	_map_view.queue_redraw()


# Active floor = level-bar override if set, else the floor the player is
# currently in, else 0. Lookup-only — no side effects.
func _active_floor() -> int:
	if _active_floor_override >= 0:
		return _active_floor_override
	var room: Dictionary = ShipLayout.room(GameState.current_room_id)
	if not room.is_empty():
		return int(room.get("floor", 0))
	return 0


func _deck_subtitle() -> String:
	var f: int = _active_floor()
	return ("DECK %d — UPPER" % f) if f == 1 else ("DECK %d — MAIN" % f)


func _rebuild_level_bar() -> void:
	if _level_bar == null:
		return
	for c in _level_bar.get_children():
		c.queue_free()
	# Enumerate floors that contain at least one DISCOVERED room. Sorted
	# descending so floor 1 (upper) sits above floor 0 (main).
	var floors: Array = []
	for room_id in GameState.rooms_discovered:
		var r: Dictionary = ShipLayout.room(room_id)
		if r.is_empty():
			continue
		var f: int = int(r.get("floor", 0))
		if not floors.has(f):
			floors.append(f)
	floors.sort()
	floors.reverse()
	# Bar stays hidden by default per the user request ("hidden for now,
	# we'll have other levels later"). Flip `_level_bar.visible = true`
	# manually when more decks justify it.
	for f in floors:
		var b: Button = Button.new()
		b.text = "L%d" % f
		b.custom_minimum_size = Vector2(40, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_font_size_override("font_size", 13)
		var active: bool = (f == _active_floor())
		b.add_theme_stylebox_override("normal", _button_stylebox(active))
		b.add_theme_stylebox_override("hover", _button_stylebox_hover())
		b.pressed.connect(_on_level_button.bind(int(f)))
		_level_bar.add_child(b)


func _on_level_button(floor_id: int) -> void:
	_active_floor_override = floor_id
	_pan_offset = Vector2.ZERO  # Reset pan when switching decks.
	if _map_deck_label != null:
		_map_deck_label.text = _deck_subtitle()
	_rebuild_level_bar()
	if _map_view != null:
		_map_view.queue_redraw()


func _refresh_status_readouts() -> void:
	if _status_oxygen != null:
		_status_oxygen.text = "O2  %d%%" % int(GameState.oxygen)
	if _status_power != null:
		_status_power.text = _format_status("POWER", GameState.power_percent)
	if _status_hull != null:
		_status_hull.text = _format_status("HULL", GameState.hull_percent)


func _format_status(label: String, value: float) -> String:
	if value <= GameState.STATUS_OFFLINE + 0.001:
		return "%s  OFFLINE" % label
	return "%s  %d%%" % [label, int(value)]


func _on_zoom_changed(value: float) -> void:
	_zoom = value
	if _map_view != null:
		_map_view.queue_redraw()


# Route resolution: placed marker wins over the active quest target.
# Returns "" if neither resolves or if the player is already there.
func _active_route_target() -> String:
	var target: String = _placed_marker_room()
	if target == "":
		var quest: Dictionary = GameState.quest_target()
		target = String(quest.get("room", ""))
	var from_id: String = GameState.current_room_id
	if from_id == "" or target == "" or target == from_id:
		return ""
	return target


# Compute ONE transform for the active floor, filling the entire MapView
# rect. AABB is taken over discovered rooms on that floor only, so the
# fit auto-tightens as the player explores. `_pan_offset` and `_zoom`
# layer on top so click-drag + wheel-zoom move the visible window.
func _compute_deck_transforms() -> void:
	_deck_transform = {}
	if _map_view == null:
		return
	var size: Vector2 = _map_view.size
	if size.x <= 0 or size.y <= 0:
		return
	var floor_id: int = _active_floor()
	var aabb: Rect2 = Rect2()
	var has_any: bool = false
	for room_id in GameState.rooms_discovered:
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		var sx: float = float(room["startX"])
		var sy: float = float(room["startY"])
		var ex: float = float(room["endX"])
		var ey: float = float(room["endY"])
		var room_rect: Rect2 = Rect2(Vector2(sx, sy), Vector2(ex - sx, ey - sy))
		if has_any:
			aabb = aabb.merge(room_rect)
		else:
			aabb = room_rect
			has_any = true
	if not has_any:
		return
	var margin: float = max(aabb.size.x, aabb.size.y) * MAP_AABB_MARGIN_FRAC
	aabb = aabb.grow(margin)
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	var sx_fit: float = rect.size.x / aabb.size.x
	var sy_fit: float = rect.size.y / aabb.size.y
	var scale: float = min(sx_fit, sy_fit) * _zoom
	var origin_world: Vector2 = aabb.position + aabb.size * 0.5
	_deck_transform = {
		"floor": floor_id,
		"rect": rect,
		"origin_world": origin_world,
		"scale": scale,
	}


# Project a JSON-space point onto the MapView in pixel space. Returns null
# when there's no active transform (no rooms discovered on this floor yet
# or the requested floor differs from the active one).
func _world_to_px(floor_id: int, world_pt: Vector2) -> Variant:
	if _deck_transform.is_empty():
		return null
	if int(_deck_transform.get("floor", 0)) != floor_id:
		return null
	var rect: Rect2 = _deck_transform["rect"]
	var origin: Vector2 = _deck_transform["origin_world"]
	var scale: float = _deck_transform["scale"]
	var delta: Vector2 = (world_pt - origin) * scale
	return rect.position + rect.size * 0.5 + delta + _pan_offset


# Inverse of _world_to_px for the active floor: given a screen pixel
# (relative to MapView), return the JSON-space world position. Used by
# the right-click "place marker" gesture.
func _screen_to_world(screen_pt: Vector2) -> Variant:
	if _deck_transform.is_empty():
		return null
	var rect: Rect2 = _deck_transform["rect"]
	var origin: Vector2 = _deck_transform["origin_world"]
	var scale: float = _deck_transform["scale"]
	if scale <= 0.0:
		return null
	var delta_px: Vector2 = screen_pt - (rect.position + rect.size * 0.5) - _pan_offset
	return origin + delta_px / scale


# Centre of a room in MapView pixel space, or null if not on a fitted deck.
func _room_to_px(room_id: String) -> Variant:
	var room: Dictionary = ShipLayout.room(room_id)
	if room.is_empty():
		return null
	var floor_id: int = int(room.get("floor", 0))
	var centre: Vector2 = Vector2(
		(float(room["startX"]) + float(room["endX"])) * 0.5,
		(float(room["startY"]) + float(room["endY"])) * 0.5,
	)
	return _world_to_px(floor_id, centre)


# Pixel-space room Rect2 for a given room, or null if not on a fitted deck.
func _room_rect_px(room_id: String) -> Variant:
	var room: Dictionary = ShipLayout.room(room_id)
	if room.is_empty():
		return null
	var floor_id: int = int(room.get("floor", 0))
	var top_left: Variant = _world_to_px(floor_id, Vector2(float(room["startX"]), float(room["startY"])))
	var bot_right: Variant = _world_to_px(floor_id, Vector2(float(room["endX"]), float(room["endY"])))
	if not (top_left is Vector2 and bot_right is Vector2):
		return null
	var tl: Vector2 = top_left
	var br: Vector2 = bot_right
	return Rect2(tl, br - tl)


# Single Control draw callback — owns all the map geometry. `canvas` is
# always `_map_view`; receiving it as a parameter from the needs_geometry
# signal keeps the canvas-item context valid through every draw_* call.
func _on_map_view_draw(canvas: CanvasItem) -> void:
	_compute_deck_transforms()
	if not _deck_transform.is_empty():
		var floor_id: int = int(_deck_transform["floor"])
		var rect: Rect2 = _deck_transform["rect"]
		_draw_deck_geometry(canvas, floor_id, rect)
	# Player marker, quest diamond, placed-marker glyph, dotted route.
	_draw_player_marker(canvas)
	_draw_quest_markers(canvas)
	_draw_placed_marker(canvas)
	_draw_route(canvas)
	# Outer chrome.
	_draw_corner_brackets(canvas, _map_view.size)
	_draw_north_arrow(canvas, _map_view.size)


# Faint blueprint grid inside one room's rect. Pitch = 18px in screen space —
# tight enough to read as a grid even on small room rects.
func _draw_room_grid(canvas: CanvasItem, rect: Rect2) -> void:
	const PITCH: float = 18.0
	const COL: Color = Color(0.35, 0.62, 0.92, 0.18)
	var x: float = rect.position.x + PITCH
	while x < rect.end.x:
		canvas.draw_line(Vector2(x, rect.position.y + 1), Vector2(x, rect.end.y - 1), COL, 1.0)
		x += PITCH
	var y: float = rect.position.y + PITCH
	while y < rect.end.y:
		canvas.draw_line(Vector2(rect.position.x + 1, y), Vector2(rect.end.x - 1, y), COL, 1.0)
		y += PITCH


# Dispatches a room-type glyph at the centre of the room rect. New room types
# can hook in by adding a branch here; everything else falls through to "no
# glyph" (corridors, connectors).
func _draw_room_glyph(canvas: CanvasItem, room: Dictionary, rect: Rect2, is_current: bool) -> void:
	var min_dim: float = min(rect.size.x, rect.size.y)
	if min_dim < 22.0:
		return  # Room too tiny to show a glyph cleanly.
	var centre: Vector2 = rect.position + rect.size * 0.5
	var radius: float = min_dim * 0.28
	var glyph_color: Color = Color(0.70, 0.92, 1.0, 0.85) if is_current else Color(0.55, 0.80, 1.0, 0.55)
	var room_id: String = String(room.get("id", ""))
	var type_id: String = String(room.get("type", room_id))
	# Eli's quarters is HOME because Eli is the player.
	if room_id == "eli_quarters":
		_draw_home_glyph(canvas, centre, radius, glyph_color)
		return
	match type_id:
		"gate_room":
			_draw_stargate_glyph(canvas, centre, radius, glyph_color)
		"control_room":
			_draw_console_glyph(canvas, centre, radius, glyph_color)
		"hydroponics":
			_draw_plant_glyph(canvas, centre, radius, glyph_color)
		"elevator":
			_draw_elevator_glyph(canvas, centre, radius, glyph_color)
		"quarters":
			_draw_home_glyph(canvas, centre, radius, glyph_color)
		_:
			pass  # corridor / connector / unknown → no glyph


# Stargate: outer ring + inner ring + 9 small chevron dots evenly placed
# around the inner ring (real SG has 9, close enough for a glyph).
func _draw_stargate_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	canvas.draw_arc(centre, radius, 0.0, TAU, 48, color, 2.0, true)
	canvas.draw_arc(centre, radius * 0.78, 0.0, TAU, 40, color * Color(1, 1, 1, 0.6), 1.0, true)
	for i in 9:
		var theta: float = float(i) / 9.0 * TAU - PI * 0.5
		var p: Vector2 = centre + Vector2(cos(theta), sin(theta)) * radius * 0.88
		canvas.draw_circle(p, 1.6, color)


# Console tower: chunky rectangle base + cyan screen plate inset on top.
func _draw_console_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var base: Rect2 = Rect2(centre + Vector2(-radius * 0.7, -radius * 0.4), Vector2(radius * 1.4, radius * 1.2))
	canvas.draw_rect(base, color * Color(1, 1, 1, 0.5), true)
	canvas.draw_rect(base, color, false, 1.5)
	var screen: Rect2 = Rect2(base.position + Vector2(radius * 0.18, radius * 0.18), base.size - Vector2(radius * 0.36, radius * 0.7))
	canvas.draw_rect(screen, Color(0.30, 0.85, 1.0, 0.85), true)


# Home: roof triangle + square base. Reads as "your quarters" at a glance.
func _draw_home_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var w: float = radius * 1.1
	var h: float = radius * 0.95
	var base: Rect2 = Rect2(centre + Vector2(-w * 0.5, -h * 0.1), Vector2(w, h * 0.85))
	canvas.draw_rect(base, color * Color(1, 1, 1, 0.5), true)
	canvas.draw_rect(base, color, false, 1.5)
	var roof: PackedVector2Array = PackedVector2Array([
		centre + Vector2(-w * 0.6, -h * 0.1),
		centre + Vector2(0.0, -h * 0.8),
		centre + Vector2(w * 0.6, -h * 0.1),
	])
	canvas.draw_colored_polygon(roof, color)
	# Door slit at the base centre.
	var door_w: float = w * 0.22
	var door_h: float = h * 0.40
	var door: Rect2 = Rect2(centre + Vector2(-door_w * 0.5, h * 0.35), Vector2(door_w, door_h))
	canvas.draw_rect(door, Color(0.02, 0.06, 0.12, 1.0), true)


# Plant: three vertical leaf strokes for hydroponics.
func _draw_plant_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	for i in 3:
		var t: float = float(i) - 1.0  # -1, 0, 1
		var top: Vector2 = centre + Vector2(t * radius * 0.5, -radius * 0.8)
		var bot: Vector2 = centre + Vector2(t * radius * 0.4, radius * 0.6)
		canvas.draw_line(bot, top, color, 2.5)
	# Soil bar at the base.
	canvas.draw_line(centre + Vector2(-radius * 0.6, radius * 0.6), centre + Vector2(radius * 0.6, radius * 0.6), color, 2.0)


# Elevator: stacked up + down chevrons.
func _draw_elevator_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var up: PackedVector2Array = PackedVector2Array([
		centre + Vector2(0.0, -radius * 0.45),
		centre + Vector2(radius * 0.4, -radius * 0.05),
		centre + Vector2(-radius * 0.4, -radius * 0.05),
	])
	var down: PackedVector2Array = PackedVector2Array([
		centre + Vector2(0.0, radius * 0.45),
		centre + Vector2(radius * 0.4, radius * 0.05),
		centre + Vector2(-radius * 0.4, radius * 0.05),
	])
	canvas.draw_colored_polygon(up, color)
	canvas.draw_colored_polygon(down, color)


# Rooms + per-room grid + room glyph + door pips + inter-room connection
# ghosts for the active deck. Drawn in 3 passes so pips and glyphs land on
# top of room fills, and connection lines sit behind pips.
func _draw_deck_geometry(canvas: CanvasItem, floor_id: int, _rect: Rect2) -> void:
	for room_id in GameState.rooms_discovered:
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		_draw_room_outline(canvas, room)
	_draw_connection_lines(canvas, floor_id)
	for room_id in GameState.rooms_discovered:
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		_draw_door_pips_for_room(canvas, room)


func _draw_room_outline(canvas: CanvasItem, room: Dictionary) -> void:
	var room_id: String = String(room["id"])
	var rect_var: Variant = _room_rect_px(room_id)
	if not (rect_var is Rect2):
		return
	var rect: Rect2 = rect_var
	var is_current: bool = (room_id == GameState.current_room_id)
	var outline: Color = ROOM_OUTLINE_CURRENT_COLOR if is_current else ROOM_OUTLINE_COLOR
	canvas.draw_rect(rect, ROOM_FILL_COLOR, true)
	# Faint blueprint grid clipped to this room's interior. Pitch in JSON
	# units (100) projected to pixels so grid spacing stays consistent across
	# rooms regardless of how zoom and AABB-fit scale individual rects.
	_draw_room_grid(canvas, rect)
	canvas.draw_rect(rect, outline, false, (2.5 if is_current else 1.5))
	# Room-type glyph centred in the rect (stargate / console / home / etc.).
	_draw_room_glyph(canvas, room, rect, is_current)
	# Name label — uppercase + multi-line auto-wrap when the room is narrow,
	# matching the concept-art typography. Skip entirely if the rect is too
	# small to fit any text without overlapping pips.
	var name_text: String = String(room.get("name", room_id)).to_upper()
	if rect.size.x < 24.0 or rect.size.y < 18.0:
		return
	var font: Font = ThemeDB.fallback_font
	var fs: int = 11 if is_current else 10
	# Shrink font until the string fits inside the room's inner padding,
	# down to a 7px floor; below that, drop to the first word only.
	var inner_w: float = rect.size.x - 12.0
	var label: String = name_text
	var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs).x
	while text_w > inner_w and fs > 7:
		fs -= 1
		text_w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs).x
	if text_w > inner_w:
		var first_word: String = label.split(" ", false)[0]
		label = first_word
		text_w = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs).x
		if text_w > inner_w:
			return  # Even the first word won't fit — leave the rect unlabeled.
	var centre: Vector2 = rect.position + rect.size * 0.5
	var text_pos: Vector2 = centre + Vector2(-text_w * 0.5, fs * 0.35)
	var text_color: Color = Color(0.95, 0.98, 1.0, 1.0) if is_current else Color(0.78, 0.88, 0.96, 0.9)
	canvas.draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs, text_color)


# Thin connecting ghost-line between two discovered rooms that share an edge.
# Helps the player see topology before they walk through the door.
func _draw_connection_lines(canvas: CanvasItem, floor_id: int) -> void:
	var seen: Dictionary = {}
	for room_id in GameState.rooms_discovered:
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		for edge in ShipLayout.outgoing_edges(room_id):
			var e: Dictionary = edge
			var to_id: String = String(e.get("to", ""))
			if to_id == "" or not GameState.rooms_discovered.has(to_id):
				continue
			var key: String = GameState.door_key(room_id, to_id)
			if seen.has(key):
				continue
			seen[key] = true
			var to_room: Dictionary = ShipLayout.room(to_id)
			if to_room.is_empty() or int(to_room.get("floor", 0)) != floor_id:
				continue
			var a: Variant = _room_to_px(room_id)
			var b: Variant = _room_to_px(to_id)
			if a is Vector2 and b is Vector2:
				canvas.draw_line(a, b, CONNECTION_LINE_COLOR, 1.0)


# Door pips for one room — auto-spaced along each wall when multiple pips
# share the same direction (e.g. north_corridor has two +x exits).
func _draw_door_pips_for_room(canvas: CanvasItem, room: Dictionary) -> void:
	var room_id: String = String(room["id"])
	var rect_var: Variant = _room_rect_px(room_id)
	if not (rect_var is Rect2):
		return
	var rect: Rect2 = rect_var
	# Group outgoing edges by direction so we can stagger them along the wall.
	var by_dir: Dictionary = {}
	for edge in ShipLayout.outgoing_edges(room_id):
		var e: Dictionary = edge
		var dir: String = String(e.get("dir", ""))
		if dir == "":
			continue
		if not by_dir.has(dir):
			by_dir[dir] = []
		(by_dir[dir] as Array).append(e)
	for dir in by_dir.keys():
		var edges: Array = by_dir[dir]
		for i in range(edges.size()):
			# Distribute pips along the wall as (i+1)/(N+1), so 1 pip lands
			# at 0.5, 2 pips at 0.33/0.67, 3 at 0.25/0.50/0.75, etc.
			var t: float = float(i + 1) / float(edges.size() + 1)
			var pip_centre: Vector2 = _wall_position(rect, String(dir), t)
			var pip_axis: Vector2 = _wall_axis(String(dir))
			var to_id: String = String((edges[i] as Dictionary).get("to", ""))
			var state: String = _pip_state(room_id, to_id, String(dir))
			_draw_door_pip(canvas, pip_centre, pip_axis, state)


# Pip state machine. Order matters: hard-lock > kino-lock > power-lock >
# traversed > open.
func _pip_state(source_id: String, target_id: String, dir: String) -> String:
	var target_room: Dictionary = ShipLayout.room(target_id)
	if not target_room.is_empty() and bool(target_room.get("locked", false)):
		return "hardlock"
	if dir == "elevator" and not GameState.elevator_repaired:
		return "lock"
	if GameState.door_was_traversed(source_id, target_id):
		return "traversed"
	return "open"


# Pixel position on the wall of a deck-projected room rect.
# `dir` is one of "+x","-x","+z","-z","elevator". `t ∈ [0,1]` slides the pip
# along the wall (0 = top/left edge, 1 = bottom/right). Elevator pips sit at
# the room centre with a stacked-chevron glyph.
func _wall_position(rect: Rect2, dir: String, t: float) -> Vector2:
	match dir:
		"-x":
			return Vector2(rect.position.x, rect.position.y + rect.size.y * t)
		"+x":
			return Vector2(rect.end.x, rect.position.y + rect.size.y * t)
		"-z":
			return Vector2(rect.position.x + rect.size.x * t, rect.position.y)
		"+z":
			return Vector2(rect.position.x + rect.size.x * t, rect.end.y)
		_:
			return rect.position + rect.size * 0.5


# Direction vector along the wall — perpendicular to the pip's protrusion.
# Used for orienting the pip's long axis.
func _wall_axis(dir: String) -> Vector2:
	match dir:
		"-x", "+x":
			return Vector2(0.0, 1.0)
		"-z", "+z":
			return Vector2(1.0, 0.0)
		_:
			return Vector2(1.0, 0.0)


# Render a single door pip. `centre` is on the room boundary; `axis` is the
# along-wall direction. State determines fill/outline.
func _draw_door_pip(canvas: CanvasItem, centre: Vector2, axis: Vector2, state: String) -> void:
	var perp: Vector2 = Vector2(-axis.y, axis.x)  # 90° rotation
	var half_len: float = PIP_LENGTH * 0.5
	var half_dep: float = PIP_DEPTH * 0.5
	# Pip straddles the wall so it reads as part of it.
	var poly: PackedVector2Array = PackedVector2Array([
		centre - axis * half_len - perp * half_dep,
		centre + axis * half_len - perp * half_dep,
		centre + axis * half_len + perp * half_dep,
		centre - axis * half_len + perp * half_dep,
	])
	match state:
		"open":
			canvas.draw_colored_polygon(poly, PIP_OPEN_COLOR)
		"traversed":
			canvas.draw_polyline(_close_poly(poly), PIP_TRAVERSED_COLOR, 1.0)
		"lock":
			canvas.draw_colored_polygon(poly, PIP_LOCKED_COLOR)
			canvas.draw_circle(centre, 1.5, Color(0.10, 0.05, 0.0, 1.0))
		"hardlock":
			canvas.draw_colored_polygon(poly, PIP_HARDLOCK_COLOR)
			# Small × glyph.
			canvas.draw_line(centre + Vector2(-2, -2), centre + Vector2(2, 2), Color.WHITE, 1.0)
			canvas.draw_line(centre + Vector2(-2, 2), centre + Vector2(2, -2), Color.WHITE, 1.0)


func _close_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p in poly:
		out.append(p)
	if poly.size() > 0:
		out.append(poly[0])
	return out


func _draw_player_marker(canvas: CanvasItem) -> void:
	var px_var: Variant = _room_to_px(GameState.current_room_id)
	if not (px_var is Vector2):
		return
	var px: Vector2 = px_var
	canvas.draw_circle(px, 7.0, Color(PLAYER_MARKER_COLOR.r, PLAYER_MARKER_COLOR.g, PLAYER_MARKER_COLOR.b, 0.35))
	canvas.draw_circle(px, 4.0, PLAYER_MARKER_COLOR)


func _draw_quest_markers(canvas: CanvasItem) -> void:
	var quest: Dictionary = GameState.quest_target()
	var quest_room: String = String(quest.get("room", ""))
	if quest_room != "":
		var qpx_var: Variant = _room_to_px(quest_room)
		if qpx_var is Vector2:
			_draw_diamond(canvas, qpx_var, 7.0, QUEST_TARGET_COLOR)


func _draw_route(canvas: CanvasItem) -> void:
	var target_id: String = _active_route_target()
	if target_id == "":
		return
	var path: PackedStringArray = ShipLayout.path_through_rooms(GameState.current_room_id, target_id)
	var dot_color: Color = CUSTOM_TARGET_COLOR if _placed_marker != null else QUEST_TARGET_COLOR
	for i in range(path.size() - 1):
		var a_var: Variant = _room_to_px(path[i])
		var b_var: Variant = _room_to_px(path[i + 1])
		if not (a_var is Vector2 and b_var is Vector2):
			continue
		_draw_dotted_segment(canvas, a_var, b_var, dot_color)


# Bracket-style chrome at the four corners of the MapView. Sets the
# "HUD frame around a tactical display" feel from the concept art.
func _draw_corner_brackets(canvas: CanvasItem, size: Vector2) -> void:
	const LEN: float = 22.0
	const W: float = 2.0
	var color: Color = Color(0.55, 0.85, 1.0, 0.85)
	canvas.draw_line(Vector2(0, 0), Vector2(LEN, 0), color, W)
	canvas.draw_line(Vector2(0, 0), Vector2(0, LEN), color, W)
	canvas.draw_line(Vector2(size.x - LEN, 0), Vector2(size.x, 0), color, W)
	canvas.draw_line(Vector2(size.x, 0), Vector2(size.x, LEN), color, W)
	canvas.draw_line(Vector2(0, size.y), Vector2(LEN, size.y), color, W)
	canvas.draw_line(Vector2(0, size.y - LEN), Vector2(0, size.y), color, W)
	canvas.draw_line(Vector2(size.x - LEN, size.y), Vector2(size.x, size.y), color, W)
	canvas.draw_line(Vector2(size.x, size.y - LEN), Vector2(size.x, size.y), color, W)


# Simple compass — "N" letter + upward triangle in the bottom-right corner.
func _draw_north_arrow(canvas: CanvasItem, size: Vector2) -> void:
	var origin: Vector2 = Vector2(size.x - 30.0, size.y - 30.0)
	var color: Color = Color(0.55, 0.85, 1.0, 0.85)
	var tri: PackedVector2Array = PackedVector2Array([
		origin + Vector2(0.0, -10.0),
		origin + Vector2(6.0, 4.0),
		origin + Vector2(-6.0, 4.0),
	])
	canvas.draw_colored_polygon(tri, color)
	var font: Font = ThemeDB.fallback_font
	canvas.draw_string(font, origin + Vector2(-4.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)


func _draw_diamond(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		centre + Vector2(0.0, -radius),
		centre + Vector2(radius, 0.0),
		centre + Vector2(0.0, radius),
		centre + Vector2(-radius, 0.0),
	])
	canvas.draw_colored_polygon(pts, color)


func _draw_dotted_segment(canvas: CanvasItem, a: Vector2, b: Vector2, color: Color) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.5:
		return
	var dir: Vector2 = (b - a) / dist
	var steps: int = int(floor(dist / ROUTE_DOT_SPACING))
	for s in range(steps + 1):
		var p: Vector2 = a + dir * float(s) * ROUTE_DOT_SPACING
		canvas.draw_circle(p, ROUTE_DOT_RADIUS, color)


# Map input: left-drag pans, mouse wheel zooms toward the cursor, right-click
# drops a route marker at the world-space point under the cursor (clearing it
# if it's already on the same spot).
func _on_map_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _is_panning:
		var mm: InputEventMouseMotion = event
		var delta: Vector2 = mm.position - _pan_last_mouse
		_pan_offset += delta
		_pan_last_mouse = mm.position
		_map_view.queue_redraw()


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_panning = true
				_pan_last_mouse = mb.position
			else:
				_is_panning = false
		MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_place_marker_at(mb.position)
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom_at(mb.position, 1.15)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_at(mb.position, 1.0 / 1.15)


# Wheel zoom: scale around the cursor so the point under the mouse stays put
# (standard map-tool behaviour). Implemented by adjusting pan to absorb the
# pre/post screen-position delta for that world point.
func _zoom_at(screen_pt: Vector2, factor: float) -> void:
	var pre_world_var: Variant = _screen_to_world(screen_pt)
	var new_zoom: float = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, _zoom):
		return
	_zoom = new_zoom
	if _zoom_slider != null:
		_zoom_slider.set_block_signals(true)
		_zoom_slider.value = _zoom
		_zoom_slider.set_block_signals(false)
	if pre_world_var is Vector2:
		# Recompute the transform at the new zoom, then nudge pan so the
		# cursor's world point lands back under the cursor.
		_compute_deck_transforms()
		var post_pt_var: Variant = _world_to_px(_active_floor(), pre_world_var)
		if post_pt_var is Vector2:
			_pan_offset += screen_pt - post_pt_var
	if _map_view != null:
		_map_view.queue_redraw()


# Right-click drop-pin: store {floor, world_pos} so the marker persists
# across pan + zoom. Clicking again on (within ~12px of) the existing
# marker clears it.
func _place_marker_at(screen_pt: Vector2) -> void:
	var world_var: Variant = _screen_to_world(screen_pt)
	if not (world_var is Vector2):
		return
	var floor_id: int = _active_floor()
	if _placed_marker != null:
		var m: Dictionary = _placed_marker
		if int(m.get("floor", 0)) == floor_id:
			var existing_px_var: Variant = _world_to_px(floor_id, m["world"])
			if existing_px_var is Vector2 and (existing_px_var as Vector2).distance_to(screen_pt) < 14.0:
				_placed_marker = null
				_map_view.queue_redraw()
				return
	_placed_marker = {"floor": floor_id, "world": world_var}
	if _map_view != null:
		_map_view.queue_redraw()


# Map-pin glyph at the placed marker. Drawn on top of rooms but under
# corner-bracket chrome.
func _draw_placed_marker(canvas: CanvasItem) -> void:
	if _placed_marker == null:
		return
	var m: Dictionary = _placed_marker
	var floor_id: int = int(m.get("floor", 0))
	if floor_id != _active_floor():
		return
	var px_var: Variant = _world_to_px(floor_id, m["world"])
	if not (px_var is Vector2):
		return
	var px: Vector2 = px_var
	# Teardrop pin — circle head + triangle stem pointing down.
	var head: Vector2 = px + Vector2(0.0, -10.0)
	canvas.draw_circle(head, 6.0, CUSTOM_TARGET_COLOR)
	canvas.draw_circle(head, 2.5, Color(0.04, 0.06, 0.12, 1.0))
	var stem: PackedVector2Array = PackedVector2Array([
		head + Vector2(-5.0, 4.0),
		head + Vector2(5.0, 4.0),
		px,
	])
	canvas.draw_colored_polygon(stem, CUSTOM_TARGET_COLOR)


# Resolve the placed marker (if any) to a room on the active floor so the
# BFS route can target it. Returns "" if no marker, or if the marker doesn't
# land inside any discovered room.
func _placed_marker_room() -> String:
	if _placed_marker == null:
		return ""
	var m: Dictionary = _placed_marker
	var world: Vector2 = m["world"]
	var floor_id: int = int(m.get("floor", 0))
	for room_id in GameState.rooms_discovered:
		var r: Dictionary = ShipLayout.room(room_id)
		if r.is_empty() or int(r.get("floor", 0)) != floor_id:
			continue
		var rect_world: Rect2 = Rect2(
			Vector2(float(r["startX"]), float(r["startY"])),
			Vector2(float(r["endX"]) - float(r["startX"]), float(r["endY"]) - float(r["startY"])),
		)
		if rect_world.has_point(world):
			return room_id
	return ""

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
