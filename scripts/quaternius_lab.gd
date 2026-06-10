extends Node3D

# Quaternius Character Builder — interactive modular-outfit lab for the
# experiment branch. Universal Base body + per-slot outfit parts + rigged
# hairstyles, all assembled in code on one %GeneralSkeleton, driven by the
# shared Mixamo crew animation library.
# Launch standalone:
#   godot --path . scenes/quaternius_lab.tscn

const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const BASE_DIR: String = "res://models/quaternius/base"
const PARTS_DIR: String = "res://models/quaternius/parts"
const HAIR_DIR: String = "res://models/quaternius/hair"
const BODY_LIB: String = "res://models/vrm/anim/crew_body.res"
const SLOT_ORDER: Array[String] = ["Body", "Arms", "Legs", "Feet", "Head", "Acc", "Hair"]

var _base: Node3D = null
var _skel: Skeleton3D = null
var _anim: AnimationPlayer = null
var _worn: Dictionary = {}            # slot -> Array[Node] currently equipped
var _cam: Camera3D = null
var _cam_yaw: float = 0.25
var _cam_pitch: float = 0.25
var _cam_dist: float = 3.2
var _orbiting: bool = false
var _turntable: bool = false

var _base_pick: OptionButton
var _anim_pick: OptionButton
var _slot_picks: Dictionary = {}      # slot -> OptionButton
var _rifle_box: CheckBox


func _ready() -> void:
	_build_stage()
	_build_ui()
	_rebuild_base()


func _process(delta: float) -> void:
	if _turntable and _base != null:
		_base.rotation.y += delta * 0.7
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


# ------------------------------- stage ---------------------------------------

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


# ----------------------------- assembly --------------------------------------

func _gender() -> String:
	return "Male" if _base_pick.selected == 0 else "Female"


func _rebuild_base() -> void:
	if _base != null:
		_base.queue_free()
	_worn.clear()
	var path: String = "%s/Superhero_%s_FullBody.gltf" % [BASE_DIR, _gender()]
	_base = (load(path) as PackedScene).instantiate()
	add_child(_base)
	_skel = _base.get_node_or_null("%GeneralSkeleton")
	if _skel == null:
		_skel = _find_skeleton(_base)
	_anim = AnimationPlayer.new()
	_base.add_child(_anim)
	_anim.root_node = _anim.get_path_to(_base)
	if ResourceLoader.exists(BODY_LIB):
		_anim.add_animation_library("body", load(BODY_LIB))
	_refresh_slot_items()
	_refresh_anim_list()
	_apply_all_slots()
	_on_rifle_toggled(_rifle_box.button_pressed)


# Scan part/hair files for the current gender: slot -> [file stems].
func _parts_by_slot() -> Dictionary:
	var out: Dictionary = {}
	var dir: DirAccess = DirAccess.open(PARTS_DIR)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".gltf"):
				continue
			var stem: String = f.get_basename()
			var bits: PackedStringArray = stem.split("_")
			if bits.size() < 3 or bits[0] != _gender():
				continue
			var slot: String = bits[2]
			if not out.has(slot):
				out[slot] = []
			out[slot].append(stem)
	var hdir: DirAccess = DirAccess.open(HAIR_DIR)
	if hdir != null:
		out["Hair"] = []
		for f in hdir.get_files():
			if f.ends_with(".gltf"):
				out["Hair"].append(f.get_basename())
	return out


func _refresh_slot_items() -> void:
	var by_slot: Dictionary = _parts_by_slot()
	for slot in SLOT_ORDER:
		var pick: OptionButton = _slot_picks[slot]
		var prev: String = pick.get_item_text(pick.selected) if pick.selected >= 0 else ""
		pick.clear()
		pick.add_item("(none)")
		for stem in by_slot.get(slot, []):
			pick.add_item(stem)
		# Keep the same selection across gender swaps when possible.
		for i in range(pick.item_count):
			if pick.get_item_text(i) == prev or pick.get_item_text(i).replace("Female", "Male") == prev.replace("Female", "Male"):
				pick.select(i)
				break


