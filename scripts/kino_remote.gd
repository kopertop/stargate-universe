extends Node

# @no-save: UI overlay only. The persisted state it cares about (pan,
# zoom, active floor, placed marker) is mirrored to GameState fields
# (kino_pan_x/y, kino_zoom, kino_active_floor, kino_marker) which DO
# ride along in the save snapshot via game_state's serialize().
#
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
const PAGE_SHIP_SYSTEMS: int = 5
const PAGE_KINO_CONTROL: int = 6
# Short labels rendered on the nav buttons (Ancient operator typically
# reads these in an unknown alphabet — for now plain ASCII). Indexed by PAGE_*.
const PAGE_LABELS: PackedStringArray = ["MAP", "STATUS", "QUEST", "LOG", "INV", "SYSTEMS", "KINO"]

# Per-surface menus. The handheld Kino is the player's personal device (map +
# personal stats/quest/log/inventory). A wall-mounted control terminal is the
# SHIP's interface — it shares the map but swaps the personal pages for ship
# systems, and never exposes inventory/personal stats. Adding a new console
# variant later is just a new page-set constant.
const HANDHELD_PAGES: Array[int] = [PAGE_MAP, PAGE_STATUS, PAGE_QUEST, PAGE_LOG, PAGE_INVENTORY, PAGE_KINO_CONTROL]
const CONSOLE_PAGES: Array[int] = [PAGE_MAP, PAGE_SHIP_SYSTEMS]
const HANDHELD_TITLE: String = "KINO REMOTE — ANCIENT INTERFACE"
const CONSOLE_TITLE: String = "DESTINY CONTROL TERMINAL"

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
# Quest-target room — amber alert outline + warmer fill so the player can
# see at a glance WHICH room the current objective is in (e.g. the jammed
# door the control terminal just flagged).
const ROOM_OUTLINE_TARGET_COLOR: Color = Color(1.0, 0.62, 0.25, 1.0)
const ROOM_FILL_TARGET_COLOR: Color = Color(1.0, 0.45, 0.18, 0.16)
# Breach-beat colours: hot alarm red for the trap door + flooded rooms, and a
# red↔grey pulse for the jammed (half-open) door that's the real objective.
const BREACH_RED: Color = Color(1.0, 0.13, 0.10)
const BREACH_JAMMED_GREY: Color = Color(0.55, 0.56, 0.60)
const BREACH_DOOR_CLICK_RADIUS: float = 46.0
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
var _header_label: Label = null
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
# True when the panel was opened from a wall-mounted control terminal (vs the
# handheld Kino on Tab). The console has the ship's own schematic, so it
# shows EVERY room on the active floor; the handheld keeps fog-of-war and
# only shows discovered rooms. Reset on close.
var _console_mode: bool = false

# --- Blocked-door beat -------------------------------------------------------
# A scripted, map-driven sequence run from the control terminal: Scott flags a
# sealed door (pulsing red on the map); the player clicks it to OPEN (connected
# rooms flood red, Scott panics); clicks again to CLOSE; then a different room
# pulses red↔grey to reveal the jammed half-open door that's the real seal
# objective. Phases: 0 = sealed (clickable), 1 = open/flooding (clickable),
# 2 = resolved (jammed room revealed, no longer clickable).
var _breach_active: bool = false
var _breach_phase: int = 0
var _breach_time: float = 0.0
var _breach_trap_from: String = ""
var _breach_trap_to: String = ""
var _breach_jammed_room: String = ""
var _breach_flood_rooms: Array = []
var _breach_klaxon_timer: Timer = null

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

	_header_label = Label.new()
	_header_label.text = HANDHELD_TITLE
	_header_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1))
	_header_label.add_theme_font_size_override("font_size", 20)
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_header_label)

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
	_build_ship_systems_page(page_stack)
	_build_kino_control_page(page_stack)

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

# Console-only page: ship-level systems (power / O2 / hull) and a life-support
# diagnostics block. Distinct from the personal STATUS page (Eli's vitals) — a
# control terminal reads the ship, not the crewman holding it.
func _build_ship_systems_page(parent: Control) -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "ShipSystems"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	_pages.append(page)
	_label(page, "SHIP SYSTEMS", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(page, "  Main power:  —", 14, Color.WHITE).name = "SysPower"
	_label(page, "  Atmosphere O2:  —", 14, Color.WHITE).name = "SysOxygen"
	_label(page, "  Hull integrity:  —", 14, Color.WHITE).name = "SysHull"
	page.add_child(HSeparator.new())
	_label(page, "LIFE SUPPORT", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(page, "  Exposed section:  —", 14, Color.WHITE).name = "SysBreach"
	_label(page, "  CO2 scrubber:  —", 14, Color.WHITE).name = "SysScrubber"


# Handheld Kino fleet control. Available once you hold an orb or have a Kino
# deployed in the field (see _page_available). Lets you launch a new Kino and
# take control of ANY live Kino at any time — including ones left on the planet.
# The action list is rebuilt each refresh since the deployed set changes.
func _build_kino_control_page(parent: Control) -> void:
	var page: VBoxContainer = VBoxContainer.new()
	page.name = "KinoControl"
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.add_theme_constant_override("separation", 12)
	parent.add_child(page)
	_pages.append(page)
	_label(page, "KINO CONTROL", 16, Color(0.55, 0.85, 1.0, 1.0))
	var desc: Label = _label(page, "—", 14, Color(0.85, 0.92, 1.0, 0.95))
	desc.name = "KinoControlDesc"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(HSeparator.new())
	_label(page, "  Kinos in hand:  —", 14, Color.WHITE).name = "KinoControlCount"
	var list: VBoxContainer = VBoxContainer.new()
	list.name = "KinoActionList"
	list.add_theme_constant_override("separation", 8)
	page.add_child(list)


func _kino_action_button(text: String, primary: bool) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", _button_stylebox(primary))
	b.add_theme_stylebox_override("hover", _button_stylebox_hover())
	b.add_theme_stylebox_override("pressed", _button_stylebox(true))
	return b


# Friendly label for a deployed Kino's scene path.
func _scene_short_name(scene_path: String) -> String:
	if scene_path.ends_with("planet.tscn"):
		return "Planet"
	if scene_path.ends_with("gate_room.tscn"):
		return "Gate Room"
	if scene_path.ends_with("room.tscn"):
		return "Ship"
	return scene_path.get_file().get_basename().capitalize()


func _on_page_button(idx: int) -> void:
	Audio.play("res://sounds/menu_click.ogg")
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
	if event.is_action_pressed("kino_remote"):
		# Tab always CLOSES an open surface — including a console-opened map the
		# player can't reopen yet (no handheld Kino). Only OPENING via Tab is
		# gated on kino_acquired, so a diegetic console map isn't a soft-lock.
		if _open:
			_close()
			get_viewport().set_input_as_handled()
		elif GameState.kino_acquired:
			# Tab = handheld Kino: fog-of-war, only discovered rooms.
			_console_mode = false
			_open_remote()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and _open:
		_close()
		get_viewport().set_input_as_handled()

# Public open API for external callers (control_console.gd). The Tab-key
# path keeps the kino_acquired gate; this entrypoint lets diegetic in-world
# consoles open
# the same surface even before the player has picked up the handheld remote,
# since the menu represents the console's interface in that case rather than
# the player's pocket prop.
func open_remote(force: bool = false, console_mode: bool = false) -> void:
	if not force and not GameState.kino_acquired:
		return
	_console_mode = console_mode
	_open_remote()


func _open_remote() -> void:
	if not _initialized:
		_init_ui()
	_load_persisted_ui_state()
	_open = true
	_root.visible = true
	_apply_surface()
	_refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	Audio.play("res://sounds/menu_open.ogg")


# Configure the menu for the active surface: the handheld Kino (personal device)
# vs a wall-mounted control terminal (ship interface). Sets the title, shows
# only that surface's nav buttons, and lands on a valid page. Driven by
# _console_mode, which open_remote() set from its console_mode argument.
func _apply_surface() -> void:
	var pages: Array[int] = CONSOLE_PAGES if _console_mode else HANDHELD_PAGES
	if _header_label != null:
		_header_label.text = CONSOLE_TITLE if _console_mode else HANDHELD_TITLE
	for i in range(_buttons.size()):
		_buttons[i].visible = pages.has(i) and _page_available(i)
	# Keep the current page if it belongs to this surface AND is available;
	# otherwise fall back to the surface's first page (MAP today).
	var landing: int = _active_page if (pages.has(_active_page) and _page_available(_active_page)) else pages[0]
	_select_page(landing)


# Conditional page gating on top of the per-surface page list. Most pages are
# always available; the Kino Control page appears as soon as you have a Kino to
# work with — an orb in hand to launch, OR a live Kino deployed in the field
# (which you can re-take control of at any time, from any scene).
func _page_available(page: int) -> bool:
	if page == PAGE_KINO_CONTROL:
		return GameState.kino_orbs > 0 or not GameState.deployed_kinos.is_empty()
	return true

# Public close — mirrors open_remote() so external callers (control_console.gd,
# playthrough_runner.gd) can dismiss the menu without reaching into the private
# _close() path.
func close_remote() -> void:
	if _open:
		_close()


func _close() -> void:
	_open = false
	_console_mode = false
	# Tear down any in-progress breach beat so it doesn't linger / keep the
	# klaxon looping after the panel closes.
	if _breach_active:
		_breach_active = false
		_stop_breach_klaxon()
		_clear_breach_caption()
	_persist_ui_state()
	if _root != null:
		_root.visible = false
	get_tree().paused = false
	Audio.play("res://sounds/menu_close.ogg")
	# Reset mouselook through view.gd — closing the Kino doesn't restore
	# Input.mouse_mode on its own, so RMB-held-during-open leaves the cursor
	# visible until the next RMB tap.
	GameState.kino_closed.emit()


# Mirror current UI state into GameState so it rides along in the next
# autosave. Called from _close() and from the marker placement path so a
# dropped pin survives a sudden quit followed by Continue.
func _persist_ui_state() -> void:
	GameState.kino_pan_x = _pan_offset.x
	GameState.kino_pan_y = _pan_offset.y
	GameState.kino_zoom = _zoom
	GameState.kino_active_floor = _active_floor_override
	if _placed_marker is Dictionary:
		var m: Dictionary = _placed_marker
		var world: Variant = m.get("world", null)
		if world is Vector2:
			GameState.kino_marker = {
				"floor": int(m.get("floor", 0)),
				"world_x": (world as Vector2).x,
				"world_y": (world as Vector2).y,
			}
		else:
			GameState.kino_marker = {}
	else:
		GameState.kino_marker = {}


# Read GameState fields into our locals. Called from _open_remote so the
# user sees the same pan / zoom / marker they left the previous session
# on. Defaults are safe if GameState carries the initial values.
func _load_persisted_ui_state() -> void:
	_pan_offset = Vector2(GameState.kino_pan_x, GameState.kino_pan_y)
	_zoom = GameState.kino_zoom if GameState.kino_zoom > 0.0 else ZOOM_DEFAULT
	_active_floor_override = GameState.kino_active_floor
	var raw: Variant = GameState.kino_marker
	if raw is Dictionary and (raw as Dictionary).has("world_x"):
		var d: Dictionary = raw
		_placed_marker = {
			"floor": int(d.get("floor", 0)),
			"world": Vector2(float(d.get("world_x", 0.0)), float(d.get("world_y", 0.0))),
		}
	else:
		_placed_marker = null

func _refresh() -> void:
	_refresh_map()
	_refresh_status()
	_refresh_quest()
	_refresh_log()
	_refresh_inventory()
	_refresh_ship_systems()
	_refresh_kino_control()

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
	_level_bar.visible = false  # User: "hidden for now, we'll have other levels later".
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


# Room IDs the map should render. Handheld Kino → fog-of-war (only
# discovered). Console mode → every room on the active floor (the ship's
# own schematic). Returned as a plain Array of id strings.
func _visible_room_ids() -> Array:
	if not _console_mode:
		return GameState.rooms_discovered
	var ids: Array = []
	var floor_id: int = _active_floor()
	for r in ShipLayout.all_rooms():
		if int(r.get("floor", 0)) == floor_id:
			ids.append(String(r.get("id", "")))
	return ids


func _is_room_visible(room_id: String) -> bool:
	if not _console_mode:
		return GameState.rooms_discovered.has(room_id)
	var r: Dictionary = ShipLayout.room(room_id)
	return not r.is_empty() and int(r.get("floor", 0)) == _active_floor()


# Compute ONE transform for the active floor, filling the entire MapView
# rect. AABB is taken over visible rooms on that floor only, so the
# fit auto-tightens as the player explores (or covers the whole floor in
# console mode). `_pan_offset` and `_zoom` layer on top so click-drag +
# wheel-zoom move the visible window.
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
	for room_id in _visible_room_ids():
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
	# Blocked-door beat overlay (pulsing trap door, flooded rooms, jammed room).
	_draw_breach_overlay(canvas)
	# Outer chrome.
	_draw_corner_brackets(canvas, _map_view.size)
	_draw_north_arrow(canvas, _map_view.size)


# Drives the breach-beat pulse animation. Only ticks while the beat is live;
# kino_remote runs PROCESS_MODE_ALWAYS so this animates under the paused map.
func _process(delta: float) -> void:
	if _breach_active:
		_breach_time += delta
		if _map_view != null:
			_map_view.queue_redraw()


# Entry point for the control-terminal blocked-door beat. trap_from/trap_to
# name the sealed door (its on-map midpoint becomes the click target);
# flood_rooms pulse red while it's open; jammed_room pulses red↔grey once it's
# shut, revealing the real objective.
func begin_breach_beat(trap_from: String, trap_to: String, jammed_room: String, flood_rooms: Array) -> void:
	_breach_active = true
	_breach_phase = 0
	_breach_time = 0.0
	_breach_trap_from = trap_from
	_breach_trap_to = trap_to
	_breach_jammed_room = jammed_room
	_breach_flood_rooms = flood_rooms
	Audio.play("res://sounds/radio_click.ogg")
	# Caption rendered on the map panel (dialogue_shown would be hidden behind
	# the full-screen map). add_log keeps it in the journal too.
	_set_breach_caption("Lt Scott [radio]: Eli — we found a sealed door. Can you open it from there?")
	GameState.add_log("Lt Scott (radio): We found a sealed door — can you open it from there?")
	if _map_view != null:
		_map_view.queue_redraw()


# Screen-space midpoint of the trap door (between its two rooms' centres). The
# click target is a generous radius around this point.
func _breach_door_px() -> Variant:
	var a: Variant = _room_to_px(_breach_trap_from)
	var b: Variant = _room_to_px(_breach_trap_to)
	if a is Vector2 and b is Vector2:
		return ((a as Vector2) + (b as Vector2)) * 0.5
	return null


func _is_click_on_breach_door(pos: Vector2) -> bool:
	var dp: Variant = _breach_door_px()
	return dp is Vector2 and pos.distance_to(dp) <= BREACH_DOOR_CLICK_RADIUS


# Click handler: phase 0 → open (flood + panic), phase 1 → close (reveal jammed).
func _advance_breach() -> void:
	if _breach_phase == 0:
		_breach_phase = 1
		_start_breach_klaxon()
		Audio.play("res://sounds/radio_click.ogg")
		_set_breach_caption("Lt Scott [radio]: —! CLOSE IT! CLOSE IT, ELI, CLOSE IT!")
		GameState.add_log("Lt Scott (radio): CLOSE IT! CLOSE IT!")
	elif _breach_phase == 1:
		_breach_phase = 2
		_stop_breach_klaxon()
		Audio.play("res://sounds/radio_off.ogg")
		_set_breach_caption("Lt Scott [radio]: …okay. That section's a furnace — leave it. But look, south of you — that door's only half shut. It's jammed. THAT's venting our air. Get down there and force it closed.")
		GameState.add_log("Lt Scott (radio): Jammed door, half-open, in the Damaged Section to the south. Force it shut.")
		GameState.blocked_door_beat_done = true
	if _map_view != null:
		_map_view.queue_redraw()


func _start_breach_klaxon() -> void:
	if _breach_klaxon_timer == null:
		_breach_klaxon_timer = Timer.new()
		_breach_klaxon_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_breach_klaxon_timer.wait_time = 0.85
		_breach_klaxon_timer.timeout.connect(_emit_breach_klaxon)
		add_child(_breach_klaxon_timer)
	_emit_breach_klaxon()
	_breach_klaxon_timer.start()


# Dedicated loud player — the shared Audio pool clamps at -10 dB, too quiet
# for an alarm meant to convey panic. Stream is preloaded (not load() per
# tick) since this fires every 0.85 s while the klaxon timer runs.
const BREACH_KLAXON_STREAM: AudioStream = preload("res://sounds/klaxon.ogg")

func _emit_breach_klaxon() -> void:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = BREACH_KLAXON_STREAM
	p.bus = "SFX"
	p.volume_db = 6.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func _stop_breach_klaxon() -> void:
	if _breach_klaxon_timer != null:
		_breach_klaxon_timer.stop()


# Scott's breach lines render as a caption on the map panel itself —
# dialogue_shown would draw behind the full-screen map and never be seen.
func _set_breach_caption(text: String) -> void:
	if _root == null:
		return
	var label: Label = _root.get_node_or_null("BreachCaption") as Label
	if label == null:
		label = Label.new()
		label.name = "BreachCaption"
		label.anchor_left = 0.0
		label.anchor_right = 1.0
		label.offset_left = 150
		label.offset_right = -150
		label.offset_top = 150
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.78))
		label.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.0))
		label.add_theme_constant_override("outline_size", 6)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(label)
	label.text = text


