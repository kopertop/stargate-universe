class_name AssignmentConsole
extends Interactable

# Spawned in unassigned generated `storage` rooms. Opens a small menu of
# assignable room functions; choosing one calls ProceduralShip.assign_function
# and reloads the room so it rebuilds with the new template + props.
#
# Cost: ROOM_ASSIGN_COST parts (defined in ProceduralShip).
# Respects SceneRouter.instant_mode.

# Set by room.gd BEFORE add_child so _ready reads the correct room.
var console_room_id: String = ""

var _layer: CanvasLayer = null
var _root: Control = null
var _open: bool = false


func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_build_visual()
	prompt = "Assign room function (%d parts)" % ProceduralShip.ROOM_ASSIGN_COST


# ── visual ────────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.22)
	mat.metallic = 0.50
	mat.roughness = 0.45

	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.07, 0.75, 0.50)
	body.mesh = box
	body.material_override = mat
	body.position = Vector3(0.0, 1.30, 0.0)
	add_child(body)

	var screen_col: Color = Color(0.50, 0.30, 1.0)
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = screen_col
	screen_mat.emission_enabled = true
	screen_mat.emission = screen_col
	screen_mat.emission_energy_multiplier = 2.2

	var screen: MeshInstance3D = MeshInstance3D.new()
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = Vector3(0.04, 0.50, 0.35)
	screen.mesh = screen_box
	screen.material_override = screen_mat
	screen.position = Vector3(0.03, 1.30, 0.0)
	add_child(screen)

	var lbl: Label3D = Label3D.new()
	lbl.text = "ROOM\nASSIGN"
	lbl.pixel_size = 0.0036
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 5
	lbl.shaded = false
	lbl.modulate = Color(0.92, 0.88, 1.0, 1.0)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.position = Vector3(0.06, 1.75, 0.0)
	add_child(lbl)


# ── interaction ───────────────────────────────────────────────────────────────

func _on_interact(_by: Node) -> void:
	var router: Node = get_node_or_null("/root/SceneRouter")
	var instant: bool = router != null and router.get("instant_mode") == true
	if instant:
		return  # Headless/instant_mode: no UI to show.
	if _open:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	if _open:
		return
	_open = true
	_build_ui()
	if _root != null:
		_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menu() -> void:
	if not _open:
		return
	_open = false
	if _root != null:
		_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	if _layer != null:
		if _root != null:
			_root.visible = true
		return

	_layer = CanvasLayer.new()
	_layer.layer = 85
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.06, 0.88)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.gui_input.connect(_on_bg_input)
	_root.add_child(bg)

	var frame: PanelContainer = PanelContainer.new()
	frame.anchor_left = 0.30
	frame.anchor_right = 0.70
	frame.anchor_top = 0.25
	frame.anchor_bottom = 0.78
	_root.add_child(frame)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.10, 0.97)
	style.border_color = Color(0.50, 0.30, 1.0, 0.9)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	frame.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	frame.add_child(vbox)

	var title: Label = Label.new()
	title.text = "ROOM ASSIGNMENT TERMINAL"
	title.add_theme_color_override("font_color", Color(0.70, 0.55, 1.0, 1.0))
	title.add_theme_font_size_override("font_size", 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var cost_lbl: Label = Label.new()
	var inv: Node = get_node_or_null("/root/Inventory")
	var held: int = inv.call("count", ProceduralShip.FLOOR_UNLOCK_ITEM) if inv != null else 0
	cost_lbl.text = "Cost: %d ship parts  (you have: %d)" % [ProceduralShip.ROOM_ASSIGN_COST, held]
	cost_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.80, 1.0))
	cost_lbl.add_theme_font_size_override("font_size", 14)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cost_lbl)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# One button per assignable type.
	var can_afford: bool = (held >= ProceduralShip.ROOM_ASSIGN_COST)
	for type_row in ProceduralShip.assignable_types():
		var d: Dictionary = type_row
		var type_id: String = String(d.get("id", ""))
		var display: String = String(d.get("display_name", type_id))
		var btn: Button = Button.new()
		btn.text = display
		btn.custom_minimum_size = Vector2(0, 40)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 16)
		btn.disabled = not can_afford
		btn.pressed.connect(_on_assign_button.bind(type_id))
		vbox.add_child(btn)

	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn: Button = Button.new()
	close_btn.text = "CANCEL"
	close_btn.custom_minimum_size = Vector2(0, 38)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_close_menu)
	vbox.add_child(close_btn)


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_close_menu()


func _on_assign_button(type_id: String) -> void:
	var ok: bool = ProceduralShip.assign_function(console_room_id, type_id)
	if not ok:
		# Not enough parts or invalid assignment — refresh without closing.
		_close_menu()
		if _layer != null:
			_layer.queue_free()
			_layer = null
			_root = null
		_open = false
		return
	_close_menu()
	# Reload the room so RoomBuilder rebuilds with the new template.
	GameState.next_room_id = console_room_id
	var router: Node = get_node_or_null("/root/SceneRouter")
	if router != null:
		router.call("change_to", "res://scenes/room.tscn", "")
