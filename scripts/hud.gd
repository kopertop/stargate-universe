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
# Gold-primary WoW skin (HUD redesign Phase 0, #141). These mirror
# scripts/ui/hud_theme.gd::HudTheme — kept as inline literals here (not a
# class_name reference) to dodge the cold-import class_name-registration race in
# headless runs. The hud_wow.gd cohesion test mirrors SKIN_ACCENT as its contract.
const SKIN_ACCENT: Color = Color(0.83, 0.66, 0.32, 1.0)        # primary GOLD border
const SKIN_ACCENT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)    # quest title / attention (bright gold)
const SKIN_ACCENT_DIM: Color = Color(0.55, 0.46, 0.28, 0.85)   # inactive tab / dimmed accent
const SKIN_PANEL_BG: Color = Color(0.035, 0.035, 0.045, 0.82)  # near-black translucent fill
const SKIN_CORNER_RADIUS: int = 4
const SKIN_BORDER_WIDTH: int = 2
const SKIN_TEXT_PRIMARY: Color = Color(0.96, 0.92, 0.80, 1.0)  # warm off-white
const SKIN_TEXT_OUTLINE: Color = Color(0, 0, 0, 0.9)

# WoW-style player unit frame (upper-left, below the compass banner). A square
# portrait of Eli on the left, his name plate top-right of it, and the Health +
# Oxygen bars stacked beneath the name (relocated here from the old bottom-left
# Status VBox). Built in code so the hud.tscn diff stays minimal; the bar refs
# (_health_bar / _oxygen_bar) are assigned during the build and keep the
# existing GameState.health_changed / oxygen_changed bindings. (#65)
const PortraitLoaderScript := preload("res://scripts/portrait_loader.gd")
const UNIT_PLAYER_NAME: String = "Eli Wallace"
const UNIT_PORTRAIT_KEY: String = "Eli"
# Promoted to the very top-left corner to match the concept (HUD redesign Phase 1,
# #141). The compass banner's left anchor is pushed right (see _spawn_compass) so
# it no longer sits under this frame.
const UNIT_FRAME_POS: Vector2 = Vector2(14.0, 10.0)
const UNIT_PORTRAIT_SIZE: Vector2 = Vector2(76.0, 76.0)
const UNIT_BAR_WIDTH: float = 168.0
# Player level shown in a badge over the portrait's lower-left (placeholder until
# a real level system exists — the WoW frame always carries a level pip).
const UNIT_LEVEL: int = 1
const UNIT_HEALTH_FILL: Color = Color(0.35, 0.85, 0.45, 0.95)
const UNIT_HEALTH_CRITICAL_FILL: Color = Color(0.95, 0.3, 0.3, 0.98)
const UNIT_OXYGEN_FILL: Color = Color(0.4, 0.85, 0.95, 0.95)
# Below this fraction of max HP the health bar turns red and pulses.
const UNIT_HEALTH_CRITICAL_FRAC: float = 0.3
var _unit_frame: Control = null
var _health_bar: ProgressBar = null
var _oxygen_bar: ProgressBar = null
# Numeric "cur/max" overlays centred on each vitals bar (WoW-style), updated in
# the health/oxygen change handlers.
var _health_value: Label = null
var _oxygen_value: Label = null
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
const EDGE_ARROW_ACCENT: Color = Color(1.0, 0.84, 0.42, 0.95)  # gold, matches skin (#141)
const EDGE_ARROW_MARGIN: float = 64.0
var _edge_arrow: Polygon2D = null

# Circular radar minimap (top-right, #141 Phase 4). Always-on, drawn by
# scripts/ui/minimap.gd (preloaded by path to dodge the class_name race). The HUD
# feeds it heading-rotated, player-relative markers each frame; it owns the disc /
# ring / arrow drawing. A room-name label sits just beneath it.
const MinimapScript := preload("res://scripts/ui/minimap.gd")
const MINIMAP_SIZE: float = 150.0
const MINIMAP_RANGE: float = 18.0       # world metres mapped to the disc radius
const MINIMAP_POS_RIGHT: float = -18.0
const MINIMAP_POS_TOP: float = 14.0
const MINIMAP_MARKER_QUEST: Color = Color(1.0, 0.84, 0.42, 1.0)
const MINIMAP_MARKER_INTERACT: Color = Color(0.75, 0.85, 1.0, 0.9)
var _minimap: Control = null
var _minimap_name: Label = null

