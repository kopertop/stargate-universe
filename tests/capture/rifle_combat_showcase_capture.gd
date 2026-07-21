extends SceneTree

# Auto-demo capture: stop / run / kneel fire modes with VFX.
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
	await process_frame
	await process_frame

	# Force modes and capture mid-burst (tracers / muzzle still alive).
	DisplayServer.window_set_size(Vector2i(1600, 900))
	if root_n.has_method("_apply_mode"):
		for mode_i in 3:
			root_n.set("_auto", false)
			root_n.call("_apply_mode", mode_i)
			if root_n.has_method("_refresh_label"):
				root_n.call("_refresh_label")
			await _settle(30)
			# Warm-up shots then capture while bolts are in flight
			for _s in 4:
				if root_n.has_method("_fire_shot"):
					root_n.call("_fire_shot")
				await _settle(2)
			if root_n.has_method("_fire_shot"):
				root_n.call("_fire_shot")
			await _settle(2)
			await RenderingServer.frame_post_draw
			var img: Image = root.get_viewport().get_texture().get_image()
			var names: Array[String] = ["stop_fire", "run_fire", "kneel_fire"]
			var path: String = "%s/combat_%s.png" % [OUT_DIR, names[mode_i]]
			img.save_png(ProjectSettings.globalize_path(path))
			print("[shot] ", path, " size=", img.get_size())

	print("=== rifle_combat_showcase_capture done ===")
	quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame
