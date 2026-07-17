extends Node3D
class_name MintCharacter

# Mint-native character runtime — loads Mint-exported GLBs and exposes a play
# API for labs + gameplay.
#
# Clip GLBs are merged into one AnimationPlayer. An AnimationTree layers:
#   loco → jump OneShot → fire OneShot → action OneShot → aim Blend2 → output
# so jump / fire / reload / aim can overlay walk-run instead of replacing them.

const REGISTRY_PATH: String = "res://data/mint/characters.json"

var slug: String = ""
var display_name: String = ""
var _root: Node3D = null
var _anim: AnimationPlayer = null
var _tree: AnimationTree = null
var _clips: PackedStringArray = PackedStringArray()
var _base_clip: String = ""
var _aim_clip: String = ""
var _jump_clip: String = ""
var _fire_clip: String = ""
var _action_clip: String = ""


static func load_profile(character_slug: String) -> MintCharacter:
	var registry: Dictionary = _load_registry()
	if not registry.has(character_slug):
		push_error("MintCharacter: unknown slug '%s'" % character_slug)
		return null
	var entry: Dictionary = registry[character_slug]
	var c: MintCharacter = MintCharacter.new()
	c.slug = character_slug
	c.display_name = str(entry.get("display_name", character_slug))
	c.name = "Mint_%s" % character_slug
	c.set_meta("mint_entry", entry)
	return c


static func profile_slugs() -> Array[String]:
	var registry: Dictionary = _load_registry()
	var out: Array[String] = []
	for key in registry.keys():
		out.append(str(key))
	out.sort()
	return out


static func display_name_for(character_slug: String) -> String:
	var registry: Dictionary = _load_registry()
	if registry.has(character_slug) and typeof(registry[character_slug]) == TYPE_DICTIONARY:
		var entry: Dictionary = registry[character_slug]
		return str(entry.get("display_name", character_slug))
	return character_slug


static func _load_registry() -> Dictionary:
	if not FileAccess.file_exists(REGISTRY_PATH):
		return {}
	var f: FileAccess = FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var root: Dictionary = parsed
	var chars: Variant = root.get("characters", {})
	return chars if typeof(chars) == TYPE_DICTIONARY else {}


func _ready() -> void:
	var entry: Dictionary = get_meta("mint_entry", {}) as Dictionary
	if entry.is_empty():
		push_error("MintCharacter: missing mint_entry meta")
		return
	_instantiate_from_entry(entry)


