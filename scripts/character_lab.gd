extends Node3D

# Character Lab — standalone VRoid-style character editor / test bench.
#
# Launch it alone (no game state needed):
#   godot scenes/character_lab.tscn          # CLI
#   F6 on the scene in the editor
#
# Pick a crew member, flip between ship/mission contexts, toggle gear, and
# live-tweak garment colors. "Print snippet" dumps a paste-ready recolor dict
# to the console for promoting a tweak into CharacterFactory.OUTFITS — the lab
# itself never writes files.

const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const ROLE_ORDER: Array[String] = ["top", "bottom", "shoes", "limbs", "accent"]

var _actor: Node3D = null
var _model_holder: Node3D = null
var _anim: AnimationPlayer = null
var _cam: Camera3D = null
var _cam_yaw: float = 0.35
var _cam_pitch: float = 0.42
var _cam_dist: float = 5.0
var _orbiting: bool = false
var _turntable: bool = false

var _char_pick: OptionButton
var _ctx_pick: OptionButton
var _anim_pick: OptionButton
var _gear_boxes: Dictionary = {}      # gear id -> CheckBox
var _custom_toggle: CheckBox
var _role_pickers: Dictionary = {}    # role -> ColorPickerButton
var _turn_toggle: CheckBox


func _ready() -> void:
	_build_stage()
	_build_ui()
	_rebuild_actor()


func _process(delta: float) -> void:
	if _turntable and _actor != null:
		_actor.rotation.y += delta * 0.8
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = maxf(2.0, _cam_dist - 0.3)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(10.0, _cam_dist + 0.3)
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		_cam_yaw -= mm.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.006, 0.05, 1.35)


# ------------------------------- stage --------------------------------------

func _build_stage() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.15, 0.19)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.1
	env.environment = e
	add_child(env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.5, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, 2.4, 0.0)
	fill.light_energy = 0.45
	add_child(fill)

	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.08
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.04
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.22, 0.24, 0.28)
	floor_mesh.material_override = fmat
	add_child(floor_mesh)

	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)
	_cam.current = true
	_update_camera()


func _update_camera() -> void:
	if _cam == null:
		return
	var target: Vector3 = Vector3(0.0, 1.0, 0.0)
	var off: Vector3 = Vector3(
		sin(_cam_yaw) * cos(_cam_pitch),
		sin(_cam_pitch),
		cos(_cam_yaw) * cos(_cam_pitch)) * _cam_dist
	_cam.position = target + off
	_cam.look_at(target, Vector3.UP)


# ------------------------------- actor --------------------------------------

func _selected_character() -> String:
	return _char_pick.get_item_text(_char_pick.selected)


func _selected_context() -> String:
	return FactoryRef.CTX_SHIP if _ctx_pick.selected == 0 else FactoryRef.CTX_MISSION


func _rebuild_actor() -> void:
	if _actor != null:
		_actor.queue_free()
	_actor = Node3D.new()
	_actor.name = "Actor"
	add_child(_actor)

	_model_holder = Node3D.new()
	_model_holder.name = "Model"
	_model_holder.scale = Vector3(2.6, 2.6, 2.6)
	_model_holder.rotation.y = PI
	_actor.add_child(_model_holder)

	var character_name: String = _selected_character()
	var glb: PackedScene = load(FactoryRef.model_for(character_name))
	_anim = null
	if glb != null:
		var inst: Node = glb.instantiate()
		_model_holder.add_child(inst)
		_anim = _find_anim(inst)
	FactoryRef.dress(_actor, _model_holder, character_name, _selected_context())
	if _custom_toggle.button_pressed:
		_apply_custom_colors()
	_refresh_gear_boxes()
	_refresh_anim_list()
	_refresh_role_pickers()


func _find_anim(node: Node) -> AnimationPlayer:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