# WoW-style action bar (bottom-CENTER, #141 Phase 5). Four FIXED controller-first
# slots, always shown. `ActionBar` is a full-width-bottom CenterContainer (so its
# corner anchors still read 1.0/1.0 for the cohesion test) holding a centred HBox
# of slots. Each slot shows its bound key glyph (read live from InputMap) over the
# action's icon; empty/reserved slots show just the gold frame + slot number.
const ACTION_SLOT_SIZE: Vector2 = Vector2(56, 56)
const ACTION_BAR_MARGIN: float = 18.0
# Fixed slot roster. Each slot's hotkey is its NUMBER (1-4) on keyboard, or a
# D-pad direction (Up / Right / Down / Left) when a controller is connected — the
# glyph shown reflects whichever device is active. Slots select the wielded
# tool/weapon (Inventory hotbar); they do NOT fire interact / open Kino.
# Empty `id` == reserved slot (frame only) until an item is assigned.
const ACTION_SLOTS: Array = [
	{"index": 0, "key": KEY_1, "pad": JOY_BUTTON_DPAD_UP, "arrow": "↑"},
	{"index": 1, "key": KEY_2, "pad": JOY_BUTTON_DPAD_RIGHT, "arrow": "→"},
	{"index": 2, "key": KEY_3, "pad": JOY_BUTTON_DPAD_DOWN, "arrow": "↓"},
	{"index": 3, "key": KEY_4, "pad": JOY_BUTTON_DPAD_LEFT, "arrow": "←"},
]
var _action_bar: CenterContainer = null
var _action_slots_box: HBoxContainer = null
var _action_pulse: Tween = null

# Persistent tabbed Chat / Combat log (bottom-right, #141 Phase 6). Replaces the
# transient top-right feed: a small gold-framed panel with "Chat" / "Combat" tabs
# over a scrollable RichTextLabel, backed by GameState.log_entries (so history
# survives across the session) + live log_added. Smaller font than the old feed.
const CHAT_PANEL_SIZE: Vector2 = Vector2(372.0, 150.0)
const CHAT_FONT_SIZE: int = 12
const CHAT_MAX_LINES: int = 200
var _chat_panel: PanelContainer = null
var _chat_log: RichTextLabel = null
var _combat_log: RichTextLabel = null
var _chat_tab_btn: Button = null
var _combat_tab_btn: Button = null
var _chat_active: String = "chat"

# WoW-style quest objective tracker (upper-right). The tracked quest's title in
# an accent header above its active objective line, prefixed with an empty
# checkbox. Built in code so the hud.tscn diff stays minimal. Driven by the
# QuestLog autoload: refreshed on _ready and whenever GameState mirrors a
# QuestLog step change (GameState.quest_step_changed). Hidden cleanly when no
# quest is tracked. Sits ABOVE the recent-log feed (which is pushed down in
# _ready) so the two top-right elements never overlap. (#66)
const TRACKER_POS_RIGHT: float = -24.0       # offset from the right edge
const TRACKER_POS_TOP: float = 196.0         # below the top-right minimap (#141 P4)
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
	if Inventory.has_signal("wield_changed") and not Inventory.wield_changed.is_connected(_on_wield_changed):
		Inventory.wield_changed.connect(_on_wield_changed)
	if Inventory.has_signal("changed") and not Inventory.changed.is_connected(_on_inventory_changed_for_bar):
		Inventory.changed.connect(_on_inventory_changed_for_bar)
	# The Chat panel is a NARRATIVE transcript: it is fed by dialogue_shown
	# (character speech) + narrative_added (stage directions / scripted lines),
	# NOT log_added — log_added is the noisy system journal (discovery, resources,
	# saves) and must not flood the chat. So the chat starts empty and only fills
	# as characters actually speak. (#141)
	GameState.narrative_added.connect(_on_narrative_added)
	GameState.chat_cleared.connect(_on_chat_cleared)
	GameState.dialogue_shown.connect(_on_dialogue_shown)
	GameState.dialog_started.connect(_on_dialog_started)
	# The interact prompt ("[E] Talk to …") must not linger under an open
	# conversation — it collides with the dialog subtitle (live-play bug).
	GameState.dialog_closed.connect(_on_dialog_closed_restore_prompt)
	# Toast fires on DECIPHER (the on-foot player walked in), not on remote Kino
	# discovery — the decode animation celebrates physically reaching a room.
	# Rooms a drone merely finds stay encrypted on the Kino map until entered.
	GameState.room_deciphered.connect(_on_room_deciphered)
	GameState.current_room_changed.connect(_on_current_room_changed)
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
	_build_chat_panel()
	_build_quest_tracker()
	_refresh_quest_tracker()
	_build_edge_arrow()
	_build_minimap()
	_build_discovery_toast()
	_spawn_compass()
	# If the Gate Room was already deciphered before this HUD mounted (it is
	# deciphered in gate_room.gd::_ready, which can fire before/after ours),
	# treat that boot decipher as already consumed so the first PLAYER-driven
	# room entry is the first toast shown.
	if not GameState.rooms_deciphered.is_empty():
		_first_discovery_consumed = true
	# HUD interface size (#141): scale the whole HUD uniformly from the Settings
	# value, re-applying on live changes and viewport resizes.
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("hud_scale_changed"):
		settings.hud_scale_changed.connect(_on_hud_scale_changed)
	get_viewport().size_changed.connect(_apply_hud_scale)
	_apply_hud_scale()
	# Defer player lookup so the scene tree is settled.
	call_deferred("_bind_player")


