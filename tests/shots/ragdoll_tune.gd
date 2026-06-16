extends SceneTree

# Karpathy-loop scorer for the gate-throw PROJECTILE arc. Throws ONE crew body
# with the REAL gate_room code (so it reflects the live THROW_* constants), tracks
# the body's flight, and prints an objective METRICS line the loop maximises:
#   apex     — peak height of the arc (m); a good throw clears head height but not the ceiling
#   travel   — horizontal distance covered gate→landing (m); proves it flew, not flopped
#   land_err — horizontal distance of the settled body from the aimed spot (m); want ~0
#   score    — 100 - 12*land_err - 4*|apex - APEX_IDEAL| - 6*max(0, head_clear-apex)
# Side camera writes a profile PNG of the arc for eyeballing.
#
#   godot --quit-after 600 -s res://tests/shots/ragdoll_tune.gd ++ out=user://ragdoll shot=1

const TARGET := Vector3(3.5, 0.05, -3.0)
const APEX_IDEAL := 4.6     # a satisfying arc height (clears a standing crewman ~1.9 m)
const HEAD_CLEAR := 2.4     # the arc should rise at least this high

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a); var eq := s.find("=")
		if eq > 0: args[s.substr(0, eq)] = s.substr(eq + 1)
	var want_shot := String(args.get("shot", "0")) == "1"
	var prefix := String(args.get("out", "user://ragdoll"))

	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("configure_test_paths", "ragdoll_tune")
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)   # skip the cinematic; we throw our own body

	var inst: Node = (load("res://scenes/gate_room.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	for i in 6:
		await process_frame
	var hud: Node = inst.get_node_or_null("HUDLayer")
	if hud is CanvasLayer: (hud as CanvasLayer).visible = false

	# Empty the room (the real cinematic throws into a cleared room).
	if inst.has_method("_set_arrival_crew_visible"):
		inst.call("_set_arrival_crew_visible", false)
	var world: Node = inst.get_node_or_null("World")
	if world == null:
		world = inst
	for child in world.get_children():
		if child is StaticBody3D and (child as Node).get_node_or_null("Model") != null:
			(child as CollisionObject3D).collision_layer = 0
			(child as Node3D).visible = false

	# Side camera — profile of the flight (gate at +Z, body flies toward -Z).
	var cam := Camera3D.new(); cam.fov = 55.0
	inst.add_child(cam)
	cam.global_position = Vector3(15.0, 4.0, 3.5)
	cam.look_at(Vector3(0.0, 2.0, 3.0), Vector3.UP)
	cam.make_current()

	var npc: Node3D = inst.call("_throw_persistent_crew", "Sgt Greer", "", TARGET, null)
	if npc == null:
		print("METRICS error=no_npc score=-999"); quit(0); return

	var origin: Vector3 = npc.global_position
	var apex := origin.y
	var travel := 0.0
	var frames := 120
	var shot_at := 26
	for f in range(frames):
		await process_frame
		var p: Vector3 = npc.global_position
		apex = maxf(apex, p.y)
		travel = maxf(travel, Vector2(p.x - origin.x, p.z - origin.z).length())
		if want_shot and f == shot_at:
			root.get_viewport().get_texture().get_image().save_png(prefix + "_flight.png")

	inst.call("_settle_persistent_crew", npc, "knockback")
	await process_frame
	await process_frame
	var landed: Vector3 = npc.global_position
	var land_err := Vector2(landed.x - TARGET.x, landed.z - TARGET.z).length()
	if want_shot:
		await create_timer(0.3).timeout
		root.get_viewport().get_texture().get_image().save_png(prefix + "_settled.png")

	var score := 100.0 - 12.0 * land_err - 4.0 * absf(apex - APEX_IDEAL) - 6.0 * maxf(0.0, HEAD_CLEAR - apex)
	print("METRICS apex=%.2f travel=%.2f land_err=%.3f score=%.3f" % [apex, travel, land_err, score])
	quit(0)
