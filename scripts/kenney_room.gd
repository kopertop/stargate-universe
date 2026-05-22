extends Node3D

# Generic Kenney space-station room builder. Procedurally lays out a floor + 4 walls
# + ceiling, with optional door cutouts on any of the four sides at a configurable
# tile index. Used by corridor, quarters, hull-breach, observation, etc.
#
# Coordinate convention: room is centered on origin; floor on y=0; walls go up.
# Door cutouts use the kit's wall-door.glb at the chosen index. Other walls get wall.glb.

@export_group("Room")
@export var floor_size: Vector2i = Vector2i(8, 20)
@export var tile_size: float = 1.0
@export var wall_y_scale: float = 6.0
@export var ceiling_height: float = 6.0

@export_group("Assets")
@export var floor_scene: PackedScene
@export var wall_scene: PackedScene
@export var wall_door_scene: PackedScene

@export_group("Door Cutouts")
# -1 = no cutout; otherwise tile index along that side (0..floor_size.x-1 for N/S, 0..floor_size.y-1 for E/W).
@export var south_door_index: int = -1
@export var north_door_index: int = -1
@export var east_door_index: int = -1
@export var west_door_index: int = -1

@export_group("Materials")
@export var metallic_material: StandardMaterial3D
@export var ceiling_material: StandardMaterial3D

@export_group("Narrative")
# Contextual objective set on the HUD when this room loads. Leave empty
# to keep whatever the prior scene set. Prevents "Step through the gate"
# from sticking once the player has moved past the gate.
@export_multiline var objective_on_enter: String = ""

@onready var _world: Node3D = $World

func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_room_colliders()
	if objective_on_enter != "":
		GameState.set_objective(objective_on_enter)

func _build_ceiling() -> void:
	var size_x: float = float(floor_size.x) * tile_size
	var size_z: float = float(floor_size.y) * tile_size
	var mi: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(size_x, size_z)
	mi.mesh = plane
	mi.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	mi.position = Vector3(0.0, ceiling_height, 0.0)
	if ceiling_material != null:
		mi.material_override = ceiling_material
	_world.add_child(mi)

func _build_room_colliders() -> void:
	# Camera-occluder shell on layer 2 (SpringArm only masks layer 2).
	# Also walls on layer 1 for actual player blocking.
	var size_x: float = float(floor_size.x) * tile_size
	var size_z: float = float(floor_size.y) * tile_size
	var thickness: float = 0.5
	var wall_body: StaticBody3D = StaticBody3D.new()
	wall_body.collision_layer = 1 | 2  # walk-blocker AND camera-occluder
	wall_body.collision_mask = 0
	_world.add_child(wall_body)
	# Camera-only "curtain" body — invisible plates spanning each door cutout.
	# The player (mask layer 1) walks through; the camera SpringArm (mask layer 2)
	# bounces off so it cannot escape the room through the doorway.
	var curtain_body: StaticBody3D = StaticBody3D.new()
	curtain_body.collision_layer = 2
	curtain_body.collision_mask = 0
	_world.add_child(curtain_body)
	# Each side is split around the door cutout so the player can walk through.
	_add_side_with_cutout(wall_body, curtain_body, "south", size_x, size_z, thickness)
	_add_side_with_cutout(wall_body, curtain_body, "north", size_x, size_z, thickness)
	_add_side_with_cutout(wall_body, curtain_body, "east", size_x, size_z, thickness)
	_add_side_with_cutout(wall_body, curtain_body, "west", size_x, size_z, thickness)
	# Ceiling (camera-occluder only).
	var ceiling_body: StaticBody3D = StaticBody3D.new()
	ceiling_body.collision_layer = 2
	ceiling_body.collision_mask = 0
	_world.add_child(ceiling_body)
	_add_box_collider(ceiling_body, Vector3(0.0, ceiling_height + thickness * 0.5, 0.0),
		Vector3(size_x, thickness, size_z))