# --------------------------------- UI ---------------------------------------

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(250, 0)
	layer.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "CHARACTER LAB"
	box.add_child(title)

	_char_pick = OptionButton.new()
	for character_name in FactoryRef.PROFILES:
		_char_pick.add_item(character_name)
	_char_pick.item_selected.connect(func(_i: int) -> void: _rebuild_actor())
	box.add_child(_char_pick)

	_ctx_pick = OptionButton.new()
	_ctx_pick.add_item("Ship")
	_ctx_pick.add_item("Mission")
	_ctx_pick.item_selected.connect(func(_i: int) -> void: _rebuild_actor())
	box.add_child(_ctx_pick)

	box.add_child(HSeparator.new())
	var gear_label: Label = Label.new()
	gear_label.text = "Gear"
	box.add_child(gear_label)
	for gear_id in ["sidearm", "rifle", "helmet"]:
		var cb: CheckBox = CheckBox.new()
		cb.text = gear_id.capitalize()
		cb.toggled.connect(_on_gear_toggled.bind(gear_id))
		box.add_child(cb)
		_gear_boxes[gear_id] = cb

	box.add_child(HSeparator.new())
	_custom_toggle = CheckBox.new()
	_custom_toggle.text = "Override colors"
	_custom_toggle.toggled.connect(func(_on: bool) -> void: _rebuild_actor())
	box.add_child(_custom_toggle)
	for role in ROLE_ORDER:
		var row: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = role
		lbl.custom_minimum_size = Vector2(70, 0)
		row.add_child(lbl)
		var picker: ColorPickerButton = ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(110, 24)
		picker.color = Color(0.5, 0.5, 0.5)
		picker.color_changed.connect(func(_c: Color) -> void:
			if _custom_toggle.button_pressed:
				_apply_custom_colors())
		row.add_child(picker)
		box.add_child(row)
		_role_pickers[role] = picker

	var snippet: Button = Button.new()
	snippet.text = "Print snippet"
	snippet.pressed.connect(_print_snippet)
	box.add_child(snippet)

	box.add_child(HSeparator.new())
	_anim_pick = OptionButton.new()
	_anim_pick.item_selected.connect(_on_anim_selected)
	box.add_child(_anim_pick)

	_turn_toggle = CheckBox.new()
	_turn_toggle.text = "Turntable"
	_turn_toggle.toggled.connect(func(on: bool) -> void: _turntable = on)
	box.add_child(_turn_toggle)

	var hint: Label = Label.new()
	hint.text = "drag: orbit   wheel: zoom"
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)


func _on_gear_toggled(on: bool, gear_id: String) -> void:
	if _actor == null:
		return
	var node_name: String = gear_id.capitalize()
	var existing: Node = _actor.get_node_or_null(node_name)
	if on and existing == null:
		FactoryRef.add_gear(_actor, gear_id)
	elif not on and existing != null:
		existing.name = node_name + "_retired"
		existing.queue_free()


func _refresh_gear_boxes() -> void:
	for gear_id in _gear_boxes:
		var cb: CheckBox = _gear_boxes[gear_id]
		cb.set_pressed_no_signal(_actor.get_node_or_null(String(gear_id).capitalize()) != null)


func _refresh_anim_list() -> void:
	_anim_pick.clear()
	if _anim == null:
		_anim_pick.add_item("(no animations)")
		return
	var names: PackedStringArray = _anim.get_animation_list()
	var idle_idx: int = 0
	for i in range(names.size()):
		_anim_pick.add_item(String(names[i]))
		if String(names[i]).to_lower().contains("idle"):
			idle_idx = i
	_anim_pick.select(idle_idx)
	_on_anim_selected(idle_idx)


func _on_anim_selected(idx: int) -> void:
	if _anim == null:
		return
	var clip: String = _anim_pick.get_item_text(idx)
	if _anim.has_animation(clip):
		var a: Animation = _anim.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR
		_anim.play(clip)


# Seed pickers from the active outfit's recolor so "Override colors" starts
# from what's on screen instead of gray.
func _refresh_role_pickers() -> void:
	var outfit_id: String = FactoryRef.outfit_id_for(_selected_character(), _selected_context())
	var outfit: Dictionary = FactoryRef.OUTFITS.get(outfit_id, {})
	var recolor: Dictionary = outfit.get("recolor", {})
	for role in ROLE_ORDER:
		if recolor.has(role):
			(_role_pickers[role] as ColorPickerButton).color = recolor[role]


func _current_custom_recolor() -> Dictionary:
	var stem: String = String(FactoryRef.profile_for(_selected_character())["model"])
	var groups: Dictionary = FactoryRef.SWATCH_GROUPS.get(stem, {})
	var recolor: Dictionary = {}
	for role in ROLE_ORDER:
		if groups.has(role) and not (groups[role] as Array).is_empty():
			recolor[role] = (_role_pickers[role] as ColorPickerButton).color
	return recolor


func _apply_custom_colors() -> void:
	var stem: String = String(FactoryRef.profile_for(_selected_character())["model"])
	FactoryRef.apply_texture(_model_holder, FactoryRef.custom_texture(stem, _current_custom_recolor()))


func _print_snippet() -> void:
	var recolor: Dictionary = _current_custom_recolor()
	var lines: Array[String] = []
	for role in recolor:
		var c: Color = recolor[role]
		lines.append('\t\t"%s": Color(%.2f, %.2f, %.2f),' % [role, c.r, c.g, c.b])
	print("[character_lab] %s / %s recolor snippet for CharacterFactory.OUTFITS:" % [
		_selected_character(), _selected_context()])
	print('\t"recolor": {\n%s\n\t},' % "\n".join(lines))