func _instantiate_from_entry(entry: Dictionary) -> void:
	var clips_dir: String = str(entry.get("clips_dir", ""))
	var clip_names: Array = entry.get("clips", []) as Array
	var host_probe: String = ""
	if clips_dir != "":
		var probe_stem: String = "Idle"
		if not clip_names.is_empty():
			probe_stem = str(clip_names[0])
		host_probe = "%s/%s.glb" % [clips_dir.rstrip("/"), probe_stem]
	if host_probe != "" and ResourceLoader.exists(host_probe):
		_instantiate_from_clip_set(clips_dir, clip_names, float(entry.get("scale", 1.0)))
		return

	var scene_path: String = str(entry.get("animated_glb", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		scene_path = str(entry.get("glb", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("MintCharacter(%s): no GLB at registry paths" % slug)
		return
	_root = _instantiate_scene(scene_path)
	if _root == null:
		return
	_root.name = "Model"
	add_child(_root)
	_apply_scale(_root, float(entry.get("scale", 1.0)))
	_anim = _find_animation_player(_root)
	if _anim != null:
		_clips = PackedStringArray(_anim.get_animation_list())
		_build_anim_tree()
		_autoplay_idle()


func _instantiate_from_clip_set(clips_dir: String, preferred_names: Array, scale_mul: float) -> void:
	var stems: Array[String] = []
	var seen: Dictionary = {}
	if not preferred_names.is_empty():
		for n in preferred_names:
			var s: String = str(n)
			if not seen.has(s):
				stems.append(s)
				seen[s] = true
	for scanned in _scan_clip_stems(clips_dir):
		if not seen.has(scanned):
			stems.append(scanned)
			seen[scanned] = true
	if stems.is_empty():
		push_error("MintCharacter(%s): clips_dir empty: %s" % [slug, clips_dir])
		return

	var host_stem: String = "Idle" if stems.has("Idle") else stems[0]
	var host_path: String = "%s/%s.glb" % [clips_dir.rstrip("/"), host_stem]
	if not ResourceLoader.exists(host_path):
		push_warning("MintCharacter(%s): host clip not imported yet: %s" % [slug, host_path])
	_root = _instantiate_scene(host_path)
	if _root == null:
		push_error("MintCharacter(%s): failed to instance host %s" % [slug, host_path])
		return
	_root.name = "Model"
	add_child(_root)
	_apply_scale(_root, scale_mul)

	_anim = _find_animation_player(_root)
	if _anim == null:
		push_error("MintCharacter(%s): host has no AnimationPlayer" % slug)
		return

	var lib := AnimationLibrary.new()
	for stem in stems:
		var path: String = "%s/%s.glb" % [clips_dir.rstrip("/"), stem]
		if not ResourceLoader.exists(path):
			continue
		var anim: Animation = _extract_first_animation(path)
		if anim == null:
			push_warning("MintCharacter(%s): no animation in %s" % [slug, path])
			continue
		anim.resource_name = stem
		var lower: String = stem.to_lower()
		var oneshot: bool = (
			lower.find("jump") >= 0
			or lower.find("shoot") >= 0
			or lower.find("draw") >= 0
			or lower.find("reload") >= 0
			or lower.find("pick") >= 0
		)
		if not oneshot:
			anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(stem, anim)
		_clips.append(stem)

	for lib_name in _anim.get_animation_library_list():
		_anim.remove_animation_library(lib_name)
	_anim.add_animation_library("", lib)
	_build_anim_tree()
	_autoplay_idle()


func _build_anim_tree() -> void:
	if _anim == null or _clips.is_empty():
		return
	_jump_clip = _first_matching(["Regular_Jump", "Jump"])
	_fire_clip = _first_matching([
		"Cowboy_Quick_Draw_Shooting", "Draw_and_Shoot_from_Back",
		"Draw_and_Shoot_from_Back_1", "Draw_and_Shoot_Left"
	])
	_aim_clip = _first_matching([
		"Gesture_with_Hand_on_Gun", "Female_Crouch_Pick_Gun_Point_Forward", "Idle"
	])
	var idle: String = _first_matching(["Idle", "idle"])
	if idle == "":
		idle = _clips[0]
	var walk: String = _first_matching(["Casual_Walk_inplace", "Walk"])
	if walk == "":
		walk = idle
	var run: String = _first_matching(["run_fast_3_inplace", "Run"])
	if run == "":
		run = walk

	_tree = AnimationTree.new()
	_tree.name = "AnimTree"
	_root.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)

	var blend := AnimationNodeBlendTree.new()

	# Continuous gait: walk↔run keeps arm-swing time when speeding up.
	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = walk
	blend.add_node("walk", walk_node, Vector2(-400, -40))
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = run
	blend.add_node("run", run_node, Vector2(-400, 40))
	var gait := AnimationNodeBlend2.new()
	blend.add_node("gait", gait, Vector2(-220, 0))
	blend.connect_node("gait", 0, "walk")
	blend.connect_node("gait", 1, "run")

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = idle
	blend.add_node("idle", idle_node, Vector2(-400, -120))
	var stance := AnimationNodeBlend2.new()
	blend.add_node("stance", stance, Vector2(-60, -40))
	blend.connect_node("stance", 0, "idle")
	blend.connect_node("stance", 1, "gait")

	# Parkour layering: oneshots / aim only hit UPPER body so legs keep cycling.
	var jump_node := AnimationNodeAnimation.new()
	jump_node.animation = _jump_clip if _jump_clip != "" else idle
	blend.add_node("jump_clip", jump_node, Vector2(-200, 120))
	var jump_os := AnimationNodeOneShot.new()
	jump_os.fadein_time = 0.06
	jump_os.fadeout_time = 0.22
	jump_os.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	_filter_bones(jump_os, _JUMP_BONES)
	blend.add_node("jump", jump_os, Vector2(120, 40))

	var fire_node := AnimationNodeAnimation.new()
	fire_node.animation = _fire_clip if _fire_clip != "" else idle
	blend.add_node("fire_clip", fire_node, Vector2(-200, 240))
	var fire_os := AnimationNodeOneShot.new()
	fire_os.fadein_time = 0.04
	fire_os.fadeout_time = 0.16
	fire_os.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	_filter_bones(fire_os, _ARM_BONES)
	blend.add_node("fire", fire_os, Vector2(280, 40))

	_action_clip = _first_matching(["Forward_Reload_Subtle", "Reload"])
	var action_node := AnimationNodeAnimation.new()
	action_node.animation = _action_clip if _action_clip != "" else idle
	blend.add_node("action_clip", action_node, Vector2(-200, 360))
	var action_os := AnimationNodeOneShot.new()
	action_os.fadein_time = 0.05
	action_os.fadeout_time = 0.16
	action_os.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	_filter_bones(action_os, _ARM_BONES)
	blend.add_node("action", action_os, Vector2(440, 40))

	var aim_node := AnimationNodeAnimation.new()
	aim_node.animation = _aim_clip if _aim_clip != "" else idle
	blend.add_node("aim_clip", aim_node, Vector2(-200, 480))
	var aim_blend := AnimationNodeBlend2.new()
	_filter_bones(aim_blend, _ARM_BONES)
	blend.add_node("aim", aim_blend, Vector2(600, 40))

	blend.connect_node("jump", 0, "stance")
	blend.connect_node("jump", 1, "jump_clip")
	blend.connect_node("fire", 0, "jump")
	blend.connect_node("fire", 1, "fire_clip")
	blend.connect_node("action", 0, "fire")
	blend.connect_node("action", 1, "action_clip")
	blend.connect_node("aim", 0, "action")
	blend.connect_node("aim", 1, "aim_clip")
	blend.connect_node("output", 0, "aim")

	_tree.tree_root = blend
	_tree.active = true
	_anim.active = false
	_base_clip = idle
	set_move_blend(0.0, 0.0)
	set_aim_blend(0.0)


# Bones oneshots may replace. Legs / feet omitted so loco continues underneath.
const _JUMP_BONES: Array[String] = [
	"Hips", "Spine", "Spine01", "Spine02",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"neck", "Head", "head_end", "headfront",
]
const _ARM_BONES: Array[String] = [
	"Spine", "Spine01", "Spine02",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"neck", "Head",
]


func _filter_bones(node: AnimationNode, bones: Array[String]) -> void:
	node.filter_enabled = true
	for bone in bones:
		node.set_filter_path("Armature/Skeleton3D:%s" % bone, true)


# moving 0..1 (idle→loco), gait 0..1 (walk→run). Continuous arm swing.
func set_move_blend(moving: float, gait: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/stance/blend_amount", clampf(moving, 0.0, 1.0))
	_tree.set("parameters/gait/blend_amount", clampf(gait, 0.0, 1.0))
	if moving < 0.05:
		_base_clip = _first_matching(["Idle", "idle"])
	elif gait > 0.55:
		_base_clip = _first_matching(["run_fast_3_inplace", "Run"])
	else:
		_base_clip = _first_matching(["Casual_Walk_inplace", "Walk"])


func _first_matching(candidates: Array) -> String:
	for c in candidates:
		var name: String = str(c)
		if _has_clip(name):
			return name
	return ""


func _extract_first_animation(scene_path: String) -> Animation:
	var tmp: Node3D = _instantiate_scene(scene_path)
	if tmp == null:
		return null
	var player: AnimationPlayer = _find_animation_player(tmp)
	if player == null:
		tmp.free()
		return null
	var names: PackedStringArray = player.get_animation_list()
	if names.is_empty():
		tmp.free()
		return null
	var src: Animation = player.get_animation(names[0])
	var dup: Animation = src.duplicate(true) as Animation
	tmp.free()
	return dup


func _scan_clip_stems(clips_dir: String) -> Array[String]:
	var out: Array[String] = []
	var abs_dir: String = ProjectSettings.globalize_path(clips_dir)
	var d: DirAccess = DirAccess.open(abs_dir)
	if d == null:
		return out
	d.list_dir_begin()
	var fname: String = d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".glb"):
			out.append(fname.get_basename())
		fname = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _instantiate_scene(scene_path: String) -> Node3D:
	if not ResourceLoader.exists(scene_path):
		push_error("MintCharacter(%s): missing %s (open Godot once to import)" % [slug, scene_path])
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("MintCharacter(%s): failed to load %s" % [slug, scene_path])
		return null
	return packed.instantiate() as Node3D


func _apply_scale(node: Node3D, scale_mul: float) -> void:
	if scale_mul != 1.0:
		node.scale = Vector3.ONE * scale_mul


func _autoplay_idle() -> void:
	if _tree != null:
		set_move_blend(0.0, 0.0)
		return
	var preferred: Array[String] = ["Idle", "idle", "Idle_Loop"]
	for name in preferred:
		if _has_clip(name):
			play(name)
			return
	if not _clips.is_empty():
		play(_clips[0])


func clip_names() -> PackedStringArray:
	return _clips


# Base locomotion / stance. Walk/run map to continuous gait blends so arm
# swing doesn't restart; other clips fall through to AnimationPlayer (manual).
func play(clip: String, _custom_blend: float = 0.15) -> bool:
	if not _resolve_clip(clip):
		return false
	clip = _resolved
	_base_clip = clip
	if _tree != null:
		var lower: String = clip.to_lower()
		if lower.find("run") >= 0:
			_ensure_tree_driving()
			set_move_blend(1.0, 1.0)
			return true
		if lower.find("walk") >= 0 or lower.find("casual") >= 0:
			_ensure_tree_driving()
			set_move_blend(1.0, 0.0)
			return true
		if lower == "idle" or lower.find("idle") == 0:
			_ensure_tree_driving()
			_set_idle_animation(_first_matching(["Idle", "idle"]))
			set_move_blend(0.0, 0.0)
			return true
		if lower.find("turn") >= 0:
			_ensure_tree_driving()
			_set_idle_animation(clip)
			set_move_blend(0.0, 0.0)
			return true
		# Manual clip picker — temporarily drive AnimationPlayer directly.
		_tree.active = false
		if _anim != null:
			_anim.active = true
			_anim.play(clip, _custom_blend)
		return true
	if _anim == null:
		return false
	_anim.active = true
	_anim.play(clip, _custom_blend)
	return true


func _ensure_tree_driving() -> void:
	if _tree == null:
		return
	_tree.active = true
	if _anim != null:
		_anim.active = false


func _set_idle_animation(clip: String) -> void:
	if clip == "" or _tree == null:
		return
	var root: AnimationNodeBlendTree = _tree.tree_root as AnimationNodeBlendTree
	if root == null:
		return
	var idle_node: AnimationNodeAnimation = root.get_node("idle") as AnimationNodeAnimation
	if idle_node != null and idle_node.animation != clip:
		idle_node.animation = clip


var _resolved: String = ""


func _resolve_clip(clip: String) -> bool:
	_resolved = clip
	if _has_clip(clip):
		return true
	for existing in _clips:
		if String(existing).to_lower() == clip.to_lower():
			_resolved = existing
			return true
	push_warning("MintCharacter(%s): missing clip '%s'" % [slug, clip])
	return false


func set_aim_blend(amount: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/aim/blend_amount", clampf(amount, 0.0, 1.0))


func request_jump() -> bool:
	if _tree == null or _jump_clip == "":
		return play(_jump_clip if _jump_clip != "" else "Regular_Jump")
	_tree.set("parameters/jump/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func request_fire() -> bool:
	if _tree == null or _fire_clip == "":
		return play(_fire_clip if _fire_clip != "" else "Cowboy_Quick_Draw_Shooting")
	_tree.set("parameters/fire/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func request_action(clip: String = "") -> bool:
	if _tree == null:
		return play(clip if clip != "" else "Forward_Reload_Subtle")
	var use: String = clip if clip != "" else _action_clip
	if use == "" or not _resolve_clip(use):
		return false
	use = _resolved
	var root: AnimationNodeBlendTree = _tree.tree_root as AnimationNodeBlendTree
	if root != null:
		var action_anim: AnimationNodeAnimation = root.get_node("action_clip") as AnimationNodeAnimation
		if action_anim != null:
			action_anim.animation = use
	_action_clip = use
	_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func is_jump_active() -> bool:
	if _tree == null:
		return false
	return bool(_tree.get("parameters/jump/active"))


func is_fire_active() -> bool:
	if _tree == null:
		return false
	return bool(_tree.get("parameters/fire/active"))


func is_action_active() -> bool:
	if _tree == null:
		return false
	return bool(_tree.get("parameters/action/active"))


# --- Held props (sidearm / repair tool share the same hand mount) ---------

const DEFAULT_SIDEARM: String = "res://models/quaternius/guns/Gun_Pistol.gltf"

var _held_mount: BoneAttachment3D = null
var _held_prop: Node3D = null
var _held_aimed: bool = false


func find_skeleton() -> Skeleton3D:
	return _find_skeleton(_root if _root != null else self)


func set_held_sidearm(carried: bool, aimed: bool = true, glb_path: String = "") -> void:
	var path: String = glb_path if glb_path != "" else DEFAULT_SIDEARM
	_clear_held_prop()
	if not carried:
		return
	var skel: Skeleton3D = find_skeleton()
	if skel == null:
		push_warning("MintCharacter(%s): no Skeleton3D for held prop" % slug)
		return
	var bone: String = "RightHand" if aimed else "Hips"
	if skel.find_bone(bone) < 0:
		push_warning("MintCharacter(%s): missing bone '%s'" % [slug, bone])
		return
	_held_mount = BoneAttachment3D.new()
	_held_mount.name = "HeldPropMount"
	_held_mount.bone_name = bone
	skel.add_child(_held_mount)
	if not ResourceLoader.exists(path):
		push_warning("MintCharacter(%s): missing prop %s" % [slug, path])
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return
	_held_prop = packed.instantiate() as Node3D
	if _held_prop == null:
		return
	_held_prop.name = "HeldProp"
	# Quaternius pistol frame (modular_character pistol_grip_grid candidate #6).
	# Mint hand axes may need a later capture pass — close enough for studio.
	if aimed:
		_held_prop.position = Vector3(0.0, 0.06, 0.02)
		_held_prop.rotation = Vector3(0.0, -1.57, 0.0)
	else:
		_held_prop.position = Vector3(0.14, 0.02, 0.04)
		_held_prop.rotation = Vector3(-1.57, 0.0, 0.0)
	_held_mount.add_child(_held_prop)
	_held_aimed = aimed


func is_held_aimed() -> bool:
	return _held_aimed and _held_prop != null


func muzzle_global_position() -> Vector3:
	if _held_prop != null:
		# Approximate muzzle: pistol barrel along local -X after aimed rotate.
		return _held_prop.global_transform * Vector3(0.18, 0.02, 0.0)
	var skel: Skeleton3D = find_skeleton()
	if skel != null:
		var idx: int = skel.find_bone("RightHand")
		if idx >= 0:
			return skel.global_transform * skel.get_bone_global_pose(idx).origin
	return global_position + Vector3(0.0, 1.2, 0.3)


func _clear_held_prop() -> void:
	if _held_mount != null and is_instance_valid(_held_mount):
		_held_mount.queue_free()
	_held_mount = null
	_held_prop = null
	_held_aimed = false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func stop() -> void:
	if _tree != null:
		_tree.active = false
	if _anim != null:
		_anim.active = true
		_anim.stop()


func current_clip() -> String:
	if _base_clip != "":
		return _base_clip
	if _anim == null:
		return ""
	return _anim.current_animation


func _has_clip(clip: String) -> bool:
	for existing in _clips:
		if existing == clip:
			return true
	return false


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null