func _add_side_with_cutout(body: StaticBody3D, curtain: StaticBody3D, side: String,
		size_x: float, size_z: float, thickness: float) -> void:
	# Cutout is 1 tile wide & 2.4m tall (matches Kenney wall-door clearance).
	var cutout_w: float = tile_size
	var cutout_h: float = 2.4
	var top_h: float = ceiling_height - cutout_h
	var idx: int = -1
	match side:
		"south": idx = south_door_index
		"north": idx = north_door_index
		"east": idx = east_door_index
		"west": idx = west_door_index
	var is_horizontal: bool = (side == "south" or side == "north")
	var length: float = size_x if is_horizontal else size_z
	var z_or_x: float = (size_z * 0.5 + thickness * 0.5)
	if side == "north" or side == "east":
		pass
	else:
		z_or_x = -z_or_x
	if idx < 0:
		# Solid wall.
		var pos: Vector3
		var sz: Vector3
		if is_horizontal:
			pos = Vector3(0.0, ceiling_height * 0.5, (size_z * 0.5 + thickness * 0.5) * (1.0 if side == "north" else -1.0))
			sz = Vector3(length, ceiling_height, thickness)
		else:
			pos = Vector3((size_x * 0.5 + thickness * 0.5) * (1.0 if side == "east" else -1.0), ceiling_height * 0.5, 0.0)
			sz = Vector3(thickness, ceiling_height, length)
		_add_box_collider(body, pos, sz)
		return
	# Split into left chunk, header above cutout, right chunk.
	var half: float = length * 0.5
	var center_along: float = -half + (float(idx) + 0.5) * tile_size
	var left_len: float = center_along - cutout_w * 0.5 + half
	var right_len: float = half - (center_along + cutout_w * 0.5)
	var left_center: float = -half + left_len * 0.5
	var right_center: float = half - right_len * 0.5
	if is_horizontal:
		var side_z: float = (size_z * 0.5 + thickness * 0.5) * (1.0 if side == "north" else -1.0)
		if left_len > 0.01:
			_add_box_collider(body, Vector3(left_center, ceiling_height * 0.5, side_z),
				Vector3(left_len, ceiling_height, thickness))
		if right_len > 0.01:
			_add_box_collider(body, Vector3(right_center, ceiling_height * 0.5, side_z),
				Vector3(right_len, ceiling_height, thickness))
		# Header above cutout.
		if top_h > 0.01:
			_add_box_collider(body, Vector3(center_along, cutout_h + top_h * 0.5, side_z),
				Vector3(cutout_w, top_h, thickness))
		# Camera-only curtain across the cutout itself.
		_add_box_collider(curtain, Vector3(center_along, cutout_h * 0.5, side_z),
			Vector3(cutout_w, cutout_h, thickness))
	else:
		var side_x: float = (size_x * 0.5 + thickness * 0.5) * (1.0 if side == "east" else -1.0)
		if left_len > 0.01:
			_add_box_collider(body, Vector3(side_x, ceiling_height * 0.5, left_center),
				Vector3(thickness, ceiling_height, left_len))
		if right_len > 0.01:
			_add_box_collider(body, Vector3(side_x, ceiling_height * 0.5, right_center),
				Vector3(thickness, ceiling_height, right_len))
		if top_h > 0.01:
			_add_box_collider(body, Vector3(side_x, cutout_h + top_h * 0.5, center_along),
				Vector3(thickness, top_h, cutout_w))
		_add_box_collider(curtain, Vector3(side_x, cutout_h * 0.5, center_along),
			Vector3(thickness, cutout_h, cutout_w))

func _add_box_collider(parent: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	parent.add_child(cs)

func _build_floor() -> void:
	if floor_scene == null:
		push_warning("kenney_room: floor_scene not assigned")
		return
	var origin_x: float = -float(floor_size.x) * 0.5 * tile_size + tile_size * 0.5
	var origin_z: float = -float(floor_size.y) * 0.5 * tile_size + tile_size * 0.5
	# Floor collider so player walks on it.
	# Kenney floor.glb tiles sit on their origin and rise 0.3m, so the visual top is at y=0.3.
	# Anchor the collider top at y=0.3 to match the visible surface — otherwise the player
	# rests at y≈0 while the floor renders 0.3m above, sinking the character.
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	_world.add_child(floor_body)
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(float(floor_size.x) * tile_size + 0.4, 0.2, float(floor_size.y) * tile_size + 0.4)
	cs.shape = box
	cs.position = Vector3(0.0, 0.2, 0.0)
	floor_body.add_child(cs)
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
		push_warning("kenney_room: wall_scene not assigned")
		return
	var half_x: float = float(floor_size.x) * 0.5 * tile_size
	var half_z: float = float(floor_size.y) * 0.5 * tile_size
	# +Z (north) and -Z (south)
	for x in floor_size.x:
		var px: float = -half_x + (x + 0.5) * tile_size
		_place_wall(Vector3(px, 0.0, half_z), 180.0, _pick(x, north_door_index))
		_place_wall(Vector3(px, 0.0, -half_z), 0.0, _pick(x, south_door_index))
	# +X (east) and -X (west)
	for z in floor_size.y:
		var pz: float = -half_z + (z + 0.5) * tile_size
		_place_wall(Vector3(half_x, 0.0, pz), 270.0, _pick(z, east_door_index))
		_place_wall(Vector3(-half_x, 0.0, pz), 90.0, _pick(z, west_door_index))

func _pick(i: int, door_index: int) -> PackedScene:
	if i == door_index and wall_door_scene != null:
		return wall_door_scene
	return wall_scene

func _place_wall(pos: Vector3, yaw_deg: float, scene: PackedScene) -> void:
	if scene == null:
		return
	var w: Node3D = scene.instantiate()
	w.position = pos
	w.rotation_degrees = Vector3(0, yaw_deg, 0)
	w.scale = Vector3(1.0, wall_y_scale, 1.0)
	_world.add_child(w)
	_apply_metallic(w)
