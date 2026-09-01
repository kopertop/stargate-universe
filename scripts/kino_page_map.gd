class_name KinoPageMap
extends Node

# Map page for the Kino Remote. Owns map rendering (deck geometry, room
# outlines, glyphs, door pips, player marker, quest markers, route drawing),
# pan/zoom, deck transforms, breach-beat mechanics, and the placed-marker
# (right-click pin) feature.
#
# The actual canvas-item _draw() lives in kino_map_view.gd (KinoMapView),
# which emits needs_geometry; this page subscribes and does all rendering
# with the supplied canvas.

const AncientTextRef: GDScript = preload("res://scripts/ancient_text.gd")

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

# Visual constants for the MapView pipeline. Match the project's
# established cyan-tech palette.
const MAP_BG_COLOR: Color = Color(0.02, 0.06, 0.12, 1.0)
const MAP_GRID_COLOR: Color = Color(0.15, 0.30, 0.45, 0.35)
const MAP_GRID_PITCH: float = 50.0
const ROOM_OUTLINE_COLOR: Color = Color(0.55, 0.85, 1.0, 0.95)
const ROOM_FILL_COLOR: Color = Color(0.20, 0.55, 0.95, 0.10)
const ROOM_OUTLINE_CURRENT_COLOR: Color = Color(0.80, 0.95, 1.0, 1.0)
const ROOM_OUTLINE_TARGET_COLOR: Color = Color(1.0, 0.62, 0.25, 1.0)
const ROOM_FILL_TARGET_COLOR: Color = Color(1.0, 0.45, 0.18, 0.16)
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

# Breach klaxon — dedicated loud player since the shared Audio pool clamps
# at -10 dB, too quiet for an alarm. Preloaded (not load() per tick).
const BREACH_KLAXON_STREAM: AudioStream = preload("res://sounds/klaxon.ogg")

var _coordinator: Node
var _page: Control
var _map_view: Control = null
var _pan_offset: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_last_mouse: Vector2 = Vector2.ZERO
var _zoom: float = ZOOM_DEFAULT
var _console_mode: bool = false
var _active_floor_override: int = -1
var _placed_marker: Variant = null
var _deck_transform: Dictionary = {}

# HUD readouts on the map page.
var _status_power: Label = null
var _status_oxygen: Label = null
var _status_hull: Label = null
var _map_deck_label: Label = null
var _zoom_slider: HSlider = null
var _level_bar: VBoxContainer = null

# Breach beat state.
var _breach_active: bool = false
var _breach_phase: int = 0
var _breach_time: float = 0.0
var _breach_trap_from: String = ""
var _breach_trap_to: String = ""
var _breach_jammed_room: String = ""
var _breach_flood_rooms: Array = []
var _breach_klaxon_timer: Timer = null

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = Control.new()
	_page.name = "Map"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(_page)
	# Map nodes are placed deferred each open via refresh so newly
	# discovered rooms appear without rebuilding the page.
	return _page

func is_available() -> bool:
	return true

func set_console_mode(mode: bool) -> void:
	_console_mode = mode

func get_pan_offset() -> Vector2:
	return _pan_offset

func set_pan_offset(offset: Vector2) -> void:
	_pan_offset = offset

func get_zoom() -> float:
	return _zoom

func set_zoom(z: float) -> void:
	_zoom = z

func get_active_floor_override() -> int:
	return _active_floor_override

func set_active_floor_override(f: int) -> void:
	_active_floor_override = f

func get_placed_marker() -> Variant:
	return _placed_marker

func set_placed_marker(m: Variant) -> void:
	_placed_marker = m

func get_breach_active() -> bool:
	return _breach_active

func get_map_view() -> Control:
	return _map_view

func refresh() -> void:
	var page: Control = _page
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

	# Status readouts (right side).
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

	# Level-switcher bar — vertical strip on the right side of the map page.
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
	_level_bar.visible = false  # "hidden for now, we'll have other levels later"
	page.add_child(_level_bar)
	_rebuild_level_bar()

	# MapView — KinoMapView subclass owns the _draw() override.
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

