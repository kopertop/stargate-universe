extends Node3D

# Procedurally lays out a Kenney space-station floor + perimeter walls.
# Keeps the .tscn small while we iterate on room shape.

@export_group("Room")
@export var floor_size: Vector2i = Vector2i(22, 22)   # tiles in X, Z
@export var tile_size: float = 1.0                    # Kenney kit is 1m grid
@export var wall_height_offset: float = 0.0           # walls sit on floor (y=0) by default
@export var wall_y_scale: float = 6.0                 # Kenney walls are ~1m tall; stretch up

@export_group("Assets")
@export var floor_scene: PackedScene
@export var wall_scene: PackedScene
@export var wall_corner_scene: PackedScene
@export var wall_door_scene: PackedScene

@export_group("Ceiling")
@export var ceiling_height: float = 6.0
@export var ceiling_material: StandardMaterial3D

@export_group("Materials")
# Applied to floor + wall tile mesh instances after instantiation.
@export var metallic_material: StandardMaterial3D

@onready var _world: Node3D = $World

func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_room_colliders()

func _build_ceiling() -> void:
	var size_x: float = float(floor_size.x) * tile_size
	var size_z: float = float(floor_size.y) * tile_size
	var mi: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)
	mi.mesh = plane
	# Flip plane upside-down so its normal points down into the room.
	mi.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	mi.position = Vector3(0.0, ceiling_height, 0.0)
	if ceiling_material != null:
		mi.material_override = ceiling_material
	_world.add_child(mi)

func _build_room_colliders() -> void:
	# Invisible shell so SpringArm3D camera raycasts stop at walls/ceiling.
	var size_x: float = float(floor_size.x) * tile_size
	var size_z: float = float(floor_size.y) * tile_size
	var thickness: float = 0.5
	var body: StaticBody3D = StaticBody3D.new()
	# Layer 2 reserved for camera occluders so SpringArm3D can mask just these.
	body.collision_layer = 2
	body.collision_mask = 0
	_world.add_child(body)

	# +X wall
	_add_box_collider(body, Vector3(size_x * 0.5 + thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(thickness, ceiling_height, size_z))
	# -X wall
	_add_box_collider(body, Vector3(-size_x * 0.5 - thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(thickness, ceiling_height, size_z))
	# +Z wall
	_add_box_collider(body, Vector3(0.0, ceiling_height * 0.5, size_z * 0.5 + thickness * 0.5),
		Vector3(size_x, ceiling_height, thickness))
	# -Z wall
	_add_box_collider(body, Vector3(0.0, ceiling_height * 0.5, -size_z * 0.5 - thickness * 0.5),
		Vector3(size_x, ceiling_height, thickness))
	# Ceiling
	_add_box_collider(body, Vector3(0.0, ceiling_height + thickness * 0.5, 0.0),
		Vector3(size_x, thickness, size_z))

func _add_box_collider(parent: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	parent.add_child(cs)

func _build_floor() -> void:
	if floor_scene == null:
		push_warning("gate_room: floor_scene not assigned")
		return
	var origin_x: float = -float(floor_size.x) * 0.5 * tile_size + tile_size * 0.5
	var origin_z: float = -float(floor_size.y) * 0.5 * tile_size + tile_size * 0.5
	for x in floor_size.x:
		for z in floor_size.y:
			var tile: Node3D = floor_scene.instantiate()
			tile.position = Vector3(origin_x + x * tile_size, 0.0, origin_z + z * tile_size)
			_world.add_child(tile)
			_apply_metallic(tile)

func _apply_metallic(root: Node) -> void:
	if metallic_material == null:
		return
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, metallic_material)
	for c in root.get_children():
		_apply_metallic(c)

func _build_walls() -> void:
	if wall_scene == null:
		push_warning("gate_room: wall_scene not assigned")
		return
	var half_x: float = float(floor_size.x) * 0.5 * tile_size
	var half_z: float = float(floor_size.y) * 0.5 * tile_size
	var door_index: int = floor_size.x / 2  # door near middle of +Z wall (behind player view)

	# North (+Z) and South (-Z) walls — face inward along Z
	for x in floor_size.x:
		var px: float = -half_x + (x + 0.5) * tile_size
		# +Z wall (back of room, where the gate sits)
		_place_wall(Vector3(px, wall_height_offset, half_z), 180.0, wall_scene)
		# -Z wall (player spawn side) — leave a door
		var is_door: bool = (x == door_index) and (wall_door_scene != null)
		var s: PackedScene = wall_door_scene if is_door else wall_scene
		_place_wall(Vector3(px, wall_height_offset, -half_z), 0.0, s)

	# East (+X) and West (-X) walls
	for z in floor_size.y:
		var pz: float = -half_z + (z + 0.5) * tile_size
		_place_wall(Vector3(half_x, wall_height_offset, pz), 270.0, wall_scene)
		_place_wall(Vector3(-half_x, wall_height_offset, pz), 90.0, wall_scene)

func _place_wall(pos: Vector3, yaw_deg: float, scene: PackedScene) -> void:
	var w: Node3D = scene.instantiate()
	w.position = pos
	w.rotation_degrees = Vector3(0, yaw_deg, 0)
	w.scale = Vector3(1.0, wall_y_scale, 1.0)
	_world.add_child(w)
	_apply_metallic(w)
