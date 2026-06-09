extends Control

# SGU HUD. Listens to GameState signals + the active scene's player to render:
#   • Player unit frame (upper-left): Eli portrait + name + health/oxygen bars
#   • Interact prompt (bottom-center, only when target in range)
#   • Kino Remote reminder (bottom-right, only after acquisition)
#   • Quest objective tracker (upper-right): tracked quest title + objective
#   • Recent log feed (top-right, last 3 entries, stacked below the tracker)
#
# The single-line objective used to live in the top-left $Objective label; it
# moved entirely to the upper-right quest tracker (#66), so that label is hidden
# in _ready and no longer wired to GameState.objective_changed.

# Retired top-left objective label — kept in the scene but hidden in _ready (see
# the comment there). Held only so _ready can flip it off.
@onready var _objective_label: Label = $Objective
@onready var _interact_label: Label = $InteractPrompt
@onready var _kino_hint: Label = $KinoHint
@onready var _log_box: VBoxContainer = $Log
@onready var _dialog_panel: NinePatchRect = $DialogPanel
@onready var _dialog_name: Label = $DialogPanel/Nameplate/Name
@onready var _dialog_line: Label = $DialogPanel/Line

var _player: Node = null

# --- Shared WoW-skin palette (cohesion pass, #62) --------------------------
# One visual language across every code-built HUD widget (unit frame, action
# bar, quest tracker, discovery toast): the SAME cool-blue accent border, the
# SAME translucent dark panel fill, and the SAME corner radius. Each widget used
# to redefine its own near-but-not-identical stylebox; these constants + the
# _make_wow_stylebox factory are now the single source of truth. The warm-gold
# accent (SKIN_ACCENT_GOLD) is the deliberate secondary highlight for quest
# titles / attention states — also shared, not per-widget.
const SKIN_ACCENT: Color = Color(0.60, 0.78, 0.95, 0.85)       # primary cool-blue border
const SKIN_ACCENT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)    # quest title / attention
const SKIN_PANEL_BG: Color = Color(0.04, 0.06, 0.09, 0.6)      # translucent dark fill
const SKIN_CORNER_RADIUS: int = 4
const SKIN_BORDER_WIDTH: int = 2
const SKIN_TEXT_PRIMARY: Color = Color(0.95, 0.98, 1.0, 1.0)
const SKIN_TEXT_OUTLINE: Color = Color(0, 0, 0, 0.85)

# WoW-style player unit frame (upper-left, below the compass banner). A square
# portrait of Eli on the left, his name plate top-right of it, and the Health +
# Oxygen bars stacked beneath the name (relocated here from the old bottom-left
# Status VBox). Built in code so the hud.tscn diff stays minimal; the bar refs
# (_health_bar / _oxygen_bar) are assigned during the build and keep the
# existing GameState.health_changed / oxygen_changed bindings. (#65)
const PortraitLoaderScript := preload("res://scripts/portrait_loader.gd")
const UNIT_PLAYER_NAME: String = "Eli Wallace"
const UNIT_PORTRAIT_KEY: String = "Eli"
const UNIT_FRAME_POS: Vector2 = Vector2(24.0, 70.0)
const UNIT_PORTRAIT_SIZE: Vector2 = Vector2(72.0, 72.0)
const UNIT_BAR_WIDTH: float = 196.0
const UNIT_HEALTH_FILL: Color = Color(0.35, 0.85, 0.45, 0.95)
const UNIT_HEALTH_CRITICAL_FILL: Color = Color(0.95, 0.3, 0.3, 0.98)
const UNIT_OXYGEN_FILL: Color = Color(0.4, 0.85, 0.95, 0.95)
# Below this fraction of max HP the health bar turns red and pulses.
const UNIT_HEALTH_CRITICAL_FRAC: float = 0.3
var _unit_frame: Control = null
var _health_bar: ProgressBar = null
var _oxygen_bar: ProgressBar = null
var _health_fill_style: StyleBoxFlat = null
var _health_pulse: Tween = null
# Active dialog auto-hide tween. Held so a follow-up line can cancel the old
# fade — otherwise rapid talking would leave the panel half-faded.
var _dialog_tween: Tween = null

# Quest-waypoint edge arrow: a Polygon2D triangle that lives at the centre of
# this Control's coordinate space. When the waypoint Node3D (group
# "quest_waypoint") is offscreen, the arrow shows at the viewport edge along
# the direction from screen-centre to its projected position and rotates to
# point at it. When the waypoint is onscreen — or doesn't exist — the arrow
# hides. Built programmatically so the .tscn stays unchanged.
const EDGE_ARROW_ACCENT: Color = Color(0.55, 0.85, 1.0, 0.95)
const EDGE_ARROW_MARGIN: float = 64.0
var _edge_arrow: Polygon2D = null

# WoW-style action bar (bottom-right). One slot per available tool: a dark
# translucent square with the tool's catalog icon centred and its keybind
# overlaid top-left. Built in code, anchored bottom-right, grows leftward so
# more tools can be added later. Driven by _refresh_action_bar.
const ACTION_SLOT_SIZE: Vector2 = Vector2(58, 58)
const ACTION_BAR_MARGIN: float = 20.0
var _action_bar: HBoxContainer = null
var _action_pulse: Tween = null

# WoW-style quest objective tracker (upper-right). The tracked quest's title in
# an accent header above its active objective line, prefixed with an empty
# checkbox. Built in code so the hud.tscn diff stays minimal. Driven by the
# QuestLog autoload: refreshed on _ready and whenever GameState mirrors a
# QuestLog step change (GameState.quest_step_changed). Hidden cleanly when no
# quest is tracked. Sits ABOVE the recent-log feed (which is pushed down in
# _ready) so the two top-right elements never overlap. (#66)
const TRACKER_POS_RIGHT: float = -24.0       # offset from the right edge
const TRACKER_POS_TOP: float = 70.0          # below the compass banner
const TRACKER_WIDTH: float = 300.0
# Tracker title uses the shared gold accent; objective + outline use the shared
# primary text + outline so all four widgets read in one type/color language.
const TRACKER_TITLE_COLOR: Color = SKIN_ACCENT_GOLD
const TRACKER_OBJECTIVE_COLOR: Color = SKIN_TEXT_PRIMARY
const TRACKER_OUTLINE: Color = SKIN_TEXT_OUTLINE
# Push the recent-log feed below the tracker so they share the top-right corner
# without fighting. Recomputed after each tracker refresh from its real height.
const LOG_GAP_BELOW_TRACKER: float = 12.0
const LOG_TOP_NO_TRACKER: float = 18.0
var _tracker_root: Control = null
var _tracker_title: Label = null
var _tracker_objective: Label = null

# NOTE: the atmosphere readout is a KINO recon affordance — it lives on the
# drone's overlay (kino_drone.gd::_build_atmo_readout) and is only visible while
# piloting a Kino, NOT on Eli's HUD. The per-room data model (GameState.
# room_atmosphere) + the shared renderer (atmo_readout.gd) feed it there.

# Always-on direction compass (top banner). Single spawner for ALL gameplay
# scenes: ship interiors + gate room read "ship" mode, the lime planet reads
# "planet" mode. Preloaded by path (not class_name) so a fresh headless run
# can't trip the class_name-registration race.
const PlanetCompassScript := preload("res://scripts/planet_compass.gd")
# Ancient-text decode component (#61) drives the room-name line of the toast.
const AncientTextScript := preload("res://scripts/ancient_text.gd")
# Scene-path → compass mode. Anything not listed (e.g. title) gets no compass.
const COMPASS_SHIP_SCENES: Array = [
	"res://scenes/gate_room.tscn",
	"res://scenes/room.tscn",
]
const COMPASS_PLANET_SCENES: Array = [
	"res://scenes/planet.tscn",
]
var _compass: Control = null

# Resource strip (issue #134, ship mode only). One pip per tracked resource,
# red when resource_deficit(id) > 0. Built in code, anchored bottom-left so it
# sits above the ground without fighting the unit frame. Shown only when the
# active scene is a ship scene; hidden otherwise. Rebuilt on _build_resource_strip
# and refreshed on GameState.resource_changed.
const STRIP_POS: Vector2 = Vector2(24.0, -110.0)   # offset from bottom-left
const STRIP_PIP_SIZE: Vector2 = Vector2(80.0, 24.0)
const STRIP_OK_COLOR: Color = Color(0.45, 0.85, 0.55, 0.9)
const STRIP_LOW_COLOR: Color = Color(0.95, 0.35, 0.35, 1.0)
var _resource_strip: Control = null
# Labels keyed by resource id for refresh without rebuild.
var _strip_labels: Dictionary = {}   # id → Label

# Center-screen room discovery toast (#63). On the FIRST entry into a room, a
# small letter-spaced "DISCOVERED" header sits above the room name, which starts
# as obfuscated Ancient glyphs and decodes into English (via #61). The whole
# stack then fades to transparent over DISCOVERY_FADE_SECS. Changing rooms
# short-circuits the fade (hidden instantly). Built programmatically so the
# hud.tscn diff stays empty.
const DISCOVERY_FADE_SECS: float = 3.0
# Per-letter decode rate for the room-name reveal: each character flips from its
# Ancient glyph to readable Latin one at a time (left→right) at this cadence, so
# the total decode time scales with the name length.
const DISCOVERY_DECODE_SECS_PER_CHAR: float = 0.08
# Discovery header shares the cool-blue skin accent at full opacity (the header
# must read crisply over the world), keeping the hue identical to the unit
# frame / action-bar borders.
const DISCOVERY_ACCENT: Color = Color(SKIN_ACCENT.r, SKIN_ACCENT.g, SKIN_ACCENT.b, 1.0)
const DISCOVERY_STING_SOUND: String = "res://sounds/discovery_stinger.ogg"
# Special "magical discovery" cue for KEY rooms (Control Interface Room, Kino
# Room, Bridge, Infirmary, …). Which rooms count as "key" is read ONLY via
# ProceduralShip.is_key_room() — the facade delegates base ids to
# ShipLayout.is_key_room() and resolves generated rooms from the room-type
# catalog's key_room flag, keeping a single key-room query.
const DISCOVERY_STING_KEY_SOUND: String = "res://sounds/discovery_stinger_key.ogg"
var _discovery_root: Control = null
var _discovery_name: Node = null      # RichTextLabel (per-char decode) — duck-typed.
var _discovery_fade: Tween = null
# Room the live toast is announcing. discover_room() is followed immediately by
# set_current_room(SAME id) when entering a room, so the room-change short-circuit
# must ignore a change INTO the room the toast is already for, and only fire when
# the player actually moves on to a DIFFERENT room.
var _discovery_room_id: String = ""
# Suppress the very first discovery of the run: the Gate Room is auto-discovered
# on boot before the player has moved, so its toast would fire over the arrival
# cinematic. Every subsequent (player-driven) discovery shows normally.
var _first_discovery_consumed: bool = false

func _ready() -> void:
	# The single-line objective now lives in the upper-right quest tracker
	# (_build_quest_tracker / _refresh_quest_tracker, #66). The old top-left
	# $Objective label is retired so the objective never renders in two corners
	# at once — hidden here rather than deleted from the scene to keep the
	# hud.tscn diff minimal and any external NodePath references intact.
	_objective_label.visible = false
	GameState.health_changed.connect(_on_health_changed)
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.kino_changed.connect(_on_kino_changed)
	GameState.quest_step_changed.connect(_on_quest_step_changed)
	GameState.log_added.connect(_on_log_added)
	GameState.dialogue_shown.connect(_on_dialogue_shown)
	GameState.dialog_started.connect(_on_dialog_started)
	# Toast fires on DECIPHER (the on-foot player walked in), not on remote Kino
	# discovery — the decode animation celebrates physically reaching a room.
	# Rooms a drone merely finds stay encrypted on the Kino map until entered.
	GameState.room_deciphered.connect(_on_room_deciphered)
	GameState.current_room_changed.connect(_on_current_room_changed)
	# Resource strip (issue #134): refresh pips whenever any tracked resource changes.
	GameState.resource_changed.connect(_on_resource_strip_changed)
	# Unit frame builds the relocated health/oxygen bars, so it must exist before
	# the initial _on_health_changed / _on_oxygen_changed binds below.
	_build_unit_frame()
	_on_health_changed(GameState.health)
	_on_oxygen_changed(GameState.oxygen)
	_on_kino_changed(Inventory.has("kino_remote"))
	_interact_label.text = ""
	_dialog_panel.visible = false
	_build_action_bar()
	_refresh_action_bar()
	_build_quest_tracker()
	_refresh_quest_tracker()
	_build_edge_arrow()
	_build_discovery_toast()
	_build_resource_strip()
	_spawn_compass()
	# If the Gate Room was already deciphered before this HUD mounted (it is
	# deciphered in gate_room.gd::_ready, which can fire before/after ours),
	# treat that boot decipher as already consumed so the first PLAYER-driven
	# room entry is the first toast shown.
	if not GameState.rooms_deciphered.is_empty():
		_first_discovery_consumed = true
	# Defer player lookup so the scene tree is settled.
	call_deferred("_bind_player")


# Build the always-on direction compass as a child of this HUD layer. Single
# entry point for every gameplay scene — the mode (ship vs planet) is resolved
# from the active scene's file path. Skipped headlessly / during cinematics
# (instant_mode), where there's no camera to read a heading from and the
# capture harnesses would otherwise see an unexpected child.
func _spawn_compass() -> void:
	if SceneRouter.instant_mode:
		return
	# Idempotent — never grow a second strip (also lets a headless test re-invoke
	# once current_scene is set, since _ready fires before that can happen).
	if _compass != null and is_instance_valid(_compass):
		return
	var scene_path: String = ""
	var current: Node = get_tree().current_scene
	if current != null:
		scene_path = current.scene_file_path
	var compass_mode: String = ""
	if COMPASS_SHIP_SCENES.has(scene_path):
		compass_mode = "ship"
	elif COMPASS_PLANET_SCENES.has(scene_path):
		compass_mode = "planet"
	if compass_mode == "":
		return
	_compass = PlanetCompassScript.new()
	_compass.name = "PlanetCompass"
	# Span ~70% of the screen width, centred. The strip draws to the control's
	# actual width, so the anchors define how wide it reads. Pinned to the VERY
	# TOP as the top banner; the objective label sits below it.
	_compass.anchor_left = 0.15
	_compass.anchor_right = 0.85
	_compass.offset_left = 0.0
	_compass.offset_right = 0.0
	_compass.offset_top = 4.0
	_compass.offset_bottom = 64.0
	_compass.call("set_mode", compass_mode)
	_compass.call("set_scene_path", scene_path)
	add_child(_compass)


