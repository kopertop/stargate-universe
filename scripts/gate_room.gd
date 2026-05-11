extends Node3D

# Procedurally lays out a Kenney space-station floor + perimeter walls.
# Keeps the .tscn small while we iterate on room shape.

@export_group("Room")
@export var floor_size: Vector2i = Vector2i(14, 14)   # tiles in X, Z
@export var tile_size: float = 1.0                    # Kenney kit is 1m grid
@export var wall_height_offset: float = 0.0           # walls sit on floor (y=0) by default
@export var wall_y_scale: float = 1.5                 # Kenney walls are ~1m tall; stretch up

@export_group("Assets")
@export var floor_scene: PackedScene
@export var wall_scene: PackedScene
@export var wall_corner_scene: PackedScene
@export var wall_door_scene: PackedScene

@onready var _world: Node3D = $World

func _ready() -> void:
	_build_floor()
	_build_walls()

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
