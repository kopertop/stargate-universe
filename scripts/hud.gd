extends Control

# SGU HUD. Listens to GameState signals + the active scene's player to render:
#   • Current objective (top-left)
#   • Health + oxygen bars (bottom-left)
#   • Interact prompt (bottom-center, only when target in range)
#   • Kino Remote reminder (bottom-right, only after acquisition)
#   • Recent log feed (top-right, last 3 entries)

@onready var _objective_label: Label = $Objective
@onready var _health_bar: ProgressBar = $Status/Health/Bar
@onready var _oxygen_bar: ProgressBar = $Status/Oxygen/Bar
@onready var _interact_label: Label = $InteractPrompt
@onready var _kino_hint: Label = $KinoHint
@onready var _log_box: VBoxContainer = $Log
@onready var _dialog_panel: NinePatchRect = $DialogPanel
@onready var _dialog_name: Label = $DialogPanel/Nameplate/Name
@onready var _dialog_line: Label = $DialogPanel/Line

var _player: Node = null
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
const ACTION_BORDER: Color = Color(0.70, 0.80, 0.95, 0.65)
const ACTION_BORDER_ATTENTION: Color = Color(1.0, 0.78, 0.30, 0.95)
var _action_bar: HBoxContainer = null
var _action_pulse: Tween = null

# NOTE: the atmosphere readout is a KINO recon affordance — it lives on the
# drone's overlay (kino_drone.gd::_build_atmo_readout) and is only visible while
# piloting a Kino, NOT on Eli's HUD. The per-room data model (GameState.
# room_atmosphere) + the shared renderer (atmo_readout.gd) feed it there.

# Always-on direction compass (top banner). Single spawner for ALL gameplay
# scenes: ship interiors + gate room read "ship" mode, the lime planet reads
# "planet" mode. Preloaded by path (not class_name) so a fresh headless run
# can't trip the class_name-registration race.
const PlanetCompassScript := preload("res://scripts/planet_compass.gd")
# Scene-path → compass mode. Anything not listed (e.g. title) gets no compass.
const COMPASS_SHIP_SCENES: Array = [
	"res://scenes/gate_room.tscn",
	"res://scenes/room.tscn",
]
const COMPASS_PLANET_SCENES: Array = [
	"res://scenes/planet.tscn",
]
var _compass: Control = null

func _ready() -> void:
	# Wrap the objective within its ~676px box (offset 24→700 in the scene)
	# instead of overflowing across the full top row into the top-right log
	# feed. Extra vertical room lets a long objective wrap to 2–3 lines.
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.offset_bottom = 130.0
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.kino_changed.connect(_on_kino_changed)
	GameState.quest_step_changed.connect(_on_quest_step_changed)
	GameState.log_added.connect(_on_log_added)
	GameState.dialogue_shown.connect(_on_dialogue_shown)
	GameState.dialog_started.connect(_on_dialog_started)
	_on_objective_changed(GameState.current_objective)
	_on_health_changed(GameState.health)
	_on_oxygen_changed(GameState.oxygen)
	_on_kino_changed(Inventory.has("kino_remote"))
	_interact_label.text = ""
	_dialog_panel.visible = false
	_build_action_bar()
	_refresh_action_bar()
	_build_edge_arrow()
	_spawn_compass()
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

func _on_objective_changed(text: String) -> void:
	_objective_label.text = text

func _on_health_changed(v: float) -> void:
	_health_bar.value = v
	# Pulse red when critical (handled by modulate via theme override would be nicer; keep simple).

func _on_oxygen_changed(v: float) -> void:
	_oxygen_bar.value = v

func _on_kino_changed(_acquired: bool) -> void:
	_refresh_action_bar()


func _on_quest_step_changed(_step: String) -> void:
	_refresh_action_bar()


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
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.border_color = ACTION_BORDER_ATTENTION if attention else ACTION_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	slot.add_theme_stylebox_override("panel", sb)

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