func _apply_all_slots() -> void:
	for slot in SLOT_ORDER:
		_apply_slot(slot)


func _apply_slot(slot: String) -> void:
	for n in _worn.get(slot, []):
		if is_instance_valid(n):
			n.queue_free()
	_worn[slot] = []
	var pick: OptionButton = _slot_picks[slot]
	if pick.selected <= 0 or _skel == null:
		return
	var stem: String = pick.get_item_text(pick.selected)
	var dir: String = HAIR_DIR if slot == "Hair" else PARTS_DIR
	var packed: PackedScene = load("%s/%s.gltf" % [dir, stem])
	if packed == null:
		return
	var part: Node = packed.instantiate()
	for mi in _skinned_meshes(part):
		var worn: MeshInstance3D = mi.duplicate() as MeshInstance3D
		worn.name = "Part_%s_%s" % [slot, worn.name]
		_skel.add_child(worn)
		_worn[slot].append(worn)
	part.free()


func _on_rifle_toggled(on: bool) -> void:
	if _skel == null:
		return
	var existing: Node = _skel.get_node_or_null("RifleMount")
	if existing != null:
		existing.name = "RifleMount_retired"
		existing.queue_free()
	if not on:
		return
	var mount: BoneAttachment3D = BoneAttachment3D.new()
	mount.name = "RifleMount"
	_skel.add_child(mount)
	mount.bone_name = "RightHand"
	var rifle: Node3D = FactoryRef.build_rifle()
	rifle.position = Vector3(0.0, 0.08, -0.02)
	rifle.rotation = Vector3(1.57, 0.0, 0.0)
	mount.add_child(rifle)


# -------------------------------- UI ----------------------------------------

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(280, 0)
	layer.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = "QUATERNIUS BUILDER (experiment)"
	box.add_child(title)

	_base_pick = OptionButton.new()
	_base_pick.add_item("Male base")
	_base_pick.add_item("Female base")
	_base_pick.item_selected.connect(func(_i: int) -> void: _rebuild_base())
	box.add_child(_base_pick)

	_anim_pick = OptionButton.new()
	_anim_pick.item_selected.connect(_on_anim_selected)
	box.add_child(_anim_pick)

	box.add_child(HSeparator.new())
	var lbl: Label = Label.new()
	lbl.text = "Outfit slots (hot-swap in code)"
	lbl.add_theme_font_size_override("font_size", 12)
	box.add_child(lbl)
	for slot in SLOT_ORDER:
		var row: HBoxContainer = HBoxContainer.new()
		var slbl: Label = Label.new()
		slbl.text = slot
		slbl.custom_minimum_size = Vector2(46, 0)
		row.add_child(slbl)
		var pick: OptionButton = OptionButton.new()
		pick.custom_minimum_size = Vector2(210, 0)
		pick.add_item("(none)")
		pick.item_selected.connect(func(_i: int, s: String = slot) -> void: _apply_slot(s))
		row.add_child(pick)
		box.add_child(row)
		_slot_picks[slot] = pick

	box.add_child(HSeparator.new())
	_rifle_box = CheckBox.new()
	_rifle_box.text = "Rifle (RightHand bone)"
	_rifle_box.toggled.connect(_on_rifle_toggled)
	box.add_child(_rifle_box)

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
	if _anim == null or not _anim.has_animation_library("body"):
		_anim_pick.add_item("(no animations)")
		return
	var clips: PackedStringArray = _anim.get_animation_library("body").get_animation_list()
	var idle_idx: int = 0
	for i in range(clips.size()):
		_anim_pick.add_item(clips[i])
		if clips[i] == "idle":
			idle_idx = i
	_anim_pick.select(idle_idx)
	_on_anim_selected(idle_idx)


func _on_anim_selected(idx: int) -> void:
	if _anim == null or idx < 0:
		return
	var clip: String = "body/" + _anim_pick.get_item_text(idx)
	if _anim.has_animation(clip):
		_anim.play(clip)


# ------------------------------- helpers -------------------------------------

func _skinned_meshes(node: Node) -> Array:
	var out: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
