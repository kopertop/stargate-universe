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

	# Snapshot marks (seconds) chosen against the revised cinematic timeline:
	# 0.8 pre-dial + 3.2 dial + 0.6 kawoosh stabilise
	# + 1.3 scott-settle + 1.5 scott-getup + 0.6 inter-wave
	# + 7×0.14 (launches) + 2.8 tumble + 1.1 freeze-wait
	# + 0.5 eli-reveal + 0.5 gate-collapse + 4.5 crew-standup + 0.3 eli-beat + 1.4 eli-up
	# ≈ 24s total.
	var marks := [
		[4.3,  prefix + "_2_flush.png"],           # kawoosh portal open
		[6.5,  prefix + "_3_scott_crumpled.png"],  # scott crumpled on deck (wave 1)
		[8.4,  prefix + "_4_scott_up.png"],        # scott standing, radio clear
		[11.2, prefix + "_5_wave2.png"],           # wave 2 burst through gate
		[14.5, prefix + "_6a_all_crumpled.png"],   # everyone crumpled, none standing
		[17.5, prefix + "_6b_park_up.png"],        # park/volker mid-stand; scott standing
		[20.5, prefix + "_7_recovery.png"],        # rush/brody walking out, crew at posts
		[24.0, prefix + "_8_final.png"],           # eli standing; young down; james kneeling
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
