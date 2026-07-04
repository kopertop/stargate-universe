extends SceneTree

# Dump VRoid Body/Face mesh SURFACE material names — VRoid names materials by
# garment (Tops/Bottoms/Shoes/Accessory/SKIN), which is the key to per-slot
# gear extraction. Headless:
#   godot --headless --quit-after 240 -s res://tests/capture/vrm_surface_probe.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for stem in ["eli", "scott"]:
		var inst: Node = (load("res://models/vrm/%s.vrm" % stem) as PackedScene).instantiate()
		print("=== %s ===" % stem)
		var stack: Array = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				var mi: MeshInstance3D = n
				if mi.mesh == null:
					continue
				print(" mesh=%s (%d surfaces)" % [mi.name, mi.mesh.get_surface_count()])
				for s in range(mi.mesh.get_surface_count()):
					var mat: Material = mi.mesh.surface_get_material(s)
					var mat_name: String = mat.resource_name if mat != null else "(none)"
					print("   [%d] %s" % [s, mat_name])
			for c in n.get_children():
				stack.append(c)
		inst.free()
	quit()
