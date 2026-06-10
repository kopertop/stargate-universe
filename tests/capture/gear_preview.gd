extends SceneTree

# Gear close-up: renders each gear builder's output at large scale and dumps
# transform/AABB diagnostics. Run NON-headless:
#   godot --quit-after 600 -s res://tests/capture/gear_preview.gd

const FactoryRef: Script = preload("res://scripts/character_factory.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.3
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	world.add_child(sun)

	var gear_ids: Array[String] = ["sidearm", "rifle", "helmet"]
	for i in range(gear_ids.size()):
		var holder: Node3D = Node3D.new()
		holder.position = Vector3(i * 2.4 - 2.4, 1.0, 0.0)
		world.add_child(holder)
		var gear: Node3D = FactoryRef.add_gear(holder, gear_ids[i])
		if gear == null:
			print("[gear] %s -> NULL" % gear_ids[i])
			continue
		gear.position = Vector3.ZERO
		gear.scale = Vector3.ONE * 2.0
		# Profile view: gear barrels run along Z (toward the camera); yaw 90 so
		# the silhouette reads instead of an end-on dot.
		gear.rotation = Vector3(0.0, PI * 0.5, 0.0)
		print("[gear] %s children=%d" % [gear_ids[i], gear.get_child_count()])
		for c in gear.get_children():
			if c is Node3D:
				var c3: Node3D = c
				print("        child=%s pos=%s scale=%s rot=%s" % [c3.name, c3.position, c3.scale, c3.rotation])
		var aabb: AABB = FactoryRef._merged_aabb(gear)
		print("        merged_aabb pos=%s size=%s" % [aabb.position, aabb.size])
		_dump_meshes(gear, gear, "        ")
		var tag: Label3D = Label3D.new()
		tag.text = gear_ids[i]
		tag.position = holder.position + Vector3(0, 1.4, 0)
		tag.pixel_size = 0.01
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(tag)

	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.global_position = Vector3(0.0, 1.6, 5.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	cam.current = true

	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("user://gear_preview.png")
	print("[capture] saved abs=%s" % ProjectSettings.globalize_path("user://gear_preview.png"))
	quit()


func _dump_meshes(node: Node, top: Node3D, pad: String) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var xf: Transform3D = Transform3D.IDENTITY
		var walk: Node = mi
		while walk != null and walk != top:
			if walk is Node3D:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		print("%smesh=%s local_aabb=%s composed_origin=%s composed_scale=%s" % [
			pad, mi.name, mi.get_aabb(), xf.origin, xf.basis.get_scale()])
	for c in node.get_children():
		_dump_meshes(c, top, pad)
