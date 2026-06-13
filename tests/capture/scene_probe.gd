extends SceneTree

# Generic imported-scene probe: tree, skeleton bones, skin binds, animations.
#   SCENE=res://models/quaternius/base/Superhero_Male_FullBody.gltf \
#     godot --headless --quit-after 240 -s res://tests/capture/scene_probe.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path: String = OS.get_environment("SCENE")
	var packed: PackedScene = load(path)
	if packed == null:
		print("[probe] FAILED to load %s" % path)
		quit(1)
		return
	var inst: Node = packed.instantiate()
	print("=== %s ===" % path.get_file())
	_dump(inst, 0)
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var sk: Skeleton3D = n
			print("Skeleton '%s' bones=%d motion_scale=%.3f" % [sk.name, sk.get_bone_count(), sk.motion_scale])
			for i in range(mini(sk.get_bone_count(), 70)):
				print("  [%d] %s" % [i, sk.get_bone_name(i)])
		if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
			var skin: Skin = (n as MeshInstance3D).skin
			print("Mesh '%s': %d binds, first names: %s | %s" % [
				n.name, skin.get_bind_count(), skin.get_bind_name(0),
				skin.get_bind_name(mini(1, skin.get_bind_count() - 1))])
		if n is AnimationPlayer:
			print("Anims: %s" % ", ".join((n as AnimationPlayer).get_animation_list()))
		for c in n.get_children():
			stack.append(c)
	quit()


func _dump(node: Node, depth: int) -> void:
	if depth > 3:
		return
	print("%s- %s (%s)" % ["  ".repeat(depth), node.name, node.get_class()])
	for c in node.get_children():
		_dump(c, depth + 1)