# Scale the entire HUD uniformly to the Settings hud_scale. The HUD root is
# re-anchored to the top-left with an explicit size of viewport/scale; scaling
# that by `scale` makes the rendered rect cover the viewport again, so every
# edge-anchored child still lands on the real screen edge — the only correct way
# to scale a full-screen anchored UI without detaching corner widgets.
func _apply_hud_scale() -> void:
	var s: float = 1.0
	var settings: Node = get_node_or_null("/root/Settings")
	if settings != null and "hud_scale" in settings:
		s = float(settings.hud_scale)
	s = clampf(s, 0.5, 2.0)
	var vp: Vector2 = Vector2(get_viewport_rect().size)
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	# Drop the full-rect anchoring so size is ours to set; pivot at top-left (0,0)
	# so the scaled rect's origin stays pinned to the screen origin.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	position = Vector2.ZERO
	pivot_offset = Vector2.ZERO
	scale = Vector2(s, s)
	size = vp / s


func _on_hud_scale_changed(_value: float) -> void:
	_apply_hud_scale()


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
	# Span the centre of the screen. Left anchor pushed right of the top-left unit
	# frame (#141 Phase 1) so the frame owns the corner; the strip draws to the
	# control's actual width, so the anchors define how wide it reads.
	_compass.anchor_left = 0.34
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

	# Level badge — a small gold-ringed pip over the portrait's lower-left corner,
	# the way a WoW unit frame always carries a level number.
	var badge: Panel = Panel.new()
	badge.name = "LevelBadge"
	badge.custom_minimum_size = Vector2(24.0, 24.0)
	badge.size = Vector2(24.0, 24.0)
	badge.position = Vector2(-6.0, UNIT_PORTRAIT_SIZE.y - 18.0)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style: StyleBoxFlat = _make_wow_stylebox(SKIN_ACCENT_GOLD)
	badge_style.set_corner_radius_all(12)
	badge_style.bg_color = Color(0.08, 0.07, 0.05, 0.95)
	badge.add_theme_stylebox_override("panel", badge_style)
	var badge_label: Label = Label.new()
	badge_label.text = str(UNIT_LEVEL)
	badge_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 13)
	badge_label.add_theme_color_override("font_color", SKIN_ACCENT_GOLD)
	badge_label.add_theme_color_override("font_outline_color", SKIN_TEXT_OUTLINE)
	badge_label.add_theme_constant_override("outline_size", 4)
	badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_label)
	portrait_frame.add_child(badge)
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
	_health_value = _add_bar_value_label(_health_bar)
	col.add_child(_health_bar)
	_oxygen_bar = _make_vital_bar("Oxygen", UNIT_OXYGEN_FILL)
	_oxygen_value = _add_bar_value_label(_oxygen_bar)
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


