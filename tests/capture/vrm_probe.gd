extends SceneTree

# Diagnostic: load an imported VRM and dump its node tree, skeleton bones,
# animation list (godot-vrm imports expressions as animations), blend shape
# counts, and VRM metadata — the ground truth for building the VRM pipeline.
#   VRM=eli godot --headless --quit-after 240 -s res://tests/capture/vrm_probe.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stem: String = OS.get_environment("VRM")
	if stem == "":
		stem = "eli"
	var packed: PackedScene = load("res://models/vrm/%s.vrm" % stem)
	if packed == null:
		print("[vrm_probe] FAILED to load res://models/vrm/%s.vrm" % stem)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	print("=== %s.vrm node tree ===" % stem)
	_dump(inst, 0)
	print("=== skeleton ===")
	_dump_skeleton(inst)
	print("=== animations ===")
	_dump_anims(inst)
	print("=== meshes/blendshapes ===")
	_dump_meshes(inst)
	print("=== vrm meta ===")
	var meta: Variant = inst.get("vrm_meta")
	if meta != null:
		for p in ["title", "version", "author", "spec_version", "humanoid_bone_mapping"]:
			var v: Variant = meta.get(p)
			if v != null and str(v) != "":
				print("  %s: %s" % [p, str(v).left(120)])
	quit()


func _dump(node: Node, depth: int) -> void:
	if depth > 4:
		return
	var extra: String = " (" + node.get_class() + ")"
	if node.get_script() != null:
		extra += " script=" + String(node.get_script().resource_path).get_file()
	print("%s- %s%s" % ["  ".repeat(depth), node.name, extra])
	for c in node.get_children():
		_dump(c, depth + 1)


func _dump_skeleton(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var sk: Skeleton3D = n
			print("Skeleton '%s': %d bones; motion_scale=%.3f" % [sk.name, sk.get_bone_count(), sk.motion_scale])
			var wanted: Array = ["Hips", "Spine", "Chest", "Head", "RightHand", "LeftHand",
				"RightLowerArm", "RightIndexProximal", "RightThumbProximal", "LeftFoot"]
			for w in wanted:
				print("  find_bone(%s) = %d" % [w, sk.find_bone(w)])
			return
		for c in n.get_children():
			stack.append(c)
	print("  (no Skeleton3D found)")


func _dump_anims(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			var ap: AnimationPlayer = n
			print("AnimationPlayer '%s' (%d clips): %s" % [
				ap.name, ap.get_animation_list().size(),
				", ".join(ap.get_animation_list())])
		for c in n.get_children():
			stack.append(c)


func _dump_meshes(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			var bs: int = 0
			if mi.mesh != null:
				bs = mi.mesh.get_blend_shape_count() if mi.mesh is ArrayMesh else 0
			print("  mesh=%s surfaces=%d blendshapes=%d" % [
				mi.name, mi.mesh.get_surface_count() if mi.mesh != null else 0, bs])
		for c in n.get_children():
			stack.append(c)
