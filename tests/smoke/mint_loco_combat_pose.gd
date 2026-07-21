extends SceneTree

# Play-path regression: Eli must stay human-shaped while walking + aiming + firing.
# This is the guard for the Animation Studio spaghetti incident — structural bone
# counts alone are not enough; distortion shows up under loco/combat poses.
#
# Run: tests/run.sh mint-character   (or mint-loco-combat)

const MAX_HEIGHT: float = 2.15
const MIN_HEIGHT: float = 1.05
const MAX_LATERAL: float = 1.75
const MAX_AABB_LEN: float = 2.75
const MAX_HIP_DIST: float = 1.35
const MAX_OUTLIER_HIP_DIST: float = 1.55
const MAX_OUTLIERS: int = 0
# Posed bounds may shrink/grow with stance, but not explode vs Idle.
const AABB_AXIS_MIN_RATIO: float = 0.50
const AABB_AXIS_MAX_RATIO: float = 1.65

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mint_loco_combat_pose smoke ===")
	var MintRef: Script = load("res://scripts/mint_character.gd") as Script
	_check(MintRef != null, "load MintCharacter")
	if MintRef == null:
		_finish()
		return

	var eli: Node = MintRef.load_profile("eli")
	_check(eli != null, "load_profile('eli')")
	if eli == null:
		_finish()
		return

	root.add_child(eli)
	await process_frame
	await process_frame
	await process_frame

	var skel: Skeleton3D = eli.call("find_skeleton") as Skeleton3D
	_check(skel != null, "eli Skeleton3D")
	if skel == null:
		eli.queue_free()
		_finish()
		return

	# --- Idle baseline ---
	eli.call("play", "Idle")
	eli.call("set_move_blend", 0.0, 0.0)
	eli.call("set_aim_blend", 0.0)
	await _settle(skel, 8)
	var idle: Dictionary = _posed_stats(skel, eli)
	_assert_human(idle, "Idle")
	var idle_size: Vector3 = idle["size"] as Vector3

	# --- Walk ---
	eli.call("set_move_blend", 1.0, 0.35)
	await _settle(skel, 12)
	var walk: Dictionary = _posed_stats(skel, eli)
	_assert_human(walk, "Walk")
	_assert_near_idle(idle_size, walk["size"] as Vector3, "Walk")

	# --- Walk + aim + fire (sidearm) — the real combat play path ---
	_check(eli.call("equip_weapon", "sidearm") == true, "equip sidearm")
	_check(eli.call("request_draw") == true, "draw sidearm")
	await create_timer(0.55).timeout
	_force_aimed(eli)
	eli.call("set_aim_blend", 1.0)
	eli.call("set_move_blend", 1.0, 0.35)
	await _settle(skel, 14)
	var walk_aim: Dictionary = _posed_stats(skel, eli)
	_assert_human(walk_aim, "Walk+Aim sidearm")
	_assert_near_idle(idle_size, walk_aim["size"] as Vector3, "Walk+Aim sidearm")
	_assert_spine_sane(skel, idle, walk_aim, "Walk+Aim sidearm")

	_check(eli.call("request_fire") == true, "fire sidearm while walking")
	# Sample mid-oneshot frames — distortion often spikes mid-fire, not at rest.
	for sample in 5:
		await _settle(skel, 3)
		var fire_stats: Dictionary = _posed_stats(skel, eli)
		_assert_human(fire_stats, "Walk+Fire sidearm t%d" % sample)
		_assert_near_idle(idle_size, fire_stats["size"] as Vector3, "Walk+Fire sidearm t%d" % sample)

	# --- Stun baton aim (the studio screenshot weapon) ---
	eli.call("request_holster")
	await create_timer(0.35).timeout
	_force_holstered(eli)
	eli.call("set_aim_blend", 0.0)
	_check(eli.call("equip_weapon", "stun_baton") == true, "equip stun baton")
	_check(eli.call("request_draw") == true, "draw stun baton")
	await create_timer(0.55).timeout
	_force_aimed(eli)
	eli.call("set_aim_blend", 1.0)
	eli.call("set_move_blend", 1.0, 0.2)
	await _settle(skel, 14)
	var baton: Dictionary = _posed_stats(skel, eli)
	_assert_human(baton, "Walk+Aim stun baton")
	_assert_near_idle(idle_size, baton["size"] as Vector3, "Walk+Aim stun baton")
	_check(
		str(eli.call("grip_status")).find("bones (") < 0 or int(baton.get("finger_bones", 0)) >= 10,
		"baton grip not driving phantom finger bones"
	)

	# Bone tips must stay on the body too (catches needle chains / flipped rests).
	_check(_max_bone_from_hip(skel) <= MAX_HIP_DIST + 0.15, "bone tips near hips while baton-aiming")

	eli.queue_free()
	_finish()


