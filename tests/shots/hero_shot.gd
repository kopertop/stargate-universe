extends SceneTree

# Minimal render harness for the hero gate-room beauty shot. Boots ONLY
# scenes/gate_room_hero.tscn (no gameplay HUD), sizes the window to the concept
# frame's 16:9, lets the portal shader churn a few seconds so the vortex is mid-
# animation, then saves a PNG. Used by tools/gate_hero_render.sh and the
# gate-room-hero self-improvement loop.
#
# Run WITHOUT --headless (that disables rendering → blank PNG) and with the
# project's default Forward+ renderer so SSR / volumetric fog / glow all apply.
#
#   godot --quit-after 600 -s res://tests/shots/hero_shot.gd ++ out=user://hero.png wait=120

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := _parse_args()
	var out_path := String(args.get("out", "user://hero.png"))
	var wait_frames := int(args.get("wait", "120"))

	# Keep autosave off the player's real file even though this scene is decoupled.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths", "hero_shot")

	DisplayServer.window_set_size(Vector2i(1280, 720))

	var packed := load("res://scenes/gate_room_hero.tscn") as PackedScene
	if packed == null:
		print("SHOT_ERROR could not load hero scene")
		quit(1)
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	current_scene = inst

	for i in wait_frames:
		await process_frame

	var cam := root.get_viewport().get_camera_3d()
	if cam != null:
		print("CAM pos=", cam.global_position, " fwd=", -cam.global_transform.basis.z)
	else:
		print("SHOT_WARN no camera")

	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("SHOT ", out_path, " (save err=", err, ")")
	quit(0)

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		var eq := s.find("=")
		if eq > 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out