func _clear_breach_caption() -> void:
	if _root == null:
		return
	var label: Node = _root.get_node_or_null("BreachCaption")
	if label != null:
		label.queue_free()


func _draw_breach_overlay(canvas: CanvasItem) -> void:
	if not _breach_active:
		return
	var pulse: float = 0.5 + 0.5 * sin(_breach_time * 6.0)
	# Phase 1: connected rooms flood red.
	if _breach_phase == 1:
		for rid in _breach_flood_rooms:
			var rr: Variant = _room_rect_px(rid)
			if rr is Rect2:
				var fill: Color = BREACH_RED
				fill.a = 0.22 + 0.40 * pulse
				canvas.draw_rect(rr, fill, true)
				canvas.draw_rect(rr, Color(1.0, 0.35, 0.25, 0.95), false, 2.5)
	# Phase 2: jammed room pulses red↔grey — "half shut, jammed".
	if _breach_phase == 2:
		var jr: Variant = _room_rect_px(_breach_jammed_room)
		if jr is Rect2:
			var jfill: Color = BREACH_RED.lerp(BREACH_JAMMED_GREY, pulse)
			jfill.a = 0.38
			canvas.draw_rect(jr, jfill, true)
			var jline: Color = Color(1.0, 0.35, 0.25, 0.95).lerp(Color(0.65, 0.66, 0.70, 0.9), pulse)
			canvas.draw_rect(jr, jline, false, 3.0)
	# Trap door marker — pulsing red ring at the door midpoint (phases 0+1).
	if _breach_phase <= 1:
		var dp: Variant = _breach_door_px()
		if dp is Vector2:
			var p: Vector2 = dp
			var radius: float = 9.0 + 6.0 * pulse
			canvas.draw_circle(p, radius, Color(1.0, 0.15, 0.12, 0.45 + 0.45 * pulse))
			canvas.draw_arc(p, radius + 5.0, 0.0, TAU, 28, Color(1.0, 0.45, 0.3, 0.95), 2.0)


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