func refresh_status_readouts() -> void:
	_refresh_status_readouts()

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

# Active floor = level-bar override if set, else the floor the player is
# currently in, else 0. Lookup-only — no side effects.
func _active_floor() -> int:
	if _active_floor_override >= 0:
		return _active_floor_override
	var room: Dictionary = ProceduralShip.room(GameState.current_room_id)
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
	# Enumerate floors that contain at least one DISCOVERED room.
	var floors: Array = []
	for room_id in GameState.rooms_discovered:
		var r: Dictionary = ProceduralShip.room(room_id)
		if r.is_empty():
			continue
		var f: int = int(r.get("floor", 0))
		if not floors.has(f):
			floors.append(f)
	floors.sort()
	floors.reverse()
	for f in floors:
		var b: Button = Button.new()
		b.text = "L%d" % f
		b.custom_minimum_size = Vector2(40, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_font_size_override("font_size", 13)
		var active: bool = (f == _active_floor())
		b.add_theme_stylebox_override("normal", _coordinator.call("_button_stylebox", active))
		b.add_theme_stylebox_override("hover", _coordinator.call("_button_stylebox_hover"))
		b.pressed.connect(_on_level_button.bind(int(f)))
		Audio.attach_ui_hover(b)
		_level_bar.add_child(b)

func _on_level_button(floor_id: int) -> void:
	_active_floor_override = floor_id
	_pan_offset = Vector2.ZERO  # Reset pan when switching decks.
	if _map_deck_label != null:
		_map_deck_label.text = _deck_subtitle()
	_rebuild_level_bar()
	if _map_view != null:
		_map_view.queue_redraw()

# Route resolution: placed marker wins over the active quest target.
# Returns "" if neither resolves or if the player is already there.
func active_route_target() -> String:
	var target: String = _placed_marker_room()
	if target == "":
		var quest: Dictionary = GameState.quest_target()
		target = String(quest.get("room", ""))
	var from_id: String = GameState.current_room_id
	if from_id == "" or target == "" or target == from_id:
		return ""
	return target

# Room IDs the map should render. Handheld Kino → fog-of-war (only
# discovered). Console mode → every room on the active floor.
func _visible_room_ids() -> Array:
	if not _console_mode:
		return GameState.rooms_discovered
	var ids: Array = []
	var floor_id: int = _active_floor()
	for r in ProceduralShip.all_known_rooms():
		if int(r.get("floor", 0)) == floor_id:
			ids.append(String(r.get("id", "")))
	return ids

func _is_room_visible(room_id: String) -> bool:
	if not _console_mode:
		return GameState.rooms_discovered.has(room_id)
	var r: Dictionary = ProceduralShip.room(room_id)
	return not r.is_empty() and int(r.get("floor", 0)) == _active_floor()

# Compute ONE transform for the active floor.
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
		var room: Dictionary = ProceduralShip.room(room_id)
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

func _room_to_px(room_id: String) -> Variant:
	var room: Dictionary = ProceduralShip.room(room_id)
	if room.is_empty():
		return null
	var floor_id: int = int(room.get("floor", 0))
	var centre: Vector2 = Vector2(
		(float(room["startX"]) + float(room["endX"])) * 0.5,
		(float(room["startY"]) + float(room["endY"])) * 0.5,
	)
	return _world_to_px(floor_id, centre)

func _room_rect_px(room_id: String) -> Variant:
	var room: Dictionary = ProceduralShip.room(room_id)
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

# --- Draw callback ---

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
	# Blocked-door beat overlay.
	_draw_breach_overlay(canvas)
	# Outer chrome.
	_draw_corner_brackets(canvas, _map_view.size)
	_draw_north_arrow(canvas, _map_view.size)

# --- Process (breach animation) ---

func process(delta: float) -> void:
	if _breach_active:
		_breach_time += delta
		if _map_view != null:
			_map_view.queue_redraw()

# --- Breach beat ---

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

func stop_breach() -> void:
	if _breach_active:
		_breach_active = false
		_stop_breach_klaxon()
		_clear_breach_caption()

func _breach_door_px() -> Variant:
	var a: Variant = _room_to_px(_breach_trap_from)
	var b: Variant = _room_to_px(_breach_trap_to)
	if a is Vector2 and b is Vector2:
		return ((a as Vector2) + (b as Vector2)) * 0.5
	return null

func _is_click_on_breach_door(pos: Vector2) -> bool:
	var dp: Variant = _breach_door_px()
	return dp is Vector2 and pos.distance_to(dp) <= BREACH_DOOR_CLICK_RADIUS

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

func _set_breach_caption(text: String) -> void:
	var root: Control = _coordinator.get("_root") as Control
	if root == null:
		return
	var label: Label = root.get_node_or_null("BreachCaption") as Label
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
		root.add_child(label)
	label.text = text

func _clear_breach_caption() -> void:
	var root: Control = _coordinator.get("_root") as Control
	if root == null:
		return
	var label: Node = root.get_node_or_null("BreachCaption")
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

# --- Map drawing ---

func _draw_deck_geometry(canvas: CanvasItem, floor_id: int, _rect: Rect2) -> void:
	for room_id in _visible_room_ids():
		var room: Dictionary = ProceduralShip.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		_draw_room_outline(canvas, room)
	_draw_connection_lines(canvas, floor_id)
	for room_id in _visible_room_ids():
		var room: Dictionary = ProceduralShip.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		_draw_door_pips_for_room(canvas, room)

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
	_draw_room_grid(canvas, rect)
	canvas.draw_rect(rect, outline, false, (2.5 if (is_current or is_target) else 1.5))
	_draw_room_glyph(canvas, room, rect, is_current)
	# Name label.
	var name_text: String = String(room.get("name", room_id)).to_upper()
	if rect.size.x < 24.0 or rect.size.y < 18.0:
		return
	var font: Font = ThemeDB.fallback_font
	if not GameState.is_deciphered(room_id):
		var ancient: Font = AncientTextRef.ancient_font()
		if ancient != null:
			font = ancient
	var fs: int = 11 if is_current else 10
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
			return
	var centre: Vector2 = rect.position + rect.size * 0.5
	var type_id: String = String(room.get("type", room_id))
	var label_y: float
	if type_id == "control_room":
		label_y = rect.position.y + rect.size.y * 0.30
	else:
		label_y = centre.y + fs * 0.35
	var text_pos: Vector2 = Vector2(centre.x - text_w * 0.5, label_y)
	var text_color: Color = Color(0.95, 0.98, 1.0, 1.0) if is_current else Color(0.78, 0.88, 0.96, 0.9)
	canvas.draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs, text_color)

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

