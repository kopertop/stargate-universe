extends SceneTree

# Drive the REAL first-visit arrival cinematic (NOT instant_mode) and snapshot
# its beats by sim-time so we can verify: dial/spin -> kawoosh -> ragdoll crew
# burst -> crew landed -> Eli stands. The cinematic builds its own PrologueCam,
# so we just grab the viewport at each mark.
#
#   godot --quit-after 1200 -s res://tests/shots/prologue_shot.gd ++ out=user://prologue

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var prefix := String(args.get("out", "user://prologue"))

	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "prologue_shot")
	# IMPORTANT: do NOT set instant_mode and do NOT pre-discover gate_room — we want
	# the genuine first-visit cinematic path to run.

	var inst: Node = (load("res://scenes/gate_room.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	# Hide the HUD so captures are clean architectural frames.
	await process_frame
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer: (hud as CanvasLayer).visible = false

	# Snapshot marks (seconds) chosen against the cinematic timeline:
	# 0.8 beat + 3.2 dial + kawoosh + ~2.7 eject + 0.6 + reveal + 0.4 + 1.1 standup.
	var marks := [
		[4.3, prefix + "_2_flush.png"],
		[5.6, prefix + "_3_scott_through.png"],
		[8.6, prefix + "_5_wave2.png"],
		[11.6, prefix + "_6_landed.png"],
		[13.2, prefix + "_7_recover.png"],
		[15.6, prefix + "_8_consoles.png"],
		[19.0, prefix + "_9_final.png"],
	]
	var elapsed := 0.0
	for m in marks:
		var target: float = float(m[0])
		await create_timer(target - elapsed).timeout
		elapsed = target
		var curcam: Camera3D = root.get_viewport().get_camera_3d()
		var cam_name: String = curcam.name if curcam != null else "<none>"
		var img: Image = root.get_viewport().get_texture().get_image()
		img.save_png(String(m[1]))
		print("SHOT ", m[1], " cam=", cam_name)
	quit(0)
