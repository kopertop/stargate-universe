extends SceneTree

# Build the shared crew AnimationLibrary from retargeted Mixamo imports.
# Each imported FBX (with humanoid BoneMap) carries a 'mixamo_com' clip whose
# tracks address %GeneralSkeleton:<HumanoidBone> — playable on ANY VRM
# character. This collects them under friendly names, sets loop flags,
# REMOVES ROOT DRIFT from locomotion clips (Mixamo exports here are not
# "In Place" — the Hips position track carries real translation, which makes
# characters slide away from their node position in-game; gameplay code moves
# the body, so clips must animate on the spot), optionally slices a time
# window (e.g. the aim-idle hold at the end of a transition clip), and saves
# res://models/vrm/anim/crew_body.res.
#   godot --headless --quit-after 240 -s res://tools/extract_anim_library.gd

# friendly name -> {src, loop, in_place, slice: [from_t, to_t]}
const MANIFEST: Dictionary = {
	"idle": {"src": "standingidle", "loop": true},
	"walk": {"src": "walking", "loop": true, "in_place": true},
	"run": {"src": "runningfast", "loop": true, "in_place": true},
	"idle_happy": {"src": "happy-idle", "loop": true},
	"idle_sad": {"src": "sad-idle", "loop": true},
	"wave": {"src": "ajwavinggesture", "loop": false},
	"nod": {"src": "hardheadnodyes", "loop": false},
	"point": {"src": "pointingwitharmbent", "loop": false},
	"argue": {"src": "standingarguingwithanotherperson", "loop": true},
	"rifle_walk": {"src": "riflewalkforward", "loop": true, "in_place": true, "yaw_rebase": true},
	"rifle_run": {"src": "runningwithrifledown", "loop": true, "in_place": true},
	"rifle_run_aim": {"src": "runningwithrifleaimed", "loop": true, "in_place": true},
	"rifle_draw": {"src": "standingtoreadyposegrabbingriflefromtheback", "loop": false},
	"rifle_fire_walk": {"src": "firingwhilewalkingwithrifle", "loop": true, "in_place": true},
	"death": {"src": "deathfromstandingidle", "loop": false},
	# Stationary aim: the settled hold at the tail of the stop-running clip.
	"rifle_aim": {"src": "stoprunningtoaimingrifleidle", "loop": true,
		"in_place": true, "rebase": true, "slice": [1.70, 2.85], "yaw_rebase": 53.0},
	# ---- Quaternius Universal Animation Library (first-party, same rig) ----
	"talk": {"lib": "UAL1_Standard", "clip": "Idle_Talking", "loop": true},
	"sit_enter": {"lib": "UAL1_Standard", "clip": "Sitting_Enter", "loop": false},
	"sit": {"lib": "UAL1_Standard", "clip": "Sitting_Idle", "loop": true},
	"sit_talk": {"lib": "UAL1_Standard", "clip": "Sitting_Talking", "loop": true},
	"sit_exit": {"lib": "UAL1_Standard", "clip": "Sitting_Exit", "loop": false},
	"interact": {"lib": "UAL1_Standard", "clip": "Interact", "loop": false},
	"repair": {"lib": "UAL1_Standard", "clip": "Fixing_Kneeling", "loop": true},
	"pickup": {"lib": "UAL1_Standard", "clip": "PickUp_Table", "loop": false},
	"pistol_idle": {"lib": "UAL1_Standard", "clip": "Pistol_Idle", "loop": true},
	"pistol_aim": {"lib": "UAL1_Standard", "clip": "Pistol_Aim_Neutral", "loop": true},
	"pistol_shoot": {"lib": "UAL1_Standard", "clip": "Pistol_Shoot", "loop": false},
	"pistol_reload": {"lib": "UAL1_Standard", "clip": "Pistol_Reload", "loop": false},
	"jog": {"lib": "UAL1_Standard", "clip": "Jog_Fwd", "loop": true},
	"sprint": {"lib": "UAL1_Standard", "clip": "Sprint", "loop": true},
	"crouch_idle": {"lib": "UAL1_Standard", "clip": "Crouch_Idle", "loop": true},
	"crouch_walk": {"lib": "UAL1_Standard", "clip": "Crouch_Fwd", "loop": true},
	"hit": {"lib": "UAL1_Standard", "clip": "Hit_Chest", "loop": false},
	"death2": {"lib": "UAL1_Standard", "clip": "Death01", "loop": false},
	"dance": {"lib": "UAL1_Standard", "clip": "Dance", "loop": true},
	"idle_arms_folded": {"lib": "UAL2_Standard", "clip": "Idle_FoldArms", "loop": true},
	"shake_no": {"lib": "UAL2_Standard", "clip": "Idle_No", "loop": false},
	"nod_yes": {"lib": "UAL2_Standard", "clip": "Yes", "loop": false},
	"knockback": {"lib": "UAL2_Standard", "clip": "Hit_Knockback", "loop": false},
	"consume": {"lib": "UAL2_Standard", "clip": "Consume", "loop": false},
	"walk_carry": {"lib": "UAL2_Standard", "clip": "Walk_Carry", "loop": true},
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lib: AnimationLibrary = AnimationLibrary.new()
	var ok: int = 0
	for clip_name in MANIFEST:
		var def: Dictionary = MANIFEST[clip_name]
		var src_path: String
		var src_clip: String
		if def.has("lib"):
			# Quaternius Universal Animation Library GLB (many named clips).
			src_path = "res://models/quaternius/anim_lib/%s.glb" % String(def["lib"])
			src_clip = String(def["clip"])
		else:
			src_path = "res://models/vrm/anim_src/%s.fbx" % String(def["src"])
			src_clip = "mixamo_com"
		var packed: PackedScene = load(src_path)
		if packed == null:
			print("[extract] MISSING %s" % src_path)
			continue
		var inst: Node = packed.instantiate()
		var ap: AnimationPlayer = _find_anim(inst)
		if ap == null or not ap.has_animation(src_clip):
			print("[extract] no '%s' clip in %s" % [src_clip, src_path.get_file()])
			inst.free()
			continue
		var anim: Animation = ap.get_animation(src_clip).duplicate(true)
		var stem: String = src_path.get_file()
		if def.has("slice"):
			anim = _slice(anim, float(def["slice"][0]), float(def["slice"][1]))
		var drift: Vector3 = _hips_drift(anim)
		if bool(def.get("in_place", false)):
			_remove_root_drift(anim)
		if bool(def.get("rebase", false)):
			_rebase_to_origin(anim)
		# Capture the rig's reference stance yaw from idle (first MANIFEST
		# entry), then normalize flagged clips against it — some Mixamo
		# sources bake a hips yaw (rifle_aim: -34°), which makes a character
		# visually aim ~side-on while their NODE faces the target dead-on.
		if clip_name == "idle":
			_ref_hips_yaw = _hips_first_yaw(anim)
		# yaw_rebase: true = normalize hips to idle's stance yaw (walks).
		# A NUMBER = manual extra degrees, for clips whose AIM LINE is what
		# must face node-forward (rifle_aim's source turns ~90° to aim — the
		# hips blade hard, so hips-normalization alone leaves the barrel
		# off-axis; tuned via tests/capture/greer_aim_proof.gd).
		var yr: Variant = def.get("yaw_rebase", false)
		if yr is bool and yr == true:
			_rebase_yaw(anim, clip_name, 0.0)
		elif yr is float or yr is int:
			_rebase_yaw(anim, clip_name, deg_to_rad(float(yr)))
		anim.loop_mode = Animation.LOOP_LINEAR if bool(def["loop"]) else Animation.LOOP_NONE
		lib.add_animation(clip_name, anim)
		ok += 1
		print("[extract] %-16s <- %s (%.2fs, drift %.2f,%.2f -> now %.2f,%.2f)" % [
			clip_name, stem, anim.length, drift.x, drift.z,
			_hips_drift(anim).x, _hips_drift(anim).z])
		inst.free()
	var err: int = ResourceSaver.save(lib, "res://models/vrm/anim/crew_body.res")
	print("[extract] saved crew_body.res with %d clips (err=%d)" % [ok, err])
	quit(0 if (err == OK and ok == MANIFEST.size()) else 1)


# Net horizontal Hips displacement over the clip (the "walks out of frame" bug).
func _hips_drift(anim: Animation) -> Vector3:
	var t: int = _hips_pos_track(anim)
	if t < 0 or anim.track_get_key_count(t) < 2:
		return Vector3.ZERO
	var first: Vector3 = anim.track_get_key_value(t, 0)
	var last: Vector3 = anim.track_get_key_value(t, anim.track_get_key_count(t) - 1)
	return last - first


# Subtract the linear trend of the Hips X/Z translation so the clip animates
# on the spot: net displacement becomes zero, within-cycle sway and vertical
# bob survive, and (for near-linear travel) first/last keys still match for
# clean looping.
func _remove_root_drift(anim: Animation) -> void:
	var t: int = _hips_pos_track(anim)
	if t < 0:
		return
	var n: int = anim.track_get_key_count(t)
	if n < 2:
		return
	var t0: float = anim.track_get_key_time(t, 0)
	var t1: float = anim.track_get_key_time(t, n - 1)
	var first: Vector3 = anim.track_get_key_value(t, 0)
	var last: Vector3 = anim.track_get_key_value(t, n - 1)
	var span: float = maxf(t1 - t0, 0.0001)
	for i in range(n):
		var a: float = (anim.track_get_key_time(t, i) - t0) / span
		var v: Vector3 = anim.track_get_key_value(t, i)
		v.x -= (last.x - first.x) * a
		v.z -= (last.z - first.z) * a
		anim.track_set_key_value(t, i, v)


# Sliced clips inherit the absolute Hips offset of wherever the source motion
# had travelled to — translate all keys so the first sits at the origin
# (drift removal only zeroes the trend, not the offset).
func _rebase_to_origin(anim: Animation) -> void:
	var t: int = _hips_pos_track(anim)
	if t < 0 or anim.track_get_key_count(t) == 0:
		return
	var first: Vector3 = anim.track_get_key_value(t, 0)
	for i in range(anim.track_get_key_count(t)):
		var v: Vector3 = anim.track_get_key_value(t, i)
		anim.track_set_key_value(t, i, Vector3(v.x - first.x, v.y, v.z - first.z))


func _hips_pos_track(anim: Animation) -> int:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D \
				and String(anim.track_get_path(t)).ends_with(":Hips"):
			return t
	return -1


func _hips_rot_track(anim: Animation) -> int:
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D \
				and String(anim.track_get_path(t)).ends_with(":Hips"):
			return t
	return -1


# Reference stance yaw, captured from the idle clip's first hips key.
var _ref_hips_yaw: float = 0.0


# Projected yaw of a hips rotation key (consistent formula for reference and
# clip, so the DELTA is meaningful even if the bone's local axes are exotic).
func _yaw_of(q: Quaternion) -> float:
	var fwd: Vector3 = q * Vector3(0, 0, -1)
	return atan2(-fwd.x, -fwd.z)


func _hips_first_yaw(anim: Animation) -> float:
	var t: int = _hips_rot_track(anim)
	if t < 0 or anim.track_get_key_count(t) == 0:
		return 0.0
	return _yaw_of(anim.track_get_key_value(t, 0))


# Remove a clip's BAKED hips yaw: rotate every hips rotation key (and the
# paired position keys) so the first frame's stance yaw matches idle's.
# Without this, a character playing rifle_aim visually aims ~34° off the
# direction their node faces (the "aiming where he WAS facing" bug).
func _rebase_yaw(anim: Animation, clip_name: String, extra: float = 0.0) -> void:
	var rt: int = _hips_rot_track(anim)
	if rt < 0 or anim.track_get_key_count(rt) == 0:
		return
	var delta: float = _ref_hips_yaw - _hips_first_yaw(anim) + extra
	var fix: Quaternion = Quaternion(Vector3.UP, delta)
	for i in range(anim.track_get_key_count(rt)):
		var q: Quaternion = anim.track_get_key_value(rt, i)
		anim.track_set_key_value(rt, i, fix * q)
	var pt: int = _hips_pos_track(anim)
	if pt >= 0:
		for i in range(anim.track_get_key_count(pt)):
			var v: Vector3 = anim.track_get_key_value(pt, i)
			anim.track_set_key_value(pt, i, fix * v)
	print("[extract]   yaw-rebase %s by %.1f deg" % [clip_name, rad_to_deg(delta)])


# Copy a [from_t, to_t] window of every position/rotation track into a new
# Animation (keys re-based to 0, boundary values sampled for continuity).
func _slice(src: Animation, from_t: float, to_t: float) -> Animation:
	var out: Animation = Animation.new()
	out.length = to_t - from_t
	for t in range(src.get_track_count()):
		var ttype: int = src.track_get_type(t)
		if ttype != Animation.TYPE_POSITION_3D and ttype != Animation.TYPE_ROTATION_3D:
			continue
		var nt: int = out.add_track(ttype)
		out.track_set_path(nt, src.track_get_path(t))
		out.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		# Boundary samples keep the pose continuous at the cut points.
		if ttype == Animation.TYPE_POSITION_3D:
			out.position_track_insert_key(nt, 0.0, src.position_track_interpolate(t, from_t))
			out.position_track_insert_key(nt, to_t - from_t, src.position_track_interpolate(t, to_t))
		else:
			out.rotation_track_insert_key(nt, 0.0, src.rotation_track_interpolate(t, from_t))
			out.rotation_track_insert_key(nt, to_t - from_t, src.rotation_track_interpolate(t, to_t))
		for k in range(src.track_get_key_count(t)):
			var kt: float = src.track_get_key_time(t, k)
			if kt <= from_t or kt >= to_t:
				continue
			if ttype == Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(nt, kt - from_t, src.track_get_key_value(t, k))
			else:
				out.rotation_track_insert_key(nt, kt - from_t, src.track_get_key_value(t, k))
	return out


func _find_anim(node: Node) -> AnimationPlayer:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