# Shared WoW-skin panel stylebox. Every framed HUD widget (portrait, vital bar
# track, action slot) gets its border/fill/radius from here so the skin reads as
# one cohesive treatment. `border_color` and `border_width` let a widget opt
# into the gold attention accent or a thinner hairline while keeping the same
# fill + corner language.
func _make_wow_stylebox(
		border_color: Color = SKIN_ACCENT,
		border_width: int = SKIN_BORDER_WIDTH,
		bg_color: Color = SKIN_PANEL_BG) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(SKIN_CORNER_RADIUS)
	return sb


# WoW-style player unit frame: a portrait of Eli (left) with his name plate and
# the Health + Oxygen bars stacked to its right. Anchored top-left, just below
# the compass banner. Portrait is loaded via the shared PortraitLoader so a
# missing PNG leaves the frame gracefully blank.
func _build_unit_frame() -> void:
	if _unit_frame != null and is_instance_valid(_unit_frame):
		return
	var frame: HBoxContainer = HBoxContainer.new()
	frame.name = "UnitFrame"
	frame.position = UNIT_FRAME_POS
	frame.add_theme_constant_override("separation", 10)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Portrait, framed by a thin accent border.
	var portrait_frame: Panel = Panel.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.custom_minimum_size = UNIT_PORTRAIT_SIZE
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override("panel", _make_wow_stylebox())

	var portrait: TextureRect = TextureRect.new()
	portrait.name = "Portrait"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 2.0
	portrait.offset_top = 2.0
	portrait.offset_right = -2.0
	portrait.offset_bottom = -2.0
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Graceful blank if the PNG is missing — texture stays null.
	portrait.texture = PortraitLoaderScript.portrait_for(UNIT_PORTRAIT_KEY)
	portrait_frame.add_child(portrait)
	frame.add_child(portrait_frame)

	# Right column: name plate over the two vitals bars.
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "Vitals"
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(UNIT_BAR_WIDTH, 0.0)

	var name_label: Label = Label.new()
	name_label.name = "PlayerName"
	name_label.text = UNIT_PLAYER_NAME
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", SKIN_TEXT_PRIMARY)
	name_label.add_theme_color_override("font_outline_color", SKIN_TEXT_OUTLINE)
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)

	_health_bar = _make_vital_bar("Health", UNIT_HEALTH_FILL)
	_health_fill_style = _health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	col.add_child(_health_bar)
	_oxygen_bar = _make_vital_bar("Oxygen", UNIT_OXYGEN_FILL)
	col.add_child(_oxygen_bar)

	frame.add_child(col)
	add_child(frame)
	_unit_frame = frame


# A single thin vitals ProgressBar styled to match the old Status bars: dark
# translucent track with an accent border, a coloured fill, no percentage text.
func _make_vital_bar(bar_name: String, fill_color: Color) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.name = bar_name
	bar.custom_minimum_size = Vector2(UNIT_BAR_WIDTH, 14.0)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bar track shares the skin fill + accent, with a hairline border (width 1).
	bar.add_theme_stylebox_override("background", _make_wow_stylebox(SKIN_ACCENT, 1))
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(SKIN_CORNER_RADIUS)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _build_edge_arrow() -> void:
	_edge_arrow = Polygon2D.new()
	_edge_arrow.name = "QuestEdgeArrow"
	# Isoceles triangle pointing up (-Y in 2D). Local origin = visual centre so
	# rotation pivots around the tip's centroid.
	_edge_arrow.polygon = PackedVector2Array([
		Vector2(0.0, -16.0),
		Vector2(12.0, 10.0),
		Vector2(-12.0, 10.0),
	])
	_edge_arrow.color = EDGE_ARROW_ACCENT
	_edge_arrow.visible = false
	_edge_arrow.z_index = 100
	add_child(_edge_arrow)