# Console room layout: central octagonal pillar with four console panels
# arranged N/E/S/W around it. Matches the SGU control-room concept art.
# `radius` is the local scale set by the room rect; we re-derive sizes from
# that so the glyph stays proportional across narrow corridors and big
# rooms alike.
func _draw_console_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var console_long: float = radius * 1.05
	var console_short: float = radius * 0.45
	var arm: float = radius * 1.05  # distance from centre to each console centre
	# North & south consoles: long axis runs horizontally.
	_draw_console_panel(canvas, centre + Vector2(0.0, -arm), console_long, console_short, color)
	_draw_console_panel(canvas, centre + Vector2(0.0,  arm), console_long, console_short, color)
	# East & west consoles: long axis runs vertically.
	_draw_console_panel(canvas, centre + Vector2(-arm, 0.0), console_short, console_long, color)
	_draw_console_panel(canvas, centre + Vector2( arm, 0.0), console_short, console_long, color)
	# Central octagonal pillar.
	_draw_octagon(canvas, centre, radius * 0.32, color)


# Single console panel — outlined rect with a small cyan "screen" patch
# centred inside it. Used by the control-room cluster glyph and any future
# console-equipped rooms.
func _draw_console_panel(canvas: CanvasItem, centre: Vector2, w: float, h: float, color: Color) -> void:
	var body: Rect2 = Rect2(centre - Vector2(w, h) * 0.5, Vector2(w, h))
	canvas.draw_rect(body, color * Color(1, 1, 1, 0.4), true)
	canvas.draw_rect(body, color, false, 1.0)
	var screen: Rect2 = body.grow_individual(-w * 0.18, -h * 0.18, -w * 0.18, -h * 0.45)
	canvas.draw_rect(screen, Color(0.30, 0.85, 1.0, 0.85), true)


