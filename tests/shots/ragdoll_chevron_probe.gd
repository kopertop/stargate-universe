extends SceneTree

# Requirements probe for the ragdoll + chevron-alignment tasks:
#  (1) Build a modular crew member, find its Skeleton3D, report bone count + a few
#      bone names + whether a humanoid hierarchy exists (feasibility of Godot's
#      PhysicalBone3D ragdoll via physical_bones_start_simulation()).
#  (2) Analyse the gunmetal ring mesh: bin vertices by angle in the ring (YZ)
#      plane and report where the ring protrudes most along its thin axis (X) →
#      the chevron angular positions so the glow markers can line up.
#   godot --headless -s res://tests/shots/ragdoll_chevron_probe.gd

const RING := "res://models/sci-fi/stargate-props/gunmetal-gate-no-glyphs.glb"
const CF := preload("res://scripts/character_factory.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# (1) Skeleton feasibility.
	var mc: Node3D = CF.build_modular("Lt Scott")
	root.add_child(mc)
	await process_frame
	var skel: Skeleton3D = _find_skeleton(mc)
	if skel == null:
		print("SKEL none found")
	else:
		var n := skel.get_bone_count()
		print("SKEL bones=", n)
		var sample: Array = []
		for i in mini(n, n):
			sample.append(skel.get_bone_name(i))
		print("SKEL names=", sample)
		# Existing PhysicalBone3D children?
		var pb := 0
		for c in skel.get_children():
			if c is PhysicalBone3D:
				pb += 1
		print("SKEL physical_bones=", pb)
	mc.queue_free()

	# (2) Chevron angular positions on the ring.
	var ps: PackedScene = load(RING) as PackedScene
	var inst: Node = ps.instantiate()
	var bins := {}
	var nb := 72   # 5-degree bins
	for i in nb:
		bins[i] = 0.0
	_bin(inst, Transform3D.IDENTITY, bins, nb)
	# Print the bin profile so peaks (chevrons) are visible.
	var line := ""
	for i in nb:
		line += "%d:%.2f " % [i * 5, bins[i]]
	print("RING_PROFILE(deg:maxX) ", line)
	inst.free()
	quit(0)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null

# Bin the max |X| (thin-axis protrusion) of mesh vertices by their angle in the
# YZ plane. Chevrons stick out / are thicker, so their bins peak.
func _bin(node: Node, xf: Transform3D, bins: Dictionary, nb: int) -> void:
	var lx := xf
	if node is Node3D:
		lx = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
				for v in arr[Mesh.ARRAY_VERTEX]:
					var w: Vector3 = lx * v
					var ang := atan2(w.z, w.y)   # YZ-plane angle
					var deg := fmod(rad_to_deg(ang) + 360.0, 360.0)
					var b := int(deg / (360.0 / float(nb))) % nb
					var ax: float = absf(w.x)
					if ax > float(bins[b]):
						bins[b] = ax
	for c in node.get_children():
		_bin(c, lx, bins, nb)
