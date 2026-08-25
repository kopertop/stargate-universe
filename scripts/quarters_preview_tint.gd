@tool
extends Node3D

# Minimal tint pass for the quarters workbench. Kenney GLBs lose their
# embedded textures on import (see feedback_gltf_embedded_texture_lost),
# so without this every furniture piece would render pure white in the
# editor. We just walk the named children and stamp each one's meshes
# with a sensible tint.
#
# Editing layout: click any child node (Bed, Nightstand, ...) in the
# scene tree and drag with the W/E/R gizmos. The script doesn't interfere
# with transforms — it only paints albedo on first load.

const TINTS: Dictionary = {
	"Bed":        Color(0.62, 0.58, 0.52),
	"Locker":     Color(0.38, 0.40, 0.44),
	"Desk":       Color(0.45, 0.40, 0.35),
	"Chair":      Color(0.30, 0.32, 0.36),
}


func _ready() -> void:
	for prop_name in TINTS.keys():
		var node: Node = get_node_or_null(prop_name)
		if node == null:
			continue
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = TINTS[prop_name]
		mat.metallic = 0.0
		mat.roughness = 0.55
		_apply_material_recursive(node, mat)


static func _apply_material_recursive(root: Node, mat: StandardMaterial3D) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		var surf_count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i in surf_count:
			mi.set_surface_override_material(i, mat)
	for child in root.get_children():
		_apply_material_recursive(child, mat)
