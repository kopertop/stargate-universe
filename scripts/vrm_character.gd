extends Node3D
class_name VrmCharacter

# Runtime brain for a VRoid/VRM crew member. Wraps an instanced .vrm scene
# (godot-vrm import: %GeneralSkeleton + AnimationPlayer of expression clips +
# spring-bone `secondary`) and provides:
#
#   - body animation from the shared retargeted Mixamo library
#     (res://models/vrm/anim/crew_body.res): play_clip("walk"), crossfades
#   - EXPRESSION CHANNELS mixed simultaneously every frame — emotion
#     (happy/angry/sad/relaxed/surprised), blink (with auto-blink), viseme
#     (aa/ih/ou/ee/oh for lip sync), and gaze (lookLeft/Right/Up/Down) —
#     by sampling the imported expression Animations' blend-shape tracks
#     (each clip is a linear 0->1 ramp, so sample time == weight)
#   - gear snap points on humanoid bones via BoneAttachment3D
#     (helmet->Head, rifle->Chest (back) or RightHand, sidearm->Hips/RightHand)
#   - spring bones (hair/cloth) run automatically via the addon's secondary
#
# Usage:
#   var c := VrmCharacter.create("res://models/vrm/eli.vrm")
#   add_child(c)
#   c.play_clip("walk"); c.set_emotion("happy", 0.8); c.attach_gear("rifle")

const BODY_LIB_PATH: String = "res://models/vrm/anim/crew_body.res"
const FactoryRef: Script = preload("res://scripts/character_factory.gd")

const EMOTIONS: Array[String] = ["happy", "angry", "sad", "relaxed", "surprised", "neutral"]
const VISEMES: Array[String] = ["aa", "ih", "ou", "ee", "oh"]

# Humanoid-bone snap points (offsets in meters — VRM is real-world scale).
# Tuned visually via tests/capture/vrm_gear_debug.gd.
const MOUNTS: Dictionary = {
	"head":   {"bone": "Head",      "pos": Vector3(0.0, 0.105, 0.01),   "rot": Vector3(0.0, 0.0, 0.0)},
	"back":   {"bone": "Chest",     "pos": Vector3(-0.04, 0.10, -0.16), "rot": Vector3(-1.25, 0.0, 0.85)},
	"belt":   {"bone": "Hips",      "pos": Vector3(0.17, -0.04, -0.02), "rot": Vector3(-1.57, 0.0, 0.0)},
	# Hand bones run +Y along the fingers; Rx(+90deg) lays the barrel (-Z in
	# gear frame) along the pointing direction.
	"hand_r": {"bone": "RightHand", "pos": Vector3(0.0, 0.08, -0.02),   "rot": Vector3(1.57, 0.0, 0.0)},
	"hand_l": {"bone": "LeftHand",  "pos": Vector3(0.0, 0.08, -0.02),   "rot": Vector3(1.57, 0.0, 0.0)},
}
const GEAR_MOUNT: Dictionary = {"helmet": "head", "rifle": "back", "sidearm": "belt"}
const GEAR_MOUNT_AIMED: Dictionary = {"rifle": "hand_r", "sidearm": "hand_r"}
# The factory's procedural gear is proportioned for the chunky minis; shrink
# to read correctly against real human anatomy.
const GEAR_SCALE: Dictionary = {"helmet": 0.40, "rifle": 0.80, "sidearm": 0.38}

var character_name: String = ""
var auto_blink: bool = true

var _model: Node3D = null
var _skel: Skeleton3D = null
var _anim: AnimationPlayer = null
var _expr_clips: Dictionary = {}          # expression name -> Animation
var _channels: Dictionary = {}            # channel -> {"expr": String, "weight": float}
var _face_meshes: Array[MeshInstance3D] = []
var _blink_timer: float = 0.0
var _blink_phase: float = -1.0            # <0 idle; 0..1 = blink progress


# Returns a VrmCharacter (typed Node3D so a cold headless load never has to
# resolve our own class_name — the known same-run registration trap).
static func create(vrm_path: String, display_name: String = "") -> Node3D:
	var c: Node3D = new()
	c.character_name = display_name if display_name != "" else vrm_path.get_file().get_basename()
	c.name = "Vrm_" + c.character_name.replace(" ", "")
	var packed: PackedScene = load(vrm_path)
	if packed != null:
		c._model = packed.instantiate()
		c.add_child(c._model)
	return c


func _ready() -> void:
	if _model == null and get_child_count() > 0:
		_model = get_child(0) as Node3D
	if _model == null:
		return
	_skel = _model.get_node_or_null("%GeneralSkeleton") as Skeleton3D
	if _skel == null:
		_skel = _find_skeleton(_model)
	_anim = _model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim != null:
		# Keep a handle on every expression clip, then make the player safe to
		# use for BODY animation only (expressions are mixed manually).
		for n in _anim.get_animation_list():
			_expr_clips[String(n)] = _anim.get_animation(n)
		if not _anim.has_animation_library("body") and ResourceLoader.exists(BODY_LIB_PATH):
			_anim.add_animation_library("body", load(BODY_LIB_PATH))
		play_clip("idle")
	for mesh in _collect_meshes():
		if mesh.mesh != null and mesh.mesh is ArrayMesh and (mesh.mesh as ArrayMesh).get_blend_shape_count() > 0:
			_face_meshes.append(mesh)


# ------------------------------ body animation ------------------------------

func play_clip(clip: String, blend: float = 0.3) -> void:
	if _anim == null:
		return
	var full: String = "body/" + clip if _anim.has_animation("body/" + clip) else clip
	if _anim.has_animation(full):
		_anim.play(full, blend)


func clip_names() -> PackedStringArray:
	var out: PackedStringArray = []
	if _anim != null and _anim.has_animation_library("body"):
		out = _anim.get_animation_library("body").get_animation_list()
	return out


# ------------------------------- expressions --------------------------------

# Set one of the mutually-blended emotion expressions (weight 0 clears).
func set_emotion(emotion: String, weight: float = 1.0) -> void:
	_channels["emotion"] = {"expr": emotion, "weight": clampf(weight, 0.0, 1.0)}


func set_viseme(viseme: String, weight: float = 1.0) -> void:
	_channels["viseme"] = {"expr": viseme, "weight": clampf(weight, 0.0, 1.0)}


func set_blink(weight: float) -> void:
	_channels["blink"] = {"expr": "blink", "weight": clampf(weight, 0.0, 1.0)}


# Gaze via the look* expression clips (bone or blendshape based, both sampled).
func set_gaze(horizontal: float, vertical: float) -> void:
	_channels["gaze_h"] = {
		"expr": "lookRight" if horizontal >= 0.0 else "lookLeft",
		"weight": clampf(absf(horizontal), 0.0, 1.0)}
	_channels["gaze_v"] = {
		"expr": "lookUp" if vertical >= 0.0 else "lookDown",
		"weight": clampf(absf(vertical), 0.0, 1.0)}


func clear_expressions() -> void:
	_channels.clear()


func expression_names() -> Array:
	return _expr_clips.keys()


func _process(delta: float) -> void:
	if auto_blink:
		_tick_autoblink(delta)
	_mix_face()


func _tick_autoblink(delta: float) -> void:
	if _blink_phase >= 0.0:
		_blink_phase += delta * 8.0          # ~0.12s blink
		if _blink_phase >= 1.0:
			_blink_phase = -1.0
			set_blink(0.0)
		else:
			# down fast, up slower
			var w: float = sin(_blink_phase * PI)
			set_blink(w)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_timer = randf_range(2.0, 5.0)
			_blink_phase = 0.0


# Mix all active expression channels into blend-shape values each frame.
# Expression clips ramp linearly 0->1 over one time unit, so sampling a track
# at t=weight yields that weight's pose; channels ACCUMULATE (capped at 1).
func _mix_face() -> void:
	if _face_meshes.is_empty():
		return
	var acc: Dictionary = {}   # mesh -> {blendshape idx -> value}
	for channel in _channels:
		var expr: String = _channels[channel]["expr"]
		var w: float = _channels[channel]["weight"]
		if w <= 0.001 or not _expr_clips.has(expr):
			continue
		var anim: Animation = _expr_clips[expr]
		for t in range(anim.get_track_count()):
			if anim.track_get_type(t) != Animation.TYPE_BLEND_SHAPE:
				continue
			var path: String = String(anim.track_get_path(t))
			var parts: PackedStringArray = path.split(":")
			if parts.size() < 2:
				continue
			for mesh in _face_meshes:
				if mesh.name != parts[0].get_file() and not parts[0].ends_with(String(mesh.name)):
					continue
				var idx: int = mesh.find_blend_shape_by_name(parts[1])
				if idx < 0:
					continue
				var v: float = anim.blend_shape_track_interpolate(t, clampf(w, 0.0, 0.999))
				if not acc.has(mesh):
					acc[mesh] = {}
				acc[mesh][idx] = clampf(float(acc[mesh].get(idx, 0.0)) + v, 0.0, 1.0)
	for mesh in _face_meshes:
		var values: Dictionary = acc.get(mesh, {})
		for i in range((mesh.mesh as ArrayMesh).get_blend_shape_count()):
			mesh.set_blend_shape_value(i, float(values.get(i, 0.0)))


# ---------------------------------- gear ------------------------------------

# Same snap-point contract as the mini pipeline: gear rides BoneAttachment3D
# on the humanoid skeleton. aimed routes weapons to the right hand.
func attach_gear(gear_id: String, aimed: bool = false) -> Node3D:
	if _skel == null:
		return null
	var node_name: String = gear_id.capitalize()
	var mount_name: String = GEAR_MOUNT_AIMED[gear_id] if (aimed and GEAR_MOUNT_AIMED.has(gear_id)) else String(GEAR_MOUNT.get(gear_id, "head"))
	var mount: Dictionary = MOUNTS[mount_name]
	var attach: BoneAttachment3D = _bone_attachment(String(mount["bone"]))
	var existing: Node = attach.get_node_or_null(node_name)
	if existing != null:
		return existing as Node3D
	remove_gear(gear_id)
	var gear: Node3D = null
	match gear_id:
		"sidearm": gear = FactoryRef.build_sidearm()
		"rifle":   gear = FactoryRef.build_rifle()
		"helmet":  gear = FactoryRef.build_helmet()
	if gear == null:
		return null
	gear.name = node_name
	gear.position = mount["pos"]
	gear.rotation = mount["rot"]
	gear.scale = Vector3.ONE * float(GEAR_SCALE.get(gear_id, 1.0))
	attach.add_child(gear)
	return gear


func remove_gear(gear_id: String) -> void:
	if _skel == null:
		return
	var node_name: String = gear_id.capitalize()
	for ba in _skel.get_children():
		if ba is BoneAttachment3D:
			var g: Node = ba.get_node_or_null(node_name)
			if g != null:
				g.name = node_name + "_retired"
				g.queue_free()


func has_gear(gear_id: String) -> bool:
	if _skel == null:
		return false
	var node_name: String = gear_id.capitalize()
	for ba in _skel.get_children():
		if ba is BoneAttachment3D and ba.get_node_or_null(node_name) != null:
			return true
	return false


func _bone_attachment(bone_name: String) -> BoneAttachment3D:
	var attach_name: String = "Mount_" + bone_name
	var existing: Node = _skel.get_node_or_null(attach_name)
	if existing is BoneAttachment3D:
		return existing
	var ba: BoneAttachment3D = BoneAttachment3D.new()
	ba.name = attach_name
	_skel.add_child(ba)
	ba.bone_name = bone_name
	return ba


# --------------------------------- helpers ----------------------------------

func skeleton() -> Skeleton3D:
	return _skel


func _collect_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array = [_model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
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
