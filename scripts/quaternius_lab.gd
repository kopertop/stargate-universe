extends Node3D

# Quaternius Character Builder — interactive WoW-style gear lab over
# ModularCharacter (Universal Base + Modular Outfits, humanoid-retargeted).
# Body regions hide under equipped parts (no clip-through); rifle mounts
# hand (aimed) or back (slung); shared Mixamo crew animations.
# Launch standalone:
#   godot --path . scenes/quaternius_lab.tscn

const ModularScript: Script = preload("res://scripts/modular_character.gd")

var _char: Node3D = null
var _cam: Camera3D = null
var _cam_yaw: float = 0.25
var _cam_pitch: float = 0.25
var _cam_dist: float = 3.2
var _orbiting: bool = false
var _turntable: bool = false

var _base_pick: OptionButton
var _anim_pick: OptionButton
var _slot_picks: Dictionary = {}
var _rifle_box: CheckBox
var _aim_box: CheckBox


func _ready() -> void:
	_build_stage()
	_build_ui()
	_rebuild_character()


func _process(delta: float) -> void:
	if _turntable and _char != null:
		_char.rotation.y += delta * 0.7
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = maxf(1.0, _cam_dist - 0.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(7.0, _cam_dist + 0.2)
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event
		_cam_yaw -= mm.relative.x * 0.008
		_cam_pitch = clampf(_cam_pitch + mm.relative.y * 0.006, -0.2, 1.2)


func _build_stage() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.15, 0.19)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.4, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.5, 0.0)
	fill.light_energy = 0.4
	add_child(fill)
	var disc: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 1.2
	cyl.bottom_radius = 1.2
	cyl.height = 0.06
	disc.mesh = cyl
	disc.position.y = -0.03
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.22, 0.24, 0.28)
	disc.material_override = fmat
	add_child(disc)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.current = true
	_update_camera()


func _update_camera() -> void:
	var target: Vector3 = Vector3(0.0, 1.0, 0.0)
	var off: Vector3 = Vector3(
		sin(_cam_yaw) * cos(_cam_pitch),
		sin(_cam_pitch),
		cos(_cam_yaw) * cos(_cam_pitch)) * _cam_dist
	_cam.position = target + off
	_cam.look_at(target, Vector3.UP)


func _gender() -> String:
	return "Male" if _base_pick.selected == 0 else "Female"


func _rebuild_character() -> void:
	if _char != null:
		_char.queue_free()
	_char = ModularScript.create(_gender())
	add_child(_char)
	_refresh_slot_items()
	_refresh_anim_list()
	_apply_all_slots()
	_apply_rifle()


func _refresh_slot_items() -> void:
	for slot in ModularScript.SLOTS:
		var pick: OptionButton = _slot_picks[slot]
		var prev: String = pick.get_item_text(pick.selected) if pick.selected >= 0 else ""
		pick.clear()
		pick.add_item("(none)")
		for stem in ModularScript.parts_for_slot(slot, _gender()):
			pick.add_item(stem)
		var want: String = prev.replace("Female", "@").replace("Male", "Female").replace("@", "Male") if not prev.begins_with(_gender()) else prev
		for i in range(pick.item_count):
			if pick.get_item_text(i) == prev or pick.get_item_text(i) == want:
				pick.select(i)
				break


func _apply_all_slots() -> void:
	for slot in ModularScript.SLOTS:
		_apply_slot(slot)


func _apply_slot(slot: String) -> void:
	if _char == null:
		return
	var pick: OptionButton = _slot_picks[slot]
	var stem: String = "" if pick.selected <= 0 else pick.get_item_text(pick.selected)
	_char.call("set_slot", slot, stem)


func _apply_rifle() -> void:
	if _char != null:
		_char.call("set_rifle", _rifle_box.button_pressed, _aim_box.button_pressed)
		if _aim_box.button_pressed and _rifle_box.button_pressed:
			_char.call("play_clip", "rifle_aim")


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(290, 0)
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "QUATERNIUS BUILDER"
	box.add_child(title)

	_base_pick = OptionButton.new()
	_base_pick.add_item("Male base")
	_base_pick.add_item("Female base")
	_base_pick.item_selected.connect(func(_i: int) -> void: _rebuild_character())
	box.add_child(_base_pick)

	_anim_pick = OptionButton.new()
	_anim_pick.item_selected.connect(_on_anim_selected)
	box.add_child(_anim_pick)

	box.add_child(HSeparator.new())
	var lbl: Label = Label.new()
	lbl.text = "Equipment slots (hides body under gear)"
	lbl.add_theme_font_size_override("font_size", 12)
	box.add_child(lbl)
	for slot in ModularScript.SLOTS:
		var row: HBoxContainer = HBoxContainer.new()
		var slbl: Label = Label.new()
		slbl.text = slot
		slbl.custom_minimum_size = Vector2(46, 0)
		row.add_child(slbl)
		var pick: OptionButton = OptionButton.new()
		pick.custom_minimum_size = Vector2(220, 0)
		pick.add_item("(none)")
		pick.item_selected.connect(func(_i: int, s: String = slot) -> void: _apply_slot(s))
		row.add_child(pick)
		box.add_child(row)
		_slot_picks[slot] = pick

	box.add_child(HSeparator.new())
	_rifle_box = CheckBox.new()
	_rifle_box.text = "Rifle"
	_rifle_box.toggled.connect(func(_on: bool) -> void: _apply_rifle())
	box.add_child(_rifle_box)
	_aim_box = CheckBox.new()
	_aim_box.text = "Aim (hand; off = slung on back)"
	_aim_box.toggled.connect(func(_on: bool) -> void: _apply_rifle())
	box.add_child(_aim_box)

	var turn: CheckBox = CheckBox.new()
	turn.text = "Turntable"
	turn.toggled.connect(func(on: bool) -> void: _turntable = on)
	box.add_child(turn)
	var hint: Label = Label.new()
	hint.text = "drag: orbit   wheel: zoom"
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)


func _refresh_anim_list() -> void:
	_anim_pick.clear()
	var clips: PackedStringArray = _char.call("clip_names")
	if clips.is_empty():
		_anim_pick.add_item("(no animations)")
		return
	var idle_idx: int = 0
	for i in range(clips.size()):
		_anim_pick.add_item(clips[i])
		if clips[i] == "idle":
			idle_idx = i
	_anim_pick.select(idle_idx)
	_on_anim_selected(idle_idx)


func _on_anim_selected(idx: int) -> void:
	if _char != null and idx >= 0:
		_char.call("play_clip", _anim_pick.get_item_text(idx))