func _draw_room_glyph(canvas: CanvasItem, room: Dictionary, rect: Rect2, is_current: bool) -> void:
	var min_dim: float = min(rect.size.x, rect.size.y)
	if min_dim < 22.0:
		return
	var centre: Vector2 = rect.position + rect.size * 0.5
	var radius: float = min_dim * 0.28
	var glyph_color: Color = Color(0.70, 0.92, 1.0, 0.85) if is_current else Color(0.55, 0.80, 1.0, 0.55)
	var room_id: String = String(room.get("id", ""))
	var type_id: String = String(room.get("type", room_id))
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
			pass

func _draw_stargate_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	canvas.draw_arc(centre, radius, 0.0, TAU, 48, color, 2.0, true)
	canvas.draw_arc(centre, radius * 0.78, 0.0, TAU, 40, color * Color(1, 1, 1, 0.6), 1.0, true)
	for i in 9:
		var theta: float = float(i) / 9.0 * TAU - PI * 0.5
		var p: Vector2 = centre + Vector2(cos(theta), sin(theta)) * radius * 0.88
		canvas.draw_circle(p, 1.6, color)

func _draw_console_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var console_long: float = radius * 1.05
	var console_short: float = radius * 0.45
	var arm: float = radius * 1.05
	_draw_console_panel(canvas, centre + Vector2(0.0, -arm), console_long, console_short, color)
	_draw_console_panel(canvas, centre + Vector2(0.0,  arm), console_long, console_short, color)
	_draw_console_panel(canvas, centre + Vector2(-arm, 0.0), console_short, console_long, color)
	_draw_console_panel(canvas, centre + Vector2( arm, 0.0), console_short, console_long, color)
	_draw_octagon(canvas, centre, radius * 0.32, color)

