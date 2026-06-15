extends SceneTree

# Render a contact sheet of the Animation Lab grid (every crew_body clip on the
# modular rig, labelled) so the catalogue can be eyeballed without launching the
# interactive scene. Run WITHOUT --headless so a real frame is produced:
#   godot --quit-after 240 -s res://tests/shots/anim_lab_shot.gd ++ out=user://anim_lab.png

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var out_path := String(args.get("out", "user://anim_lab.png"))

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "anim_lab_shot")

	var lab: Node = (load("res://scenes/anim_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	current_scene = lab
	# Let _ready probe the clip list, build the grid, and the anims advance a bit.
	for i in 90:
		await process_frame

	var img: Image = root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("SHOT ", out_path, " err=", err)
	quit(0)