func _force_aimed(eli: Node) -> void:
	if str(eli.call("weapon_state_name")) == "AIMED":
		return
	var w: Node = eli.get_node_or_null("HeldWeapon")
	if w != null and w.has_method("notify_draw_finished"):
		w.call("notify_draw_finished")


func _force_holstered(eli: Node) -> void:
	if str(eli.call("weapon_state_name")) == "HOLSTERED":
		return
	var w: Node = eli.get_node_or_null("HeldWeapon")
	if w != null and w.has_method("notify_holster_finished"):
		w.call("notify_holster_finished")


func _settle(skel: Skeleton3D, frames: int) -> void:
	for _i in frames:
		await process_frame
	skel.force_update_all_bone_transforms()


func _assert_human(stats: Dictionary, label: String) -> void:
	var size: Vector3 = stats["size"] as Vector3
	var aabb_len: float = float(stats["aabb_len"])
	var max_hip: float = float(stats["max_hip"])
	var outliers: int = int(stats["outliers"])
	_check(size.y >= MIN_HEIGHT and size.y <= MAX_HEIGHT, "%s height in [%.2f, %.2f] (got %.3f)" % [label, MIN_HEIGHT, MAX_HEIGHT, size.y])
	_check(size.x <= MAX_LATERAL and size.z <= MAX_LATERAL, "%s lateral <= %.2f (got %.3f x %.3f)" % [label, MAX_LATERAL, size.x, size.z])
	_check(aabb_len <= MAX_AABB_LEN, "%s posed AABB length <= %.2f (got %.3f)" % [label, MAX_AABB_LEN, aabb_len])
	_check(max_hip <= MAX_HIP_DIST, "%s max vert-from-hip <= %.2f (got %.3f)" % [label, MAX_HIP_DIST, max_hip])
	_check(outliers <= MAX_OUTLIERS, "%s outlier verts beyond %.2fm from hip <= %d (got %d)" % [label, MAX_OUTLIER_HIP_DIST, MAX_OUTLIERS, outliers])


func _assert_spine_sane(_skel: Skeleton3D, idle: Dictionary, posed: Dictionary, label: String) -> void:
	# Catch aim-filter leaks: Gesture clips bend Spine/Head into spaghetti.
	var idle_head: float = float(idle.get("head_from_hip", 0.0))
	var posed_head: float = float(posed.get("head_from_hip", 0.0))
	_check(
		posed_head <= idle_head * 1.35 + 0.12,
		"%s head-from-hip stable (idle %.3f → %.3f)" % [label, idle_head, posed_head]
	)
	var idle_spine: Vector3 = idle.get("spine_w", Vector3.ZERO) as Vector3
	var posed_spine: Vector3 = posed.get("spine_w", Vector3.ZERO) as Vector3
	var spine_shift: float = idle_spine.distance_to(posed_spine)
	_check(spine_shift <= 0.35, "%s spine tip shift from idle <= 0.35m (got %.3f)" % [label, spine_shift])


func _assert_near_idle(idle_size: Vector3, size: Vector3, label: String) -> void:
	for axis in 3:
		var base: float = idle_size[axis]
		if base < 0.05:
			continue
		var ratio: float = size[axis] / base
		_check(
			ratio >= AABB_AXIS_MIN_RATIO and ratio <= AABB_AXIS_MAX_RATIO,
			"%s AABB axis %d within Idle ratio [%.2f, %.2f] (got %.2f)" % [label, axis, AABB_AXIS_MIN_RATIO, AABB_AXIS_MAX_RATIO, ratio]
		)


func _head_from_hip(skel: Skeleton3D) -> float:
	var hips: int = skel.find_bone("Hips")
	var head: int = skel.find_bone("Head")
	if hips < 0 or head < 0:
		return 0.0
	var hip_w: Vector3 = skel.to_global(skel.get_bone_global_pose(hips).origin)
	var head_w: Vector3 = skel.to_global(skel.get_bone_global_pose(head).origin)
	return hip_w.distance_to(head_w)