# Regular octagon centred at `centre` with circumradius `radius`. Flat-side-
# up orientation (vertex 0 sits at angle π/8).
func _draw_octagon(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 8:
		var theta: float = (float(i) + 0.5) / 8.0 * TAU
		pts.append(centre + Vector2(cos(theta), sin(theta)) * radius)
	# Close the loop so draw_polyline renders the last edge too.
	pts.append(pts[0])
	canvas.draw_polyline(pts, color, 1.5)


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
	for room_id in _visible_room_ids():
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		_draw_room_outline(canvas, room)
	_draw_connection_lines(canvas, floor_id)
	for room_id in _visible_room_ids():
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		_draw_door_pips_for_room(canvas, room)


# True when this room holds the active quest target — drives the amber
# alert highlight so the problem room (jammed door, scrubber, etc.) stands
# out from ordinary discovered rooms.
func _is_quest_target_room(room_id: String) -> bool:
	var q: Dictionary = GameState.quest_target()
	return String(q.get("room", "")) == room_id


func _draw_room_outline(canvas: CanvasItem, room: Dictionary) -> void:
	var room_id: String = String(room["id"])
	var rect_var: Variant = _room_rect_px(room_id)
	if not (rect_var is Rect2):
		return
	var rect: Rect2 = rect_var
	var is_current: bool = (room_id == GameState.current_room_id)
	var is_target: bool = _is_quest_target_room(room_id)
	var outline: Color = ROOM_OUTLINE_COLOR
	var fill: Color = ROOM_FILL_COLOR
	if is_current:
		outline = ROOM_OUTLINE_CURRENT_COLOR
	elif is_target:
		outline = ROOM_OUTLINE_TARGET_COLOR
		fill = ROOM_FILL_TARGET_COLOR
	canvas.draw_rect(rect, fill, true)
	# Faint blueprint grid clipped to this room's interior. Pitch in JSON
	# units (100) projected to pixels so grid spacing stays consistent across
	# rooms regardless of how zoom and AABB-fit scale individual rects.
	_draw_room_grid(canvas, rect)
	canvas.draw_rect(rect, outline, false, (2.5 if (is_current or is_target) else 1.5))
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
	# Control rooms put a central octagonal pillar at the room centre — lift
	# the label into the upper third so it doesn't sit on top of the glyph.
	var type_id: String = String(room.get("type", room_id))
	var label_y: float
	if type_id == "control_room":
		label_y = rect.position.y + rect.size.y * 0.30
	else:
		label_y = centre.y + fs * 0.35
	var text_pos: Vector2 = Vector2(centre.x - text_w * 0.5, label_y)
	var text_color: Color = Color(0.95, 0.98, 1.0, 1.0) if is_current else Color(0.78, 0.88, 0.96, 0.9)
	canvas.draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs, text_color)


