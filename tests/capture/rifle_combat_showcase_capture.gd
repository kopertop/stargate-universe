extends SceneTree

# Capture holster / aim-run / aim-crouch stills from the gameplay showcase.
#   Godot --path . --quit-after 20000 -s res://tests/capture/rifle_combat_showcase_capture.gd

const OUT_DIR: String = "res://screenshots/result/mint_rifle_aim"
const SCENE: String = "res://scenes/rifle_combat_showcase.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== rifle_combat_showcase_capture ===")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load(SCENE) as PackedScene
	var root_n: Node = packed.instantiate()
	root.add_child(root_n)
	# Wait for CharacterBody drop + foot align + mouse capture path.
	for _i in 90:
		await process_frame

	DisplayServer.window_set_size(Vector2i(1600, 900))
	var poses: Array[String] = ["holster", "aim_run", "aim_crouch"]
	var names: Array[String] = ["holster", "aim_run", "aim_crouch"]
	if root_n.has_method("apply_capture_pose"):
		for i in poses.size():
			root_n.call("apply_capture_pose", poses[i])
			await _settle(36)
			if poses[i] != "holster":
				for _s in 4:
					if root_n.has_method("_fire_shot"):
						root_n.call("_fire_shot")
					await _settle(2)
				if root_n.has_method("_fire_shot"):
					root_n.call("_fire_shot")
				await _settle(2)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			var path: String = "%s/combat_%s.png" % [OUT_DIR, names[i]]
			img.save_png(ProjectSettings.globalize_path(path))
			print("[shot] ", path, " size=", img.get_size())
	else:
		push_error("showcase missing apply_capture_pose()")

	print("=== rifle_combat_showcase_capture done ===")
	quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
