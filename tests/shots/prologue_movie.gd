extends SceneTree

# Movie-Maker driver: play the REAL first-visit gate-room arrival cinematic and
# quit once it's done, so `--write-movie` captures the whole opening as a video.
# Deterministic under --fixed-fps (each frame advances time by 1/fps), so the
# cinematic's create_timer beats line up frame-for-frame.
#
#   godot --rendering-driver metal --resolution 1280x720 --fixed-fps 30 \
#         --write-movie user://prologue.avi -s res://tests/shots/prologue_movie.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "prologue_movie")
	# Genuine first visit → _run_arrival plays the full cinematic. (No instant_mode,
	# no pre-discover.)
	var inst: Node = (load("res://scenes/gate_room.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	await process_frame
	# Hide the HUD for a clean cinematic frame.
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false

	# Run long enough for the whole cinematic (dial + 2 waves + groggy staggered
	# recovery ~33s) plus Scott's walk-up + first dialog beat. At 30fps ≈ 38s.
	var frames: int = 1140
	for i in frames:
		await process_frame
	quit(0)