# Center-screen discovery toast: a centred VBox holding the small letter-spaced
# "DISCOVERED" header above the AncientText room-name line. Starts hidden and
# fully transparent; _on_room_discovered drives the decode + fade. Anchored to
# the full rect with a CenterContainer so it sits dead-centre at any resolution.
func _build_discovery_toast() -> void:
	var centre: CenterContainer = CenterContainer.new()
	centre.name = "DiscoveryToast"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.z_index = 90
	centre.visible = false
	centre.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Stack"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(box)

	var header: Label = Label.new()
	header.name = "Header"
	header.text = "D I S C O V E R E D"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", DISCOVERY_ACCENT)
	header.add_theme_color_override("font_outline_color", SKIN_TEXT_OUTLINE)
	header.add_theme_constant_override("outline_size", 4)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)

	# Room-name line — a RichTextLabel so the decode can render a readable prefix
	# and an Ancient-glyph suffix simultaneously (per-character glyph→Latin
	# reveal, driven by AncientText.decode_richtext). fit_content sizes it to the
	# text so the parent VBox keeps it centred.
	var name_label: RichTextLabel = RichTextLabel.new()
	name_label.name = "RoomName"
	name_label.bbcode_enabled = true
	name_label.fit_content = true
	name_label.scroll_active = false
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.add_theme_font_size_override("normal_font_size", 34)
	name_label.add_theme_color_override("default_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	add_child(centre)
	_discovery_root = centre
	_discovery_name = name_label


# First entry into a never-seen room: resolve its display name, run the decode,
# play the sting, then fade the whole toast out over DISCOVERY_FADE_SECS. The
# very first discovery of the run (the auto-discovered Gate Room on boot) is
# suppressed so the toast never fires before the player has moved.
func _on_room_deciphered(room_id: String) -> void:
	if not _first_discovery_consumed:
		_first_discovery_consumed = true
		return
	if _discovery_root == null or _discovery_name == null:
		return

	var display_name: String = String(ShipLayout.room(room_id).get("name", room_id))

	# Cancel a still-running fade from a prior discovery so the new toast shows
	# at full opacity (same pattern as _dialog_tween).
	if _discovery_fade != null and _discovery_fade.is_running():
		_discovery_fade.kill()
	_discovery_fade = null

	_discovery_room_id = room_id
	_discovery_root.visible = true
	_discovery_root.modulate = Color(1.0, 1.0, 1.0, 1.0)
	# Per-letter glyph→Latin decode (left→right, DISCOVERY_DECODE_SECS_PER_CHAR each).
	AncientTextScript.decode_richtext(_discovery_name, display_name, self, DISCOVERY_DECODE_SECS_PER_CHAR)

	# Decode sting — skipped under instant_mode (headless / fast-travel) so the
	# playthrough test never queues audio it can't drain. KEY rooms (defined via
	# ShipLayout.is_key_room — owned by a separate work stream) get the special
	# "magical discovery" cue; everything else gets the standard stinger.
	if not SceneRouter.instant_mode and has_node("/root/Audio"):
		var sting: String = DISCOVERY_STING_KEY_SOUND if ProceduralShip.is_key_room(room_id) else DISCOVERY_STING_SOUND
		get_node("/root/Audio").call("play", sting)

	# Under instant_mode the toast resolves + hides immediately (no tween wait).
	if SceneRouter.instant_mode:
		_hide_discovery_toast()
		return

	# Hold until the per-letter decode finishes (scales with name length), then fade.
	var decode_total: float = float(display_name.length()) * DISCOVERY_DECODE_SECS_PER_CHAR
	_discovery_fade = create_tween()
	_discovery_fade.tween_interval(decode_total)
	_discovery_fade.tween_property(_discovery_root, "modulate:a", 0.0, DISCOVERY_FADE_SECS)
	_discovery_fade.tween_callback(Callable(self, "_hide_discovery_toast"))


# Changing rooms short-circuits an in-flight toast: hide it instantly so a stale
# "DISCOVERED <prev room>" never lingers over the new room.
func _on_current_room_changed(room_id: String) -> void:
	if _discovery_root != null and _discovery_root.visible and room_id != _discovery_room_id:
		_hide_discovery_toast()


func _hide_discovery_toast() -> void:
	if _discovery_fade != null and _discovery_fade.is_running():
		_discovery_fade.kill()
	_discovery_fade = null
	if _discovery_root != null:
		_discovery_root.visible = false
		_discovery_root.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _process(_delta: float) -> void:
	_update_edge_arrow()


# Polled each frame because the player + camera move continuously and there's
# no signal that says "the camera matrix changed". Cheap — single unproject
# call and one viewport-rect check per frame, no allocations.
func _update_edge_arrow() -> void:
	if _edge_arrow == null:
		return
	var waypoint: Node = get_tree().get_first_node_in_group("quest_waypoint")
	if waypoint == null or not (waypoint is Node3D):
		_edge_arrow.visible = false
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		_edge_arrow.visible = false
		return
	var world_pos: Vector3 = (waypoint as Node3D).global_position
	var viewport_size: Vector2 = get_viewport_rect().size
	var centre: Vector2 = viewport_size * 0.5
	var behind: bool = camera.is_position_behind(world_pos)
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	var onscreen: bool = (
		not behind
		and screen_pos.x >= 0.0 and screen_pos.x <= viewport_size.x
		and screen_pos.y >= 0.0 and screen_pos.y <= viewport_size.y
	)
	if onscreen:
		_edge_arrow.visible = false
		return

	# Compute the direction from screen-centre toward the projected waypoint.
	# When the waypoint is behind the camera, unproject_position returns a
	# point reflected across the centre, so flip the direction in that case.
	var direction: Vector2 = (screen_pos - centre)
	if behind:
		direction = -direction
	if direction.length() < 0.001:
		direction = Vector2(0.0, -1.0)
	direction = direction.normalized()

	# Clamp the arrow to a rectangle inside the viewport so it never sits on
	# the literal pixel edge. Intersect the ray (centre + t*direction) with
	# the bounds rect.
	var bound_x: float = max(centre.x - EDGE_ARROW_MARGIN, 1.0)
	var bound_y: float = max(centre.y - EDGE_ARROW_MARGIN, 1.0)
	var t_x: float = bound_x / max(abs(direction.x), 0.0001)
	var t_y: float = bound_y / max(abs(direction.y), 0.0001)
	var t: float = min(t_x, t_y)
	_edge_arrow.position = centre + direction * t
	# Polygon points up by default; rotation of 0 ↔ point up (-Y direction).
	# Convert "direction vector" to "rotation about Z" so the tip faces direction.
	_edge_arrow.rotation = direction.angle() + PI * 0.5
	_edge_arrow.visible = true

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("interact_target_changed"):
		_player.interact_target_changed.connect(_on_interact_target_changed)

func _on_interact_target_changed(target: Node) -> void:
	if target == null:
		_interact_label.text = ""
		return
	var prompt: String = "Interact"
	if target.has_method("get_prompt"):
		prompt = target.get_prompt()
	elif "prompt" in target:
		prompt = String(target.prompt)
	_interact_label.text = "[E]  %s" % prompt

func _on_health_changed(v: float) -> void:
	if _health_bar == null:
		return
	_health_bar.value = v
	_update_health_critical(v)

# Below UNIT_HEALTH_CRITICAL_FRAC of max HP the health bar turns red and pulses
# its opacity; above it, the bar returns to its calm green and any pulse stops.
func _update_health_critical(v: float) -> void:
	if _health_bar == null or _health_fill_style == null:
		return
	var critical: bool = v <= GameState.MAX_HEALTH * UNIT_HEALTH_CRITICAL_FRAC
	_health_fill_style.bg_color = UNIT_HEALTH_CRITICAL_FILL if critical else UNIT_HEALTH_FILL
	if critical:
		if _health_pulse == null or not _health_pulse.is_running():
			_health_pulse = create_tween().set_loops()
			_health_pulse.tween_property(_health_bar, "modulate:a", 0.45, 0.45)
			_health_pulse.tween_property(_health_bar, "modulate:a", 1.0, 0.45)
	else:
		if _health_pulse != null and _health_pulse.is_running():
			_health_pulse.kill()
		_health_pulse = null
		_health_bar.modulate.a = 1.0

func _on_oxygen_changed(v: float) -> void:
	if _oxygen_bar == null:
		return
	_oxygen_bar.value = v

func _on_kino_changed(_acquired: bool) -> void:
	_refresh_action_bar()


func _on_quest_step_changed(_step: String) -> void:
	_refresh_action_bar()
	_refresh_quest_tracker()


# Bottom-right action bar anchored to the corner, growing leftward as tools
# are added. Empty until built.
func _build_action_bar() -> void:
	_action_bar = HBoxContainer.new()
	_action_bar.name = "ActionBar"
	_action_bar.anchor_left = 1.0
	_action_bar.anchor_top = 1.0
	_action_bar.anchor_right = 1.0
	_action_bar.anchor_bottom = 1.0
	_action_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.offset_right = -ACTION_BAR_MARGIN
	_action_bar.offset_bottom = -ACTION_BAR_MARGIN
	_action_bar.add_theme_constant_override("separation", 8)
	add_child(_action_bar)


# One slot per currently-available tool. Today just the Kino Remote (gated on
# acquisition); the list is the single extension point for future tools. The
# icon is pulled from the item catalog so HUD + inventory share one source.
# During the scout beat the slot gets an attention border + pulse and the
# repurposed KinoHint label shows a caption above the bar.
func _refresh_action_bar() -> void:
	if _action_bar == null:
		return
	for c in _action_bar.get_children():
		c.queue_free()
	if _action_pulse != null and _action_pulse.is_running():
		_action_pulse.kill()
	_action_pulse = null
	_kino_hint.visible = false

	var tools: Array = []
	if Inventory.has("kino_remote"):
		tools.append({"id": "kino_remote", "key": "Tab"})

	var scouting: bool = GameState.quest_step == GameState.QUEST_SCOUT_KINO
	for tool in tools:
		var attention: bool = scouting and tool["id"] == "kino_remote"
		var slot: Panel = _make_action_slot(String(tool["id"]), String(tool["key"]), attention)
		_action_bar.add_child(slot)
		if attention:
			_action_pulse = create_tween().set_loops()
			_action_pulse.tween_property(slot, "modulate:a", 0.55, 0.6)
			_action_pulse.tween_property(slot, "modulate:a", 1.0, 0.6)

	# Scout-beat caption above the bar (reuses the old KinoHint label).
	if scouting and Inventory.has("kino_remote"):
		_kino_hint.text = "Open the Kino Remote"
		_kino_hint.offset_top = -52.0 - ACTION_SLOT_SIZE.y - ACTION_BAR_MARGIN
		_kino_hint.offset_bottom = -24.0 - ACTION_SLOT_SIZE.y - ACTION_BAR_MARGIN
		_kino_hint.visible = true


func _make_action_slot(item_id: String, key_label: String, attention: bool) -> Panel:
	var slot: Panel = Panel.new()
	slot.custom_minimum_size = ACTION_SLOT_SIZE
	# Clickable, same as pressing the keybind. The icon/label children are
	# MOUSE_FILTER_IGNORE, so the Panel itself receives the click.
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.tooltip_text = "Open the Kino Remote  [%s]" % key_label
	slot.gui_input.connect(_on_action_slot_input.bind(item_id))
	# Shares the skin fill + corner; attention swaps to the gold accent (same gold
	# the quest tracker title uses), otherwise the cool-blue primary border.
	var border: Color = SKIN_ACCENT_GOLD if attention else SKIN_ACCENT
	slot.add_theme_stylebox_override("panel", _make_wow_stylebox(border))

	var icon_path: String = String(Inventory.definition(item_id).get("icon", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex: TextureRect = TextureRect.new()
		tex.texture = load(icon_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.anchor_right = 1.0
		tex.anchor_bottom = 1.0
		tex.offset_left = 5
		tex.offset_top = 5
		tex.offset_right = -5
		tex.offset_bottom = -5
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tex)

	# Keybind overlay, WoW-style top-left corner with an outline so it reads
	# over the icon.
	var key: Label = Label.new()
	key.text = key_label
	key.add_theme_font_size_override("font_size", 13)
	key.add_theme_color_override("font_color", Color.WHITE)
	key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	key.add_theme_constant_override("outline_size", 4)
	key.position = Vector2(4, 1)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key)
	return slot


# Left-clicking an action-bar slot fires the tool's action — the same thing its
# keybind does. Today the only tool is the Kino Remote, whose action mirrors the
# Tab key (KinoRemote.open_remote, gated on owning the remote). Add a match arm
# here when more tools are added.
func _on_action_slot_input(event: InputEvent, item_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	match item_id:
		"kino_remote":
			if has_node("/root/KinoRemote"):
				get_node("/root/KinoRemote").call("open_remote")
	accept_event()

# Upper-right quest tracker: a transparent VBox holding the accent quest title
# over the active objective line. Anchored to the top-right edge, grows down.
# Built empty + hidden; _refresh_quest_tracker fills it from QuestLog.
func _build_quest_tracker() -> void:
	if _tracker_root != null and is_instance_valid(_tracker_root):
		return
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "QuestTracker"
	box.anchor_left = 1.0
	box.anchor_top = 0.0
	box.anchor_right = 1.0
	box.anchor_bottom = 0.0
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_left = -(TRACKER_WIDTH)
	box.offset_right = TRACKER_POS_RIGHT
	box.offset_top = TRACKER_POS_TOP
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false

	var title: Label = Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", TRACKER_TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", TRACKER_OUTLINE)
	title.add_theme_constant_override("outline_size", 5)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)

	var objective: Label = Label.new()
	objective.name = "Objective"
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size = Vector2(TRACKER_WIDTH, 0.0)
	objective.add_theme_font_size_override("font_size", 14)
	objective.add_theme_color_override("font_color", TRACKER_OBJECTIVE_COLOR)
	objective.add_theme_color_override("font_outline_color", TRACKER_OUTLINE)
	objective.add_theme_constant_override("outline_size", 4)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(objective)

	add_child(box)
	_tracker_root = box
	_tracker_title = title
	_tracker_objective = objective
	# The objective wraps to a variable number of lines, so the tracker's height
	# isn't known until layout settles. Re-stack the log feed whenever the
	# tracker resizes (incl. the deferred first layout) so they never overlap.
	box.resized.connect(_apply_log_feed_position)


# Pull the tracked quest's title + active objective from QuestLog and render
# them. Hides the whole panel when nothing is tracked / there's no objective,
# keeping the empty state clean. Also repositions the recent-log feed below the
# tracker so they don't overlap in the top-right corner.
func _refresh_quest_tracker() -> void:
	if _tracker_root == null or not is_instance_valid(_tracker_root):
		return
	var ql: Node = get_node_or_null("/root/QuestLog")
	var quest_title: String = ""
	var objective_text: String = ""
	if ql != null:
		if ql.has_method("title"):
			quest_title = String(ql.call("title"))
		if ql.has_method("objective"):
			objective_text = String(ql.call("objective"))
	# Empty/again state: nothing tracked → hide the panel and restore the log
	# feed to its standalone top position.
	if quest_title == "" and objective_text == "":
		_tracker_root.visible = false
		_reposition_log_feed()
		return
	_tracker_title.text = quest_title
	# Active objective line, prefixed with an empty checkbox glyph (WoW-style).
	_tracker_objective.text = "☐ %s" % objective_text if objective_text != "" else ""
	_tracker_root.visible = true
	_reposition_log_feed()


# Stack the recent-log feed under the quest tracker so they share the corner
# cleanly. Deferred a frame so the tracker's containers have laid out and its
# size is known before we read it.
func _reposition_log_feed() -> void:
	call_deferred("_apply_log_feed_position")


func _apply_log_feed_position() -> void:
	if _log_box == null or not is_instance_valid(_log_box):
		return
	var new_top: float = LOG_TOP_NO_TRACKER
	if _tracker_root != null and is_instance_valid(_tracker_root) and _tracker_root.visible:
		new_top = TRACKER_POS_TOP + _tracker_root.size.y + LOG_GAP_BELOW_TRACKER
	_log_box.offset_top = new_top


func _on_dialogue_shown(character_name: String, line: String) -> void:
	_dialog_name.text = character_name
	_dialog_line.text = line
	_dialog_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_dialog_panel.visible = true
	# Cancel a still-running fade from the previous line so the new one shows
	# at full opacity even if the player triggered them in quick succession.
	if _dialog_tween != null and _dialog_tween.is_running():
		_dialog_tween.kill()
	_dialog_tween = create_tween()
	_dialog_tween.tween_interval(6.5)
	_dialog_tween.tween_property(_dialog_panel, "modulate:a", 0.0, 0.8)
	_dialog_tween.tween_callback(Callable(self, "_hide_dialog_panel"))

func _hide_dialog_panel() -> void:
	_dialog_panel.visible = false

# Choice-tree dialog: instance the full-screen DialogScreen as our child so it
# inherits the HUD's CanvasLayer (above the world, below pause overlays). The
# screen pauses the tree itself and frees itself on close; we just hand it the
# target NPC + tree and forget about it.
func _on_dialog_started(npc: Node3D, tree: Array) -> void:
	if tree.is_empty() or npc == null:
		return
	var scene: PackedScene = load("res://objects/dialog_screen.tscn")
	if scene == null:
		return
	var screen: Control = scene.instantiate()
	add_child(screen)
	# DialogScreen.start() shares world_3d + frames the portrait camera.
	screen.call("start", npc, tree)

# --- Resource strip (issue #134) ---------------------------------------------

# Build a row of resource pips anchored bottom-left. One pip per tracked resource
# (data-driven via tracked_resource_ids — never hardcodes a name). Show only in
# ship scenes (gate_room.tscn / room.tscn); hidden in planet + title.
func _build_resource_strip() -> void:
	if _resource_strip != null and is_instance_valid(_resource_strip):
		return
	# Determine ship mode from the current scene.
	var scene_path: String = ""
	var current: Node = get_tree().current_scene if get_tree() != null else null
	if current != null:
		scene_path = current.scene_file_path
	var is_ship: bool = COMPASS_SHIP_SCENES.has(scene_path)

	var strip: HBoxContainer = HBoxContainer.new()
	strip.name = "ResourceStrip"
	strip.anchor_left = 0.0
	strip.anchor_top = 1.0
	strip.anchor_right = 0.0
	strip.anchor_bottom = 1.0
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = STRIP_POS.x
	strip.offset_bottom = STRIP_POS.y
	strip.add_theme_constant_override("separation", 6)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.visible = is_ship
	add_child(strip)
	_resource_strip = strip
	_strip_labels.clear()

	for id in GameState.tracked_resource_ids():
		var pip: Panel = Panel.new()
		pip.custom_minimum_size = STRIP_PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb: StyleBoxFlat = _make_wow_stylebox(SKIN_ACCENT, 1, SKIN_PANEL_BG)
		pip.add_theme_stylebox_override("panel", sb)
		strip.add_child(pip)

		var lbl: Label = Label.new()
		lbl.name = "Lbl_%s" % id
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.offset_left = 4.0
		lbl.offset_right = -4.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", STRIP_OK_COLOR)
		lbl.add_theme_color_override("font_outline_color", SKIN_TEXT_OUTLINE)
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.text = id.capitalize()
		pip.add_child(lbl)
		_strip_labels[id] = lbl

	_refresh_resource_strip()


func _refresh_resource_strip() -> void:
	if _resource_strip == null or not is_instance_valid(_resource_strip):
		return
	for id in _strip_labels.keys():
		var lbl: Label = _strip_labels[id] as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		var amount: int = GameState.resource_count(id)
		var deficit: int = GameState.resource_deficit(id)
		lbl.text = "%s\n%d" % [id.capitalize(), amount]
		if deficit > 0:
			lbl.add_theme_color_override("font_color", STRIP_LOW_COLOR)
		else:
			lbl.add_theme_color_override("font_color", STRIP_OK_COLOR)


func _on_resource_strip_changed(_type: String, _count: int) -> void:
	_refresh_resource_strip()


# --- end resource strip -------------------------------------------------------

func _on_log_added(line: String) -> void:
	var lbl: Label = Label.new()
	lbl.text = "• " + line
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	lbl.add_theme_font_size_override("font_size", 11)
	_log_box.add_child(lbl)
	# Keep only the last 3. remove_child() first so the count drops synchronously —
	# queue_free() alone defers deletion to end-of-frame and would spin this loop.
	while _log_box.get_child_count() > 3:
		var oldest: Node = _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()
	# Auto-fade & remove after a moment.
	var t: Tween = create_tween()
	t.tween_interval(6.0)
	t.tween_property(lbl, "modulate:a", 0.0, 1.0)
	t.tween_callback(Callable(lbl, "queue_free"))