# Centred "cur/max" overlay for a vitals bar (WoW-style). Anchored to the bar's
# full rect so it stays centred as the bar resizes; MOUSE_FILTER_IGNORE so it
# never eats input. Returned so the caller can hold the ref and update the text.
func _add_bar_value_label(bar: ProgressBar) -> Label:
	var lbl: Label = Label.new()
	lbl.name = "Value"
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", SKIN_TEXT_PRIMARY)
	lbl.add_theme_color_override("font_outline_color", SKIN_TEXT_OUTLINE)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(lbl)
	return lbl


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
	_update_minimap()


# Top-right circular minimap + a room-name label beneath it. Always built (the
# HUD only mounts in gameplay scenes), so it holds the corner the way the concept
# does. The marker feed is computed each frame in _update_minimap.
func _build_minimap() -> void:
	if _minimap != null and is_instance_valid(_minimap):
		return
	var map: Control = MinimapScript.new()
	map.name = "Minimap"
	map.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	map.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	map.anchor_left = 1.0
	map.anchor_right = 1.0
	map.anchor_top = 0.0
	map.anchor_bottom = 0.0
	map.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map.offset_left = -(MINIMAP_SIZE - MINIMAP_POS_RIGHT)
	map.offset_right = MINIMAP_POS_RIGHT
	map.offset_top = MINIMAP_POS_TOP
	map.offset_bottom = MINIMAP_POS_TOP + MINIMAP_SIZE
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map)
	_minimap = map

	# Room/zone name centred just beneath the disc.
	var name_l: Label = Label.new()
	name_l.name = "MinimapName"
	name_l.anchor_left = 1.0
	name_l.anchor_right = 1.0
	name_l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	name_l.offset_left = -(MINIMAP_SIZE + 30.0)
	name_l.offset_right = MINIMAP_POS_RIGHT
	name_l.offset_top = MINIMAP_POS_TOP + MINIMAP_SIZE + 2.0
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", SKIN_ACCENT_GOLD)
	name_l.add_theme_color_override("font_outline_color", SKIN_TEXT_OUTLINE)
	name_l.add_theme_constant_override("outline_size", 5)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_l)
	_minimap_name = name_l


# Recompute the minimap markers in the player's heading frame and push them to
# the widget; refresh the room-name label. Cheap: a handful of nodes, no allocations
# beyond the marker array. No-ops gracefully before the player/camera exist.
func _update_minimap() -> void:
	if _minimap == null or not is_instance_valid(_minimap):
		return
	if _minimap_name != null:
		var rid: String = GameState.current_room_id
		if rid != "":
			_minimap_name.text = String(ShipLayout.room(rid).get("name", rid))
	var player: Node = _player
	if player == null or not (player is Node3D):
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	# Heading yaw from the camera forward, so the disc "up" is the way we look.
	var fwd: Vector3 = -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	var yaw: float = atan2(fwd.x, fwd.z)
	var cos_y: float = cos(yaw)
	var sin_y: float = sin(yaw)
	var origin: Vector3 = (player as Node3D).global_position
	var markers: Array = []
	var waypoint: Node = get_tree().get_first_node_in_group("quest_waypoint")
	if waypoint is Node3D:
		_append_marker(markers, (waypoint as Node3D).global_position, origin, cos_y, sin_y, MINIMAP_MARKER_QUEST)
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Node3D:
			_append_marker(markers, (node as Node3D).global_position, origin, cos_y, sin_y, MINIMAP_MARKER_INTERACT)
	_minimap.call("set_markers", markers)


# Project a world position into the minimap's heading-rotated disc space (-1..1,
# up = forward), clamped to the disc, and append a marker if within range.
func _append_marker(out: Array, world: Vector3, origin: Vector3, cos_y: float, sin_y: float, color: Color) -> void:
	var d: Vector3 = world - origin
	var dist: float = Vector2(d.x, d.z).length()
	if dist > MINIMAP_RANGE * 1.4:
		return
	# Rotate the (x,z) delta by -yaw so the look direction maps to +forward.
	var local_x: float = d.x * cos_y - d.z * sin_y
	var local_z: float = d.x * sin_y + d.z * cos_y
	var disc: Vector2 = Vector2(local_x / MINIMAP_RANGE, -local_z / MINIMAP_RANGE)
	if disc.length() > 1.0:
		disc = disc.normalized()
	out.append({"pos": disc, "color": color})


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
	if _health_value != null:
		_health_value.text = "%d/%d" % [roundi(v), roundi(GameState.MAX_HEALTH)]
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
	if _oxygen_value != null:
		_oxygen_value.text = "%d/%d" % [roundi(v), roundi(GameState.MAX_OXYGEN)]