# Thin connecting ghost-line between two discovered rooms that share an edge.
# Helps the player see topology before they walk through the door.
func _draw_connection_lines(canvas: CanvasItem, floor_id: int) -> void:
	var seen: Dictionary = {}
	for room_id in _visible_room_ids():
		var room: Dictionary = ShipLayout.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		for edge in ShipLayout.outgoing_edges(room_id):
			var e: Dictionary = edge
			var to_id: String = String(e.get("to", ""))
			if to_id == "" or not _is_room_visible(to_id):
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
	if not target_room.is_empty() and target_room.get("locked", false):
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
	# Suppressed during the breach beat — the red trap door + flooded rooms
	# are the focus; the quest diamond/route would compete with them.
	if _breach_active:
		return
	var quest: Dictionary = GameState.quest_target()
	var quest_room: String = String(quest.get("room", ""))
	if quest_room != "":
		var qpx_var: Variant = _room_to_px(quest_room)
		if qpx_var is Vector2:
			_draw_diamond(canvas, qpx_var, 7.0, QUEST_TARGET_COLOR)


func _draw_route(canvas: CanvasItem) -> void:
	# No dotted route during the breach beat (see _draw_quest_markers).
	if _breach_active:
		return
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
				# During the breach beat, a click on the trap door toggles it
				# (open ↔ close) instead of starting a pan drag.
				if _breach_active and _breach_phase <= 1 and _is_click_on_breach_door(mb.position):
					_advance_breach()
					return
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
				_persist_ui_state()
				_map_view.queue_redraw()
				return
	_placed_marker = {"floor": floor_id, "world": world_var}
	_persist_ui_state()
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

func _refresh_ship_systems() -> void:
	var page: Node = _pages[PAGE_SHIP_SYSTEMS]
	var power: Label = page.get_node_or_null("SysPower") as Label
	var oxygen: Label = page.get_node_or_null("SysOxygen") as Label
	var hull: Label = page.get_node_or_null("SysHull") as Label
	var breach: Label = page.get_node_or_null("SysBreach") as Label
	var scrubber: Label = page.get_node_or_null("SysScrubber") as Label
	if power != null:
		power.text = "  Main power:  %s" % _format_status("", GameState.power_percent).strip_edges()
	if oxygen != null:
		oxygen.text = "  Atmosphere O2:  %d%%" % int(GameState.oxygen)
	if hull != null:
		hull.text = "  Hull integrity:  %s" % _format_status("", GameState.hull_percent).strip_edges()
	if breach != null:
		if not GameState.air_crisis_started:
			breach.text = "  Exposed section:  nominal"
		elif GameState.breaches_sealed.is_empty():
			breach.text = "  Exposed section:  VENTING — seal required"
		else:
			breach.text = "  Exposed section:  sealed"
	if scrubber != null:
		if GameState.scrubber_repaired:
			scrubber.text = "  CO2 scrubber:  online"
		elif GameState.scrubber_diagnosed:
			scrubber.text = "  CO2 scrubber:  FAULT — lime required"
		elif GameState.air_crisis_started:
			scrubber.text = "  CO2 scrubber:  FAULT detected"
		else:
			scrubber.text = "  CO2 scrubber:  nominal"

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


const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")
const KINO_LAUNCH_HEIGHT: float = 1.6   # spawn the orb above the player's hands

func _refresh_kino_control() -> void:
	var page: Node = _pages[PAGE_KINO_CONTROL]
	var desc: Label = page.get_node_or_null("KinoControlDesc") as Label
	var count: Label = page.get_node_or_null("KinoControlCount") as Label
	var list: VBoxContainer = page.get_node_or_null("KinoActionList") as VBoxContainer
	if desc != null:
		desc.text = "Launch a Kino to scout, or take control of any Kino you've left out in the field — wherever it is."
	if count != null:
		count.text = "  Kinos in hand:  %d / %d" % [GameState.kino_orbs, GameState.KINO_ORB_MAX]
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	if GameState.kino_orbs > 0:
		var launch: Button = _kino_action_button("LAUNCH NEW KINO", true)
		launch.pressed.connect(_on_launch_kino)
		list.add_child(launch)
	_label(list, "  Live Kinos:", 13, Color(0.55, 0.85, 1.0, 0.85))
	if GameState.deployed_kinos.is_empty():
		_label(list, "    (none deployed)", 13, Color(0.7, 0.75, 0.85, 0.8))
	else:
		for i in range(GameState.deployed_kinos.size()):
			var k: Dictionary = GameState.deployed_kinos[i]
			var loc: String = _scene_short_name(String(k.get("scene", "")))
			var b: Button = _kino_action_button("PILOT KINO %d  —  %s" % [i + 1, loc], false)
			b.pressed.connect(_on_pilot_deployed.bind(i))
			list.add_child(b)


# Spend a carried orb and dive into a fresh Kino, launched right where the player
# stands (Eli stays put, holding the remote). In the gate room the player flies
# it through the active Stargate to reach the planet.
func _on_launch_kino() -> void:
	if GameState.kino_orbs <= 0:
		return
	if not GameState.consume_kino_orb():
		return
	Audio.play("res://sounds/menu_click.ogg")
	GameState.kino_pilot_mode = true
	_close()
	_possess_ship_kino()


