extends Node3D

# VRM Lab — the VRoid-style character studio over the VRM pipeline.
# Launch standalone:
#   godot --path . scenes/vrm_lab.tscn       (or F6 in the editor)
#
# Everything the pipeline supports, live: body animations (retargeted Mixamo),
# emotions with weight, visemes (lip-sync preview), auto/manual blink, gaze,
# bone-snapped gear with aim routing, spring-bone hair physics, turntable.

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")
const GearLib: Script = preload("res://scripts/vrm_gear_library.gd")

const VRM_DIR: String = "res://models/vrm"
const MESH_SLOTS: Array[String] = ["chest", "legs", "feet"]

var _char: Node3D = null
var _cam: Camera3D = null
var _cam_yaw: float = 0.2
var _cam_pitch: float = 0.25
var _cam_dist: float = 2.6
var _orbiting: bool = false
var _turntable: bool = false

var _char_pick: OptionButton
var _anim_pick: OptionButton
var _emotion_slider: HSlider
var _viseme_slider: HSlider
var _gaze_h: HSlider
var _gaze_v: HSlider
var _autoblink_toggle: CheckBox
var _aim_toggle: CheckBox
var _gear_boxes: Dictionary = {}
var _slot_picks: Dictionary = {}   # slot -> OptionButton
var _emotion: String = "neutral"
var _viseme: String = ""


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
			_cam_dist = maxf(0.8, _cam_dist - 0.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(6.0, _cam_dist + 0.15)
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
	sun.light_energy = 1.15
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
	var target: Vector3 = Vector3(0.0, 1.05, 0.0)
	var off: Vector3 = Vector3(
		sin(_cam_yaw) * cos(_cam_pitch),
		sin(_cam_pitch),
		cos(_cam_yaw) * cos(_cam_pitch)) * _cam_dist
	_cam.position = target + off
	_cam.look_at(target, Vector3.UP)


func _vrm_files() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(VRM_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".vrm"):
			out.append(f.get_basename())
	return out


func _rebuild_character() -> void:
	if _char != null:
		_char.queue_free()
	var stem: String = _char_pick.get_item_text(_char_pick.selected)
	_char = VrmCharacterScript.create("%s/%s.vrm" % [VRM_DIR, stem], stem)
	add_child(_char)
	_char.set("auto_blink", _autoblink_toggle.button_pressed)
	for slot in _slot_picks:
		(_slot_picks[slot] as OptionButton).select(0)
	_refresh_anim_list()
	_apply_expression_ui()
	for gear_id in _gear_boxes:
		if (_gear_boxes[gear_id] as CheckBox).button_pressed:
			_char.call("attach_gear", gear_id, _aim_toggle.button_pressed)


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(270, 0)
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "VRM LAB"
	box.add_child(title)

	_char_pick = OptionButton.new()
	for stem in _vrm_files():
		_char_pick.add_item(stem)
	_char_pick.item_selected.connect(func(_i: int) -> void: _rebuild_character())
	box.add_child(_char_pick)

	_anim_pick = OptionButton.new()
	_anim_pick.item_selected.connect(_on_anim_selected)
	box.add_child(_anim_pick)

	box.add_child(HSeparator.new())
	box.add_child(_label("Emotion"))
	var em_row: HBoxContainer = HBoxContainer.new()
	for emo in ["neutral", "happy", "angry", "sad", "relaxed", "surprised"]:
		var b: Button = Button.new()
		b.text = emo.left(4)
		b.tooltip_text = emo
		b.pressed.connect(_on_emotion.bind(emo))
		em_row.add_child(b)
	box.add_child(em_row)
	_emotion_slider = _slider(box, 1.0)
	_emotion_slider.value_changed.connect(func(_v: float) -> void: _apply_expression_ui())

	box.add_child(_label("Viseme (lip sync)"))
	var vi_row: HBoxContainer = HBoxContainer.new()
	for vis in ["-", "aa", "ih", "ou", "ee", "oh"]:
		var b: Button = Button.new()
		b.text = vis
		b.pressed.connect(_on_viseme.bind(vis))
		vi_row.add_child(b)
	box.add_child(vi_row)
	_viseme_slider = _slider(box, 1.0)
	_viseme_slider.value_changed.connect(func(_v: float) -> void: _apply_expression_ui())

	box.add_child(_label("Gaze  (h / v)"))
	_gaze_h = _slider(box, 0.0, -1.0)
	_gaze_v = _slider(box, 0.0, -1.0)
	_gaze_h.value_changed.connect(func(_v: float) -> void: _apply_expression_ui())
	_gaze_v.value_changed.connect(func(_v: float) -> void: _apply_expression_ui())

	_autoblink_toggle = CheckBox.new()
	_autoblink_toggle.text = "Auto blink"
	_autoblink_toggle.button_pressed = true
	_autoblink_toggle.toggled.connect(func(on: bool) -> void:
		if _char != null:
			_char.set("auto_blink", on))
	box.add_child(_autoblink_toggle)

	box.add_child(HSeparator.new())
	box.add_child(_label("Equipment (WoW slots — swap in code)"))
	for slot in MESH_SLOTS:
		var row: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = slot
		lbl.custom_minimum_size = Vector2(48, 0)
		row.add_child(lbl)
		var pick: OptionButton = OptionButton.new()
		pick.custom_minimum_size = Vector2(180, 0)
		pick.add_item("(own)")
		for item_id in GearLib.items_for_slot(slot):
			pick.add_item(item_id)
		pick.item_selected.connect(_on_slot_item.bind(slot))
		row.add_child(pick)
		box.add_child(row)
		_slot_picks[slot] = pick

	box.add_child(HSeparator.new())
	box.add_child(_label("Gear (bone snap points)"))
	for gear_id in ["helmet", "rifle", "sidearm"]:
		var cb: CheckBox = CheckBox.new()
		cb.text = gear_id.capitalize()
		cb.toggled.connect(_on_gear_toggled.bind(gear_id))
		box.add_child(cb)
		_gear_boxes[gear_id] = cb
	_aim_toggle = CheckBox.new()
	_aim_toggle.text = "Aim (weapon to hand)"
	_aim_toggle.toggled.connect(_on_aim_toggled)
	box.add_child(_aim_toggle)

	box.add_child(HSeparator.new())
	var turn: CheckBox = CheckBox.new()
	turn.text = "Turntable"
	turn.toggled.connect(func(on: bool) -> void: _turntable = on)
	box.add_child(turn)
	var hint: Label = Label.new()
	hint.text = "drag: orbit   wheel: zoom"
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)


func _label(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	return l


func _slider(parent: Control, value: float, minv: float = 0.0) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = minv
	s.max_value = 1.0
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(240, 18)
	parent.add_child(s)
	return s


func _refresh_anim_list() -> void:
	_anim_pick.clear()
	if _char == null:
		return
	var clips: PackedStringArray = _char.call("clip_names")
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


func _on_emotion(emotion: String) -> void:
	_emotion = emotion
	_apply_expression_ui()


func _on_viseme(viseme: String) -> void:
	_viseme = "" if viseme == "-" else viseme
	_apply_expression_ui()


func _apply_expression_ui() -> void:
	if _char == null:
		return
	_char.call("set_emotion", _emotion, _emotion_slider.value)
	if _viseme == "":
		_char.call("set_viseme", "aa", 0.0)
	else:
		_char.call("set_viseme", _viseme, _viseme_slider.value)
	_char.call("set_gaze", _gaze_h.value, _gaze_v.value)


func _on_slot_item(idx: int, slot: String) -> void:
	if _char == null:
		return
	var pick: OptionButton = _slot_picks[slot]
	if idx == 0:
		_char.call("unequip", slot)
	else:
		_char.call("equip", pick.get_item_text(idx))


func _on_gear_toggled(on: bool, gear_id: String) -> void:
	if _char == null:
		return
	if on:
		_char.call("attach_gear", gear_id, _aim_toggle.button_pressed)
	else:
		_char.call("remove_gear", gear_id)


func _on_aim_toggled(on: bool) -> void:
	if _char == null:
		return
	for gear_id in ["rifle", "sidearm"]:
		if bool(_char.call("has_gear", gear_id)):
			_char.call("remove_gear", gear_id)
			_char.call("attach_gear", gear_id, on and gear_id == _primary_weapon())
	if on:
		_char.call("play_clip", "rifle_run_aim" if bool(_char.call("has_gear", "rifle")) else "idle")


func _primary_weapon() -> String:
	if (_gear_boxes["rifle"] as CheckBox).button_pressed:
		return "rifle"
	if (_gear_boxes["sidearm"] as CheckBox).button_pressed:
		return "sidearm"
	return ""