func _on_kino_changed(_acquired: bool) -> void:
	_refresh_action_bar()


func _on_quest_step_changed(_step: String) -> void:
	_refresh_action_bar()
	_refresh_quest_tracker()


# Bottom-CENTER action bar (#141). A full-width-bottom CenterContainer named
# "ActionBar" (keeps the corner anchors the cohesion test asserts) holding a
# centred HBox of 4 fixed slots, hotkeyed 1-4 (keyboard) or the D-pad (controller).
func _build_action_bar() -> void:
	_action_bar = CenterContainer.new()
	_action_bar.name = "ActionBar"
	_action_bar.anchor_left = 0.0
	_action_bar.anchor_top = 1.0
	_action_bar.anchor_right = 1.0
	_action_bar.anchor_bottom = 1.0
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.offset_top = -(ACTION_SLOT_SIZE.y + ACTION_BAR_MARGIN)
	_action_bar.offset_bottom = -ACTION_BAR_MARGIN
	# The CenterContainer spans the width but must not eat world clicks outside the
	# slots; the inner HBox + slots take input, the container itself ignores.
	_action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_bar)

	_action_slots_box = HBoxContainer.new()
	_action_slots_box.name = "Slots"
	_action_slots_box.add_theme_constant_override("separation", 8)
	_action_bar.add_child(_action_slots_box)

	_setup_action_slot_binds()
	# Re-glyph the bar when a controller is plugged in/out (1-4 <-> D-pad arrows).
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


# Add each slot's number key + D-pad button to a dedicated wield_slot_N action
# so pressing 1–4 (or the D-pad) selects the hotbar item without firing interact
# or opening the Kino remote. Idempotent.
func _setup_action_slot_binds() -> void:
	for entry in ACTION_SLOTS:
		var idx: int = int(entry["index"])
		var action: String = "wield_slot_%d" % (idx + 1)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key_ev: InputEventKey = InputEventKey.new()
		key_ev.physical_keycode = int(entry["key"])
		if not _action_has_event(action, key_ev):
			InputMap.action_add_event(action, key_ev)
		var pad_ev: InputEventJoypadButton = InputEventJoypadButton.new()
		pad_ev.button_index = int(entry["pad"])
		if not _action_has_event(action, pad_ev):
			InputMap.action_add_event(action, pad_ev)


func _action_has_event(action: String, ev: InputEvent) -> bool:
	for existing in InputMap.action_get_events(action):
		if existing.is_match(ev):
			return true
	return false


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_action_bar()


func _on_wield_changed(_index: int, _item_id: String) -> void:
	_refresh_action_bar()


func _on_inventory_changed_for_bar() -> void:
	_refresh_action_bar()


# A controller is "active" (so the bar shows D-pad arrows) when one is connected.
func _controller_active() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _unhandled_input(event: InputEvent) -> void:
	for entry in ACTION_SLOTS:
		var idx: int = int(entry["index"])
		var action: String = "wield_slot_%d" % (idx + 1)
		if event.is_action_pressed(action):
			Inventory.select_wield(idx)
			get_viewport().set_input_as_handled()
			return


# One slot per hotbar index. Icons come from Inventory.hotbar_item; the active
# wield gets a gold attention border. Scout beat still pulses the Kino slot.
func _refresh_action_bar() -> void:
	if _action_slots_box == null:
		return
	for c in _action_slots_box.get_children():
		c.queue_free()
	if _action_pulse != null and _action_pulse.is_running():
		_action_pulse.kill()
	_action_pulse = null
	_kino_hint.visible = false

	var scouting: bool = GameState.quest_step == GameState.QUEST_SCOUT_KINO
	var active_idx: int = int(Inventory.active_wield_index())
	for entry in ACTION_SLOTS:
		var idx: int = int(entry["index"])
		var item_id: String = String(Inventory.hotbar_item(idx))
		var selected: bool = idx == active_idx and item_id != ""
		var attention: bool = selected or (scouting and item_id == "kino_remote")
		var slot: Panel = _make_action_slot(entry, item_id, attention, idx)
		_action_slots_box.add_child(slot)
		if scouting and item_id == "kino_remote":
			_action_pulse = create_tween().set_loops()
			_action_pulse.tween_property(slot, "modulate:a", 0.55, 0.6)
			_action_pulse.tween_property(slot, "modulate:a", 1.0, 0.6)

	if scouting and Inventory.has("kino_remote"):
		_kino_hint.text = "Open the Kino Remote"
		_kino_hint.offset_top = -52.0 - ACTION_SLOT_SIZE.y - ACTION_BAR_MARGIN
		_kino_hint.offset_bottom = -24.0 - ACTION_SLOT_SIZE.y - ACTION_BAR_MARGIN
		_kino_hint.visible = true


# One fixed action slot. Click selects that hotbar index.
func _make_action_slot(entry: Dictionary, item_id: String, attention: bool, slot_index: int) -> Panel:
	var slot: Panel = Panel.new()
	slot.custom_minimum_size = ACTION_SLOT_SIZE
	slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot.gui_input.connect(_on_action_slot_input.bind(slot_index))
	var border: Color = SKIN_ACCENT_GOLD if attention else SKIN_ACCENT
	slot.add_theme_stylebox_override("panel", _make_wow_stylebox(border))

	if item_id != "":
		var icon_path: String = String(Inventory.definition(item_id).get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var tex: TextureRect = TextureRect.new()
			tex.texture = load(icon_path)
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			tex.offset_left = 5
			tex.offset_top = 5
			tex.offset_right = -5
			tex.offset_bottom = -5
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(tex)

	var key: Label = Label.new()
	key.text = String(entry["arrow"]) if _controller_active() else str(int(entry["index"]) + 1)
	key.add_theme_font_size_override("font_size", 15)
	key.add_theme_color_override("font_color", SKIN_ACCENT_GOLD)
	key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	key.add_theme_constant_override("outline_size", 4)
	key.position = Vector2(5, 2)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key)
	return slot


# Left-clicking a slot selects that hotbar index.
func _on_action_slot_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	Inventory.select_wield(slot_index)
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
	# Mirror the spoken line into the Chat transcript.
	_append_dialogue(character_name, line)
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
	if _interact_label != null:
		_interact_label.visible = false
	var scene: PackedScene = load("res://objects/dialog_screen.tscn")
	if scene == null:
		return
	var screen: Control = scene.instantiate()
	add_child(screen)
	# DialogScreen.start() shares world_3d + frames the portrait camera.
	screen.call("start", npc, tree)


func _on_dialog_closed_restore_prompt() -> void:
	if _interact_label != null:
		_interact_label.visible = true


# Narrative transcript entry. speaker == "" → a white stage-direction line;
# otherwise a "Speaker: line" dialogue line. Combat-flavoured lines also mirror
# into the Combat tab.
func _on_narrative_added(speaker: String, text: String) -> void:
	if speaker == "":
		_append_narration(text)
	else:
		_append_dialogue(speaker, text)
	if _is_combat_line(text):
		_append_chat_line(_combat_log, "[color=#d98c6b]%s[/color]" % _escape_bbcode(text))


# Wipe the chat transcript (cold-open hand-off — see GameState.clear_chat).
func _on_chat_cleared() -> void:
	if _chat_log != null:
		_chat_log.clear()
	if _combat_log != null:
		_combat_log.clear()


# Character speech also flows into the Chat transcript (in addition to the
# on-screen subtitle panel rendered by _on_dialogue_shown).
func _append_dialogue(speaker: String, line: String) -> void:
	_append_chat_line(_chat_log, "[color=#ffd56b]%s:[/color] [color=#ffffff]\"%s\"[/color]"
		% [_escape_bbcode(speaker), _escape_bbcode(line)])


# Speaker-less stage direction, rendered white + italic (e.g. "Scott arrives
# through the Stargate").
func _append_narration(text: String) -> void:
	_append_chat_line(_chat_log, "[color=#eaeaf0][i]%s[/i][/color]" % _escape_bbcode(text))


