extends SceneTree

# Probe the stargate-prop pack: load each glb, instantiate, and report the
# merged world-space AABB (size + center) plus a count of valid vs empty mesh
# surfaces. Tells us each prop's native scale/pivot so gate_room can place them
# correctly instead of guessing.
#
#   godot --headless -s res://tests/shots/prop_probe.gd

const DIR := "res://models/sci-fi/stargate-props/"
const FILES := [
	"sci-fi-stargate-props-stargate-portal-ring.glb",
	"sci-fi-stargate-props-raised-circular-platform.glb",
	"sci-fi-stargate-props-metal-staircase-steps.glb",
	"sci-fi-stargate-props-operator-control-console.glb",
	"sci-fi-stargate-props-overhead-ceiling-ring-structure.glb",
	"sci-fi-stargate-props-spotlight-ceiling-light.glb",
	"sci-fi-stargate-props-industrial-wall-column.glb",
	"sci-fi-stargate-props-catwalk-railing-segment.glb",
]

func _initialize() -> void:
	for f in FILES:
		var ps: PackedScene = load(DIR + f) as PackedScene
		if ps == null:
			print("PROBE ", f, " LOAD_FAILED")
			continue
		var inst: Node = ps.instantiate()
		var res: Array = _walk(inst, Transform3D.IDENTITY, AABB(), true, 0, 0)
		var merged: AABB = res[1]
		print("PROBE ", f)
		print("   meshes=", res[2], " empty=", res[3],
			" world_size=", merged.size.snappedf(0.01), " center=", merged.get_center().snappedf(0.01))
		inst.free()
	quit(0)


# Accumulate world-space AABB across the full transform chain.
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
