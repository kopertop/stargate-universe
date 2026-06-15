extends SceneTree

# Drive the REAL first-visit arrival cinematic (NOT instant_mode) and snapshot
# its beats by sim-time so we can verify: dial/spin -> kawoosh -> ragdoll crew
# burst -> crew landed -> Eli stands. The cinematic builds its own PrologueCam,
# so we just grab the viewport at each mark.
#
#   godot --quit-after 1500 -s res://tests/shots/prologue_shot.gd ++ out=user://prologue

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

	# Snapshot marks (seconds) for the paired-wave cinematic (~23s): dial → Scott
	# (solo) → Young+James → Park+Volker → Eli → settle.
	var marks := [
		[4.5,  prefix + "_2_flush.png"],        # kawoosh flush toward camera
		[6.8,  prefix + "_3_scott.png"],        # Scott landed/standing (wave 1)
		[11.0, prefix + "_4_young_james.png"],  # Young + James down (wave 2)
		[15.5, prefix + "_5_park_volker.png"],  # Park + Volker at consoles (wave 3)
		[20.5, prefix + "_6_eli.png"],          # Eli landed (wave 4)
		[24.5, prefix + "_7_final.png"],        # settled room
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
