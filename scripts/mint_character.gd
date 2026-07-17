extends Node3D
class_name MintCharacter

# Mint-native character runtime — loads Mint-exported GLBs and exposes a play
# API for labs + gameplay.
#
# Clip GLBs are merged into one AnimationPlayer. An AnimationTree layers:
#   loco → jump OneShot → fire OneShot → action OneShot → aim Blend2 → output
# so jump / fire / reload / aim can overlay walk-run instead of replacing them.

const REGISTRY_PATH: String = "res://data/mint/characters.json"
const WEAPONS_PATH: String = "res://data/mint/weapons.json"
const HeldWeaponScript: Script = preload("res://scripts/mint_held_weapon.gd")

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
var _draw_clip: String = ""
var _action_clip: String = ""
var _weapon: MintHeldWeapon = null
var _entry_sidearm: Dictionary = {}
var _weapon_id: String = "sidearm"
var _weapon_cfg: Dictionary = {}


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
	if typeof(entry.get("sidearm", {})) == TYPE_DICTIONARY:
		_entry_sidearm = entry["sidearm"] as Dictionary
	_instantiate_from_entry(entry)


func _process(_delta: float) -> void:
	if _weapon != null and _weapon.is_drawn():
		_weapon.apply_grip_pose()


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

	# Two-pass merge: Idle first for hip-Y baseline, then normalize every clip
	# so blends don't grow/shrink or sink the body.
	var rest_hip_y: float = NAN
	var idle_path: String = "%s/Idle.glb" % clips_dir.rstrip("/")
	if ResourceLoader.exists(idle_path):
		var idle_anim: Animation = _extract_first_animation(idle_path)
		if idle_anim != null:
			rest_hip_y = _hips_pos_y_at_frame0(idle_anim)

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
		_normalize_animation(anim, rest_hip_y, lower.find("jump") >= 0)
		if is_nan(rest_hip_y):
			rest_hip_y = _hips_pos_y_at_frame0(anim)
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
	_draw_clip = _first_matching([
		"Cowboy_Quick_Draw_Shooting", "Draw_and_Shoot_from_Back",
		"Draw_and_Shoot_from_Back_1", "Draw_and_Shoot_Left"
	])
	_fire_clip = _first_matching([
		"Walk_Forward_While_Shooting", "Cowboy_Quick_Draw_Shooting",
		"Draw_and_Shoot_from_Back"
	])
	_aim_clip = _first_matching([
		"Gesture_with_Hand_on_Gun", "Idle"
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

	_action_clip = _draw_clip if _draw_clip != "" else _first_matching(["Forward_Reload_Subtle", "Reload"])
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
	var skel: Skeleton3D = find_skeleton()
	var expanded: Array[String] = bones.duplicate()
	# Include finger chains under hand bones so aim/fire grip deforms skin.
	if skel != null:
		for bone in bones:
			if bone.ends_with("Hand") or bone.find("Hand") >= 0:
				_append_bone_descendants(skel, bone, expanded)
	for bone in expanded:
		node.set_filter_path("Armature/Skeleton3D:%s" % bone, true)


func _append_bone_descendants(skel: Skeleton3D, parent_name: String, out: Array[String]) -> void:
	var parent_idx: int = skel.find_bone(parent_name)
	if parent_idx < 0:
		return
	for i in skel.get_bone_count():
		var cur: int = i
		var guard: int = 0
		while cur >= 0 and guard < 64:
			if cur == parent_idx and i != parent_idx:
				var nm: String = skel.get_bone_name(i)
				if not out.has(nm):
					out.append(nm)
				break
			cur = skel.get_bone_parent(cur)
			guard += 1


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


# Kill cross-clip size/height pops: strip scale, in-place XZ, match Idle hip Y.
# Jump: drop Hips position so code hop owns vertical travel.
func _normalize_animation(anim: Animation, rest_hip_y: float, is_jump: bool) -> void:
	if anim == null:
		return
	# Remove SCALE tracks (Idle had ~1.18 on Hips — blends looked like grow/shrink).
	var remove_idxs: Array[int] = []
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) == Animation.TYPE_SCALE_3D:
			remove_idxs.append(ti)
	remove_idxs.reverse()
	for ti in remove_idxs:
		anim.remove_track(ti)

	var hip_pos_ti: int = -1
	for ti in anim.get_track_count():
		var path: String = String(anim.track_get_path(ti))
		if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D and path.ends_with(":Hips"):
			hip_pos_ti = ti
			break
	if hip_pos_ti < 0:
		return
	if is_jump:
		anim.remove_track(hip_pos_ti)
		return
	if anim.track_get_key_count(hip_pos_ti) < 1:
		return
	var p0: Vector3 = anim.track_get_key_value(hip_pos_ti, 0) as Vector3
	var y_target: float = rest_hip_y if not is_nan(rest_hip_y) else p0.y
	var y_off: float = y_target - p0.y
	for ki in anim.track_get_key_count(hip_pos_ti):
		var p: Vector3 = anim.track_get_key_value(hip_pos_ti, ki) as Vector3
		# In-place: kill root XZ drift; match Idle hip Y baseline.
		anim.track_set_key_value(hip_pos_ti, ki, Vector3(p.x - p0.x, p.y + y_off, p.z - p0.z))


func _hips_pos_y_at_frame0(anim: Animation) -> float:
	if anim == null:
		return NAN
	for ti in anim.get_track_count():
		var path: String = String(anim.track_get_path(ti))
		if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D and path.ends_with(":Hips"):
			if anim.track_get_key_count(ti) < 1:
				return NAN
			var p: Vector3 = anim.track_get_key_value(ti, 0) as Vector3
			return p.y
	return NAN


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
	if _weapon != null and not _weapon.is_ready_to_fire():
		return false
	if _weapon != null:
		_weapon.notify_fire_started()
	if _tree == null or _fire_clip == "":
		var ok: bool = play(_fire_clip if _fire_clip != "" else "Cowboy_Quick_Draw_Shooting")
		if _weapon != null:
			_weapon.notify_fire_finished()
		return ok
	_tree.set("parameters/fire/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	# Approximate fire oneshot end for state machine.
	var dur: float = 0.45
	if _anim != null and _anim.has_animation(_fire_clip):
		dur = maxf(0.25, _anim.get_animation(_fire_clip).length * 0.55)
	get_tree().create_timer(dur).timeout.connect(func() -> void:
		if _weapon != null:
			_weapon.notify_fire_finished()
	, CONNECT_ONE_SHOT)
	return true


func request_draw() -> bool:
	var dur: float = 0.55
	if _draw_clip != "" and _anim != null and _anim.has_animation(_draw_clip):
		dur = maxf(0.35, _anim.get_animation(_draw_clip).length)
	if _weapon != null:
		_weapon.request_draw(dur)
	if _draw_clip != "":
		return request_action(_draw_clip)
	return _weapon != null


func request_holster() -> bool:
	if _weapon != null:
		_weapon.request_holster(0.35)
	set_aim_blend(0.0)
	return true


func weapon_state_name() -> String:
	if _weapon == null:
		return "NONE"
	return _weapon.state_name()


func is_weapon_drawn() -> bool:
	return _weapon != null and _weapon.is_drawn()


func is_weapon_ready() -> bool:
	return _weapon != null and _weapon.is_ready_to_fire()


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


# --- Held weapon (holster ↔ hand) ------------------------------------------

static func weapon_ids() -> Array[String]:
	var root: Dictionary = _load_weapons_root()
	var weapons: Variant = root.get("weapons", {})
	var out: Array[String] = []
	if typeof(weapons) != TYPE_DICTIONARY:
		return out
	for key in (weapons as Dictionary).keys():
		out.append(str(key))
	out.sort()
	# Prefer sidearm first for studio defaults.
	var side_idx: int = out.find("sidearm")
	if side_idx > 0:
		out.remove_at(side_idx)
		out.insert(0, "sidearm")
	return out


static func weapon_display_name(weapon_id: String) -> String:
	var cfg: Dictionary = resolve_weapon_config(weapon_id)
	return str(cfg.get("display_name", weapon_id))


static func resolve_weapon_config(weapon_id: String) -> Dictionary:
	var root: Dictionary = _load_weapons_root()
	var weapons: Variant = root.get("weapons", {})
	if typeof(weapons) != TYPE_DICTIONARY:
		return {}
	var table: Dictionary = weapons as Dictionary
	if not table.has(weapon_id):
		return {}
	var cfg: Dictionary = (table[weapon_id] as Dictionary).duplicate(true)
	cfg["id"] = weapon_id
	var mint_glb: String = str(cfg.get("mint_glb", ""))
	var fallback: String = str(cfg.get("glb", ""))
	if mint_glb != "" and ResourceLoader.exists(mint_glb):
		cfg["glb"] = mint_glb
		cfg["asset_source"] = "mint"
	elif fallback != "" and ResourceLoader.exists(fallback):
		cfg["glb"] = fallback
		cfg["asset_source"] = "fallback"
	else:
		cfg["asset_source"] = "missing"
	return cfg


static func _load_weapons_root() -> Dictionary:
	if not FileAccess.file_exists(WEAPONS_PATH):
		return {}
	var f: FileAccess = FileAccess.open(WEAPONS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func current_weapon_id() -> String:
	return _weapon_id


func equip_weapon(weapon_id: String = "sidearm", overrides: Dictionary = {}) -> bool:
	var cfg: Dictionary = resolve_weapon_config(weapon_id)
	if cfg.is_empty() and weapon_id == "sidearm" and not _entry_sidearm.is_empty():
		cfg = _entry_sidearm.duplicate(true)
		cfg["id"] = "sidearm"
		cfg["display_name"] = str(cfg.get("display_name", "Sidearm"))
	if cfg.is_empty():
		push_warning("MintCharacter(%s): unknown weapon '%s'" % [slug, weapon_id])
		return false
	for k in overrides.keys():
		cfg[k] = overrides[k]
	# Character registry sidearm mounts can override library defaults.
	if weapon_id == "sidearm" and not _entry_sidearm.is_empty():
		for k in _entry_sidearm.keys():
			if not overrides.has(k):
				cfg[k] = _entry_sidearm[k]
		# Prefer Mint prop path when registry still points at Quaternius.
		var resolved: Dictionary = resolve_weapon_config("sidearm")
		if str(resolved.get("asset_source", "")) == "mint":
			cfg["glb"] = resolved["glb"]
			cfg["asset_source"] = "mint"
	if _weapon != null:
		_weapon.unequip()
		_weapon.queue_free()
		_weapon = null
	var skel: Skeleton3D = find_skeleton()
	if skel == null:
		push_warning("MintCharacter(%s): no skeleton for weapon" % slug)
		return false
	_weapon = HeldWeaponScript.new()
	_weapon.name = "HeldWeapon"
	add_child(_weapon)
	var ok: bool = _weapon.equip(skel, cfg)
	if not ok:
		_weapon.queue_free()
		_weapon = null
		return false
	_weapon_id = weapon_id
	_weapon_cfg = cfg
	_apply_weapon_clip_roles(cfg)
	return true


func equip_sidearm(config: Dictionary = {}) -> bool:
	return equip_weapon("sidearm", config)


func cycle_weapon(delta: int = 1) -> String:
	var ids: Array[String] = weapon_ids()
	if ids.is_empty():
		return _weapon_id
	var idx: int = ids.find(_weapon_id)
	if idx < 0:
		idx = 0
	idx = (idx + delta) % ids.size()
	if idx < 0:
		idx += ids.size()
	var next_id: String = ids[idx]
	var was_drawn: bool = is_weapon_drawn()
	if not equip_weapon(next_id):
		return _weapon_id
	if was_drawn:
		request_draw()
	return _weapon_id


func grip_status() -> String:
	if _weapon == null:
		return "fingers: —"
	return _weapon.grip_status()


func weapon_label() -> String:
	if _weapon == null:
		return "—"
	var src: String = str(_weapon_cfg.get("asset_source", ""))
	var tag: String = "mint" if src == "mint" else ("kit" if src == "fallback" else "?")
	return "%s [%s] · %s" % [_weapon.display_name, tag, _weapon.state_name()]


func _apply_weapon_clip_roles(cfg: Dictionary) -> void:
	var draw_list: Array = cfg.get("draw_clips", []) as Array
	var aim_list: Array = cfg.get("aim_clips", []) as Array
	var fire_list: Array = cfg.get("fire_clips", []) as Array
	var draw: String = _first_from_list(draw_list)
	var aim: String = _first_from_list(aim_list)
	var fire: String = _first_from_list(fire_list)
	if draw != "":
		_draw_clip = draw
		_action_clip = draw
	if aim != "":
		_aim_clip = aim
		_set_tree_animation("aim_clip", aim)
	if fire != "":
		_fire_clip = fire
		_set_tree_animation("fire_clip", fire)


func _first_from_list(names: Array) -> String:
	for n in names:
		var clip: String = str(n)
		if _has_clip(clip):
			return clip
		for existing in _clips:
			if String(existing).to_lower() == clip.to_lower():
				return existing
	return ""


func _set_tree_animation(node_name: String, clip: String) -> void:
	if _tree == null or clip == "":
		return
	var root: AnimationNodeBlendTree = _tree.tree_root as AnimationNodeBlendTree
	if root == null:
		return
	var anim_node: AnimationNodeAnimation = root.get_node(node_name) as AnimationNodeAnimation
	if anim_node != null:
		anim_node.animation = clip


func find_skeleton() -> Skeleton3D:
	return _find_skeleton(_root if _root != null else self)


func muzzle_global_position() -> Vector3:
	if _weapon != null:
		var m: Vector3 = _weapon.muzzle_global_position()
		if m != Vector3.ZERO:
			return m
	var skel: Skeleton3D = find_skeleton()
	if skel != null:
		var idx: int = skel.find_bone("RightHand")
		if idx >= 0:
			return skel.global_transform * skel.get_bone_global_pose(idx).origin
	return global_position + Vector3(0.0, 1.2, 0.3)


# Deprecated shim — prefer equip_sidearm + request_draw/request_holster.
func set_held_sidearm(carried: bool, aimed: bool = true, glb_path: String = "") -> void:
	if not carried:
		if _weapon != null:
			_weapon.unequip()
			_weapon.queue_free()
			_weapon = null
		return
	var cfg: Dictionary = {}
	if glb_path != "":
		cfg["glb"] = glb_path
	if not equip_sidearm(cfg):
		return
	if aimed:
		request_draw()
	else:
		request_holster()


func is_held_aimed() -> bool:
	return is_weapon_ready()


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