func _draw_console_panel(canvas: CanvasItem, centre: Vector2, w: float, h: float, color: Color) -> void:
	var body: Rect2 = Rect2(centre - Vector2(w, h) * 0.5, Vector2(w, h))
	canvas.draw_rect(body, color * Color(1, 1, 1, 0.4), true)
	canvas.draw_rect(body, color, false, 1.0)
	var screen: Rect2 = body.grow_individual(-w * 0.18, -h * 0.18, -w * 0.18, -h * 0.45)
	canvas.draw_rect(screen, Color(0.30, 0.85, 1.0, 0.85), true)

func _draw_octagon(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 8:
		var theta: float = (float(i) + 0.5) / 8.0 * TAU
		pts.append(centre + Vector2(cos(theta), sin(theta)) * radius)
	pts.append(pts[0])
	canvas.draw_polyline(pts, color, 1.5)

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
	var door_w: float = w * 0.22
	var door_h: float = h * 0.40
	var door: Rect2 = Rect2(centre + Vector2(-door_w * 0.5, h * 0.35), Vector2(door_w, door_h))
	canvas.draw_rect(door, Color(0.02, 0.06, 0.12, 1.0), true)

func _draw_plant_glyph(canvas: CanvasItem, centre: Vector2, radius: float, color: Color) -> void:
	for i in 3:
		var t: float = float(i) - 1.0  # -1, 0, 1
		var top: Vector2 = centre + Vector2(t * radius * 0.5, -radius * 0.8)
		var bot: Vector2 = centre + Vector2(t * radius * 0.4, radius * 0.6)
		canvas.draw_line(bot, top, color, 2.5)
	canvas.draw_line(centre + Vector2(-radius * 0.6, radius * 0.6), centre + Vector2(radius * 0.6, radius * 0.6), color, 2.0)

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

func _draw_connection_lines(canvas: CanvasItem, floor_id: int) -> void:
	var seen: Dictionary = {}
	for room_id in _visible_room_ids():
		var room: Dictionary = ProceduralShip.room(room_id)
		if room.is_empty() or int(room.get("floor", 0)) != floor_id:
			continue
		for edge in ProceduralShip.outgoing_edges(room_id):
			var e: Dictionary = edge
			var to_id: String = String(e.get("to", ""))
			if to_id == "" or not _is_room_visible(to_id):
				continue
			var key: String = GameState.door_key(room_id, to_id)
			if seen.has(key):
				continue
			seen[key] = true
			var to_room: Dictionary = ProceduralShip.room(to_id)
			if to_room.is_empty() or int(to_room.get("floor", 0)) != floor_id:
				continue
			var a: Variant = _room_to_px(room_id)
			var b: Variant = _room_to_px(to_id)
			if a is Vector2 and b is Vector2:
				canvas.draw_line(a, b, CONNECTION_LINE_COLOR, 1.0)

func _draw_door_pips_for_room(canvas: CanvasItem, room: Dictionary) -> void:
	var room_id: String = String(room["id"])
	var rect_var: Variant = _room_rect_px(room_id)
	if not (rect_var is Rect2):
		return
	var rect: Rect2 = rect_var
	var by_dir: Dictionary = {}
	for edge in ProceduralShip.outgoing_edges(room_id):
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
			var t: float = float(i + 1) / float(edges.size() + 1)
			var pip_centre: Vector2 = _wall_position(rect, String(dir), t)
			var pip_axis: Vector2 = _wall_axis(String(dir))
			var to_id: String = String((edges[i] as Dictionary).get("to", ""))
			var state: String = _pip_state(room_id, to_id, String(dir))
			_draw_door_pip(canvas, pip_centre, pip_axis, state)

func _pip_state(source_id: String, target_id: String, dir: String) -> String:
	var target_room: Dictionary = ProceduralShip.room(target_id)
	if not target_room.is_empty() and target_room.get("locked", false):
		return "hardlock"
	if dir == "elevator" and not GameState.elevator_repaired:
		return "lock"
	if GameState.door_was_traversed(source_id, target_id):
		return "traversed"
	return "open"

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

func _wall_axis(dir: String) -> Vector2:
	match dir:
		"-x", "+x":
			return Vector2(0.0, 1.0)
		"-z", "+z":
			return Vector2(1.0, 0.0)
		_:
			return Vector2(1.0, 0.0)

func _draw_door_pip(canvas: CanvasItem, centre: Vector2, axis: Vector2, state: String) -> void:
	var perp: Vector2 = Vector2(-axis.y, axis.x)
	var half_len: float = PIP_LENGTH * 0.5
	var half_dep: float = PIP_DEPTH * 0.5
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
	if _breach_active:
		return
	var quest: Dictionary = GameState.quest_target()
	var quest_room: String = String(quest.get("room", ""))
	if quest_room != "":
		var qpx_var: Variant = _room_to_px(quest_room)
		if qpx_var is Vector2:
			_draw_diamond(canvas, qpx_var, 7.0, QUEST_TARGET_COLOR)

func _draw_route(canvas: CanvasItem) -> void:
	if _breach_active:
		return
	var target_id: String = active_route_target()
	if target_id == "":
		return
	var path: PackedStringArray = ProceduralShip.path_through_rooms(GameState.current_room_id, target_id)
	var dot_color: Color = CUSTOM_TARGET_COLOR if _placed_marker != null else QUEST_TARGET_COLOR
	for i in range(path.size() - 1):
		var a_var: Variant = _room_to_px(path[i])
		var b_var: Variant = _room_to_px(path[i + 1])
		if not (a_var is Vector2 and b_var is Vector2):
			continue
		_draw_dotted_segment(canvas, a_var, b_var, dot_color)

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

# --- Map input ---

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
		_compute_deck_transforms()
		var post_pt_var: Variant = _world_to_px(_active_floor(), pre_world_var)
		if post_pt_var is Vector2:
			_pan_offset += screen_pt - post_pt_var
	if _map_view != null:
		_map_view.queue_redraw()

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
				_coordinator.call("_persist_ui_state")
				_map_view.queue_redraw()
				return
	_placed_marker = {"floor": floor_id, "world": world_var}
	_coordinator.call("_persist_ui_state")
	if _map_view != null:
		_map_view.queue_redraw()

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

func _placed_marker_room() -> String:
	if _placed_marker == null:
		return ""
	var m: Dictionary = _placed_marker
	var world: Vector2 = m["world"]
	var floor_id: int = int(m.get("floor", 0))
	for room_id in GameState.rooms_discovered:
		var r: Dictionary = ProceduralShip.room(room_id)
		if r.is_empty() or int(r.get("floor", 0)) != floor_id:
			continue
		var rect_world: Rect2 = Rect2(
			Vector2(float(r["startX"]), float(r["startY"])),
			Vector2(float(r["endX"]) - float(r["startX"]), float(r["endY"]) - float(r["startY"])),
		)
		if rect_world.has_point(world):
			return room_id
	return ""