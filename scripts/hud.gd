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

func _ready() -> void:
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.kino_changed.connect(_on_kino_changed)
	GameState.log_added.connect(_on_log_added)
	GameState.dialogue_shown.connect(_on_dialogue_shown)
	GameState.dialog_started.connect(_on_dialog_started)
	_on_objective_changed(GameState.current_objective)
	_on_health_changed(GameState.health)
	_on_oxygen_changed(GameState.oxygen)
	_on_kino_changed(GameState.kino_acquired)
	_interact_label.text = ""
	_dialog_panel.visible = false
	_build_edge_arrow()
	# Defer player lookup so the scene tree is settled.
	call_deferred("_bind_player")


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

func _on_kino_changed(acquired: bool) -> void:
	_kino_hint.visible = acquired
	_kino_hint.text = "[Tab]  Kino Remote"

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
	lbl.add_theme_font_size_override("font_size", 14)
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