# Heuristic routing for the Combat tab — keyword match until a real combat event
# stream exists. Keeps the Combat tab meaningful without a combat system.
func _is_combat_line(line: String) -> bool:
	var l: String = line.to_lower()
	for kw in ["damage", "hit", "attack", "slain", "killed", "hostile", "wounded", "heal"]:
		if l.contains(kw):
			return true
	return false


# Escape BBCode opening brackets so authored text can't accidentally inject tags.
func _escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")


func _append_chat_line(target: RichTextLabel, bbcode: String) -> void:
	if target == null:
		return
	target.append_text(bbcode + "\n")
	# Cap the backlog so a long session can't grow the buffer unbounded.
	if target.get_paragraph_count() > CHAT_MAX_LINES:
		target.remove_paragraph(0)


# Bottom-right tabbed Chat / Combat log. A gold-framed panel: a tab row over a
# scrollable RichTextLabel per stream. Backed by GameState.log_entries (history)
# + live log_added. Replaces the old transient top-right feed.
func _build_chat_panel() -> void:
	if _chat_panel != null and is_instance_valid(_chat_panel):
		return
	# The legacy transient feed node is retired — hide it so nothing renders there.
	if _log_box != null:
		_log_box.visible = false

	_chat_panel = PanelContainer.new()
	_chat_panel.name = "ChatPanel"
	_chat_panel.custom_minimum_size = CHAT_PANEL_SIZE
	_chat_panel.anchor_left = 1.0
	_chat_panel.anchor_top = 1.0
	_chat_panel.anchor_right = 1.0
	_chat_panel.anchor_bottom = 1.0
	_chat_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_panel.offset_left = -(CHAT_PANEL_SIZE.x + 14.0)
	_chat_panel.offset_top = -(CHAT_PANEL_SIZE.y + 14.0)
	_chat_panel.offset_right = -14.0
	_chat_panel.offset_bottom = -14.0
	var panel_style: StyleBoxFlat = _make_wow_stylebox(SKIN_ACCENT, 1)
	panel_style.set_content_margin_all(6.0)
	_chat_panel.add_theme_stylebox_override("panel", panel_style)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_chat_panel.add_child(col)

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	_chat_tab_btn = _make_chat_tab("Chat", "chat")
	_combat_tab_btn = _make_chat_tab("Combat", "combat")
	tabs.add_child(_chat_tab_btn)
	tabs.add_child(_combat_tab_btn)
	col.add_child(tabs)

	_chat_log = _make_chat_stream()
	_combat_log = _make_chat_stream()
	_combat_log.visible = false
	col.add_child(_chat_log)
	col.add_child(_combat_log)

	add_child(_chat_panel)

	# Intentionally NOT seeded from GameState.log_entries — the chat is a live
	# narrative transcript that starts empty and fills only as characters speak
	# (dialogue_shown) or narration fires (narrative_added). The system journal
	# (discovery/resources/saves) deliberately never appears here. (#141)
	_update_chat_tab_styles()


func _make_chat_tab(text: String, id: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", CHAT_FONT_SIZE)
	btn.pressed.connect(_on_chat_tab_pressed.bind(id))
	return btn


func _make_chat_stream() -> RichTextLabel:
	var rt: RichTextLabel = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_active = true
	rt.scroll_following = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.custom_minimum_size = Vector2(0.0, CHAT_PANEL_SIZE.y - 30.0)
	rt.add_theme_font_size_override("normal_font_size", CHAT_FONT_SIZE)
	rt.add_theme_color_override("default_color", SKIN_TEXT_PRIMARY)
	return rt


func _on_chat_tab_pressed(id: String) -> void:
	_chat_active = id
	if _chat_log != null:
		_chat_log.visible = id == "chat"
	if _combat_log != null:
		_combat_log.visible = id == "combat"
	_update_chat_tab_styles()


# Active tab in gold, inactive dimmed — the WoW tab convention.
func _update_chat_tab_styles() -> void:
	if _chat_tab_btn != null:
		_chat_tab_btn.add_theme_color_override("font_color",
			SKIN_ACCENT_GOLD if _chat_active == "chat" else SKIN_ACCENT_DIM)
	if _combat_tab_btn != null:
		_combat_tab_btn.add_theme_color_override("font_color",
			SKIN_ACCENT_GOLD if _chat_active == "combat" else SKIN_ACCENT_DIM)
