extends SceneTree

# Probe the new gunmetal gate ring: native world-space AABB (size+center) and
# surface validity, so gate_room can place it floor-pinned at the right scale.
#   godot --headless -s res://tests/shots/gate_probe.gd

const PATH := "res://models/sci-fi/stargate-props/gunmetal-gate-no-glyphs.glb"

func _initialize() -> void:
	var ps: PackedScene = load(PATH) as PackedScene
	if ps == null:
		print("PROBE LOAD_FAILED")
		quit(1)
		return
	var inst: Node = ps.instantiate()
	var res: Array = _walk(inst, Transform3D.IDENTITY, AABB(), true, 0, 0)
	var merged: AABB = res[1]
	print("PROBE gunmetal-gate")
	print("   meshes=", res[2], " empty=", res[3])
	print("   world_size=", merged.size.snappedf(0.001), " center=", merged.get_center().snappedf(0.001))
	# Thin axis = ring's facing axis. Report each axis explicitly.
	print("   size.x=", merged.size.x, " size.y=", merged.size.y, " size.z=", merged.size.z)
	# Inner-radius scan: ring lies in YZ plane (thin X). Find min radial distance
	# (in YZ) of any vertex near the X=0 mid-plane -> the hole's inner edge.
	var min_r := 999.0
	var max_r := 0.0
	_scan_radii(inst, Transform3D.IDENTITY, [min_r, max_r])
	var rr := _scan(inst, Transform3D.IDENTITY)
	print("   inner_radius~", rr[0], " outer_radius~", rr[1])
	inst.free()
	quit(0)

func _scan_radii(_n, _x, _a) -> void:
	pass

# Returns [min_radius, max_radius] in the YZ plane across all surface verts.
func _scan(node: Node, xf: Transform3D) -> Array:
	var lx := xf
	if node is Node3D:
		lx = xf * (node as Node3D).transform
	var mn := 999.0
	var mx := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
				for v in arr[Mesh.ARRAY_VERTEX]:
					var w: Vector3 = lx * v
					var r := sqrt(w.y * w.y + w.z * w.z)
					if r < mn: mn = r
					if r > mx: mx = r
	for c in node.get_children():
		var sub := _scan(c, lx)
		if sub[0] < mn: mn = sub[0]
		if sub[1] > mx: mx = sub[1]
	return [mn, mx]

func _walk(node: Node, xf: Transform3D, merged: AABB, first: bool, meshes: int, empty: int) -> Array:
	var local_xf: Transform3D = xf
	if node is Node3D:
		local_xf = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			meshes += 1
			var box: AABB = local_xf * mi.get_aabb()
			if first:
				merged = box; first = false
			else:
				merged = merged.merge(box)
		else:
			empty += 1
	for c in node.get_children():
		var r: Array = _walk(c, local_xf, merged, first, meshes, empty)
		first = r[0]; merged = r[1]; meshes = r[2]; empty = r[3]
	return [first, merged, meshes, empty]