## CPU-skin every mesh vert under the live skeleton pose (GPU AABB is bind-pose).
func _posed_stats(skel: Skeleton3D, mesh_root: Node) -> Dictionary:
	var hips: int = skel.find_bone("Hips")
	var hip_w: Vector3 = (
		skel.to_global(skel.get_bone_global_pose(hips).origin) if hips >= 0 else skel.global_position
	)
	var head_from_hip: float = _head_from_hip(skel)
	var spine_i: int = skel.find_bone("Spine02")
	if spine_i < 0:
		spine_i = skel.find_bone("Spine")
	var spine_w: Vector3 = (
		skel.to_global(skel.get_bone_global_pose(spine_i).origin) if spine_i >= 0 else hip_w
	)
	var aabb := AABB()
	var first: bool = true
	var max_hip: float = 0.0
	var outliers: int = 0
	var finger_bones: int = 0
	for i in skel.get_bone_count():
		var nm: String = skel.get_bone_name(i)
		if (
			nm.find("Thumb") >= 0 or nm.find("Index") >= 0 or nm.find("Middle") >= 0
			or nm.find("Ring") >= 0 or nm.find("Little") >= 0 or nm.find("Pinky") >= 0
		):
			finger_bones += 1

	for node in _walk(mesh_root):
		if not (node is MeshInstance3D):
			continue
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		# Skip tiny prop meshes attached under the character (weapon GLBs).
		if mi != mesh_root and _is_under_name(mi, "HeldWeapon"):
			continue
		var skin: Skin = mi.skin
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			if arrays.is_empty():
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones_a: Variant = arrays[Mesh.ARRAY_BONES]
			var weights_a: Variant = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones_a == null or weights_a == null:
				continue
			var bone_ids: PackedInt32Array = bones_a as PackedInt32Array
			var weights: PackedFloat32Array = weights_a as PackedFloat32Array
			if bone_ids.size() < verts.size() * 4:
				continue
			for vi in verts.size():
				var p: Vector3 = Vector3.ZERO
				var wsum: float = 0.0
				for k in 4:
					var w: float = weights[vi * 4 + k]
					if w <= 0.0:
						continue
					var bi: int = bone_ids[vi * 4 + k]
					if bi < 0 or bi >= skin.get_bind_count():
						continue
					var bname: String = String(skin.get_bind_name(bi))
					var bidx: int = skel.find_bone(bname)
					if bidx < 0:
						bidx = skin.get_bind_bone(bi)
					if bidx < 0 or bidx >= skel.get_bone_count():
						continue
					p += (skel.get_bone_global_pose(bidx) * skin.get_bind_pose(bi) * verts[vi]) * w
					wsum += w
				if wsum <= 0.0:
					continue
				p /= wsum
				var world: Vector3 = skel.to_global(p)
				var d: float = world.distance_to(hip_w)
				max_hip = maxf(max_hip, d)
				if d > MAX_OUTLIER_HIP_DIST:
					outliers += 1
				if first:
					aabb = AABB(world, Vector3.ZERO)
					first = false
				else:
					aabb = aabb.expand(world)

	return {
		"size": aabb.size,
		"aabb_len": aabb.size.length(),
		"max_hip": max_hip,
		"outliers": outliers,
		"finger_bones": finger_bones,
		"head_from_hip": head_from_hip,
		"spine_w": spine_w,
	}


func _max_bone_from_hip(skel: Skeleton3D) -> float:
	var hips: int = skel.find_bone("Hips")
	if hips < 0:
		return 0.0
	var hip_w: Vector3 = skel.to_global(skel.get_bone_global_pose(hips).origin)
	var farthest: float = 0.0
	for i in skel.get_bone_count():
		var p: Vector3 = skel.to_global(skel.get_bone_global_pose(i).origin)
		farthest = maxf(farthest, p.distance_to(hip_w))
	return farthest


func _is_under_name(node: Node, name: String) -> bool:
	var cur: Node = node
	while cur != null:
		if cur.name == name:
			return true
		cur = cur.get_parent()
	return false


func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n == null:
		return out
	out.append(n)
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


func _check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s" % label)


func _finish() -> void:
	print("=== summary ===")
	print("passes: %d  fails: %d" % [_passes, _fails])
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
