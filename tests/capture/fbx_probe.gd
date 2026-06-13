extends SceneTree

# Diagnostic: dump an imported Mixamo FBX scene — skeleton bone names,
# animation clips + track paths. Tells us the exact bone naming for the
# retarget BoneMap and whether tracks landed on humanoid names.
#   FBX=walking godot --headless --quit-after 240 -s res://tests/capture/fbx_probe.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stem: String = OS.get_environment("FBX")
	if stem == "":
		stem = "walking"
	var packed: PackedScene = load("res://models/vrm/anim_src/%s.fbx" % stem)
	if packed == null:
		print("[fbx_probe] FAILED to load %s.fbx" % stem)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	print("=== %s.fbx tree ===" % stem)
	_dump(inst, 0)
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var sk: Skeleton3D = n
			print("Skeleton '%s' unique=%s bones=%d motion_scale=%.3f" % [
				sk.name, sk.unique_name_in_owner, sk.get_bone_count(), sk.motion_scale])
			for i in range(mini(sk.get_bone_count(), 60)):
				print("  [%d] %s" % [i, sk.get_bone_name(i)])
		if n is AnimationPlayer:
			var ap: AnimationPlayer = n
			for a in ap.get_animation_list():
				var anim: Animation = ap.get_animation(a)
				print("Animation '%s' length=%.2f loop=%d tracks=%d" % [a, anim.length, anim.loop_mode, anim.get_track_count()])
				for t in range(mini(anim.get_track_count(), 5)):
					print("   track[%d] %s (type %d)" % [t, anim.track_get_path(t), anim.track_get_type(t)])
		for c in n.get_children():
			stack.append(c)
	quit()


func _dump(node: Node, depth: int) -> void:
	if depth > 3:
		return
	print("%s- %s (%s)" % ["  ".repeat(depth), node.name, node.get_class()])
	for c in node.get_children():
		_dump(c, depth + 1)