# Take control of an already-deployed (live) Kino — from any scene. If it's in
# the current scene, possess it in place; otherwise warp to its scene and the
# scene spawns the controlled Kino at its tracked position. Either way the
# player's BODY is recorded so closing the remote returns there.
func _on_pilot_deployed(index: int) -> void:
	if index < 0 or index >= GameState.deployed_kinos.size():
		return
	var entry: Dictionary = GameState.deployed_kinos[index]
	var scene_path: String = String(entry.get("scene", ""))
	var pos: Vector3 = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0)))
	var same_scene: bool = scene_path == "" or scene_path == GameState.current_scene_path
	# Cross-scene control is supported for the planet (fly a Kino on the surface
	# from the ship). A Kino left elsewhere on the ship is retaken from its room.
	if not same_scene and scene_path != "res://scenes/planet.tscn":
		GameState.add_log("That Kino is in another section — go there to take control.")
		return
	Audio.play("res://sounds/menu_click.ogg")
	_record_body()
	GameState.deployed_kinos.remove_at(index)   # now the active, piloted Kino
	GameState.deployed_kinos_changed.emit()
	GameState.kino_pilot_mode = true
	_close()
	if same_scene:
		_possess_kino_here(pos, false)
	else:
		GameState.kino_pilot_target_scene = scene_path
		GameState.kino_pilot_target_pos = pos
		SceneRouter.change_to(scene_path, "")


# Record the player's body (scene + transform) so [E] returns control there.
func _record_body() -> void:
	GameState.kino_return_scene = GameState.current_scene_path
	GameState.kino_return_room_id = GameState.current_room_id
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		GameState.kino_return_position = player.global_position
		GameState.kino_return_yaw = player.rotation.y


# Launch a ship-mode Kino at the player's position. Records the body + possesses
# the current scene; the drone flies through the gate to reach the planet.
# Falls back to a direct planet warp if there's no live scene/player.
func _possess_ship_kino() -> void:
	var scene: Node = get_tree().current_scene
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if scene == null or player == null:
		SceneRouter.change_to("res://scenes/planet.tscn", "")
		return
	_record_body()
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var spawn: Vector3 = player.global_position + fwd * 0.8 + Vector3.UP * KINO_LAUNCH_HEIGHT
	_possess_kino_here(spawn, true)


# Spawn + possess a Kino in the CURRENT scene at `spawn_pos`. If a player body is
# present (the gate room), it STAYS PUT holding the remote (input locked, hands-
# in-front pose). The drone takes the camera. `in_ship` enables gate-crossing.
func _possess_kino_here(spawn_pos: Vector3, in_ship: bool) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		if player.has_method("set_input_locked"):
			player.call("set_input_locked", true)
		if player.has_method("set_pose_override"):
			player.call("set_pose_override", "holding-both")
		_attach_remote_prop(player)
	var hud_layer: Node = scene.get_node_or_null("HUDLayer")
	if hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	var drone: CharacterBody3D = KinoDroneScript.new()
	drone.name = "KinoDrone"
	drone.set("launch_in_ship", in_ship)
	# NOT in group "player": the body (if any) is still the player.
	if player != null:
		drone.rotation.y = player.rotation.y
	scene.add_child(drone)
	drone.global_position = spawn_pos


# A small "Kino remote" prop parented to Eli so the player (looking back) and
# onlookers see him gripping the controller while he pilots the Kino. Paired
# with the "holding-both" pose, it sits between his hands out in front (Godot
# forward is -Z) at chest height, screen tilted up toward his face.
func _attach_remote_prop(player: Node3D) -> void:
	if player.get_node_or_null("KinoRemoteProp") != null:
		return
	var prop: Node3D = Node3D.new()
	prop.name = "KinoRemoteProp"
	# Between the hands, forward of the chest. Tuned against the holding-both pose
	# at the character's 1.6x model scale (hands land ~0.7 m up, ~0.4 m forward).
	prop.position = Vector3(0.0, 0.72, -0.42)
	prop.rotation_degrees = Vector3(-35.0, 0.0, 0.0)   # tilt the screen up
	player.add_child(prop)

	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.20, 0.05, 0.30)
	body.mesh = box
	body.material_override = _remote_mat(Color(0.10, 0.12, 0.16), false)
	prop.add_child(body)

	var screen: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(0.15, 0.02, 0.22)
	screen.mesh = sbox
	screen.position = Vector3(0.0, 0.035, 0.0)
	screen.material_override = _remote_mat(Color(0.45, 0.80, 1.0), true)
	prop.add_child(screen)


func _remote_mat(col: Color, glow: bool) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.2
	else:
		m.metallic = 0.4
		m.roughness = 0.5
	return m


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
