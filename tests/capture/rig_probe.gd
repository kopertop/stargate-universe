extends SceneTree

# Diagnostic: dump the imported node tree + Skeleton3D bone names + bone rest
# transforms for a character GLB, so we know what BoneAttachment3D targets exist.
#   CHAR_MODEL=greer godot --headless --quit-after 120 -s res://tests/capture/rig_probe.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stem: String = OS.get_environment("CHAR_MODEL")
	if stem == "":
		stem = "greer"
	var glb: PackedScene = load("res://models/characters/%s.glb" % stem)
	if glb == null:
		print("no model: ", stem)
		quit(1)
		return
	var inst: Node = glb.instantiate()
	print("=== node tree for %s.glb ===" % stem)
	_dump(inst, 0)
	print("=== skeletons ===")
	_dump_skeletons(inst)
	quit()


func _dump(node: Node, depth: int) -> void:
	var extra: String = ""
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		extra = " [mesh, skin=%s]" % (mi.skin != null)
	elif node is Skeleton3D:
		extra = " [Skeleton3D, %d bones]" % (node as Skeleton3D).get_bone_count()
	elif node is AnimationPlayer:
		extra = " [AnimationPlayer: %s]" % String(", ").join((node as AnimationPlayer).get_animation_list())
	print("%s- %s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), extra])
	for c in node.get_children():
		_dump(c, depth + 1)


func _dump_skeletons(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var sk: Skeleton3D = n
			print("Skeleton '%s' — %d bones:" % [sk.name, sk.get_bone_count()])
			for i in range(sk.get_bone_count()):
				var rest: Transform3D = sk.get_bone_global_rest(i)
				print("  [%d] %-12s parent=%d  rest_origin=%s" % [
					i, sk.get_bone_name(i), sk.get_bone_parent(i),
					rest.origin])
		for c in n.get_children():
			stack.append(c)
