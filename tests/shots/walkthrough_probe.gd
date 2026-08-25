extends SceneTree

# Verify the floor-pinned gate is walk-through: a player-sized capsule swept along
# the deck through the ring opening must NOT collide with the GateRing at any
# point. Prints CLEAR / BLOCKED per sample z so we know you can walk straight
# through without jumping.
#   godot --quit-after 200 -s res://tests/shots/walkthrough_probe.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "walkthrough_probe")
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null and gs.has_method("discover_room"):
		gs.call("discover_room", "gate_room", "Gate Room")
	var sr: Node = root.get_node_or_null("SceneRouter")
	if sr != null:
		sr.set("instant_mode", true)

	var inst: Node = (load("res://scenes/gate_room.tscn") as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	for i in 8:
		await process_frame

	var space: PhysicsDirectSpaceState3D = inst.get_world_3d().direct_space_state
	# Player capsule: radius 0.35, height 1.8 → centre at y≈0.9.
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	var gate_z := 12.2
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = cap
	params.collision_mask = 1   # floor/walls/ring live on layer 1
	var blocked := 0
	var clear := 0
	# Sweep from 3 m south of the ring to 3 m north, straight through the centre.
	for i in 25:
		var z := gate_z - 3.0 + float(i) * 0.25
		params.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, z))
		var hits: Array[Dictionary] = space.intersect_shape(params, 8)
		var on_ring := false
		for h in hits:
			var col: Object = h.get("collider")
			if col != null and String(col.get_parent().name).contains("GateRing"):
				on_ring = true
		if on_ring:
			blocked += 1
			print("  z=", snappedf(z, 0.01), " BLOCKED by ring")
		else:
			clear += 1
	print("WALKTHROUGH clear=", clear, " blocked=", blocked,
		"  => ", ("PASS (walk straight through)" if blocked == 0 else "FAIL (ring blocks path)"))
	quit(0)
