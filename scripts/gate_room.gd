extends Node3D

# Gate room scene controller. Owns:
#   - Procedural Kenney floor + perimeter walls + ceiling
#   - The arrival "cinematic" (player input locked while gate shuts behind them)
#   - Gate kawhoosh SFX + ambient ship hum
#   - Objective state for E1 opening beat

@export_group("Room")
@export var floor_size: Vector2i = Vector2i(22, 22)
@export var tile_size: float = 1.0
@export var wall_height_offset: float = 0.0
@export var wall_y_scale: float = 6.0

@export_group("Assets")
@export var floor_scene: PackedScene
@export var wall_scene: PackedScene
@export var wall_corner_scene: PackedScene
@export var wall_door_scene: PackedScene

@export_group("Ceiling")
@export var ceiling_height: float = 6.0
@export var ceiling_material: StandardMaterial3D

@export_group("Materials")
@export var metallic_material: StandardMaterial3D

@export_group("Arrival")
# If true, run the gate-arrival opening. False on returns from corridor.
@export var play_arrival: bool = true
@export var arrival_lockout: float = 1.4

@onready var _world: Node3D = $World
@onready var _player: CharacterBody3D = $Player
@onready var _stargate: Node3D = $World/Stargate
@onready var _gate_back_light: OmniLight3D = $GateBackLight
@onready var _gate_key_light: OmniLight3D = $GateKeyLight
@onready var _gate_sfx: AudioStreamPlayer = $GateSFX
@onready var _ambient_sfx: AudioStreamPlayer = $AmbientHum

func _ready() -> void:
	_build_floor()
	_build_walls()
	_build_ceiling()
	_build_room_colliders()
	# Mark this room as discovered every entry; the gate-arrival cinematic only
	# fires the first time (subsequent visits keep the gate dimmed).
	var first_visit: bool = not GameState.rooms_discovered.has("gate_room")
	GameState.discover_room("gate_room", "Gate Room")
	if play_arrival and first_visit:
		_run_arrival()
	else:
		# Returning — make sure gate is dimmed/closed visually.
		_set_gate_active(false)

func _run_arrival() -> void:
	GameState.set_objective("Step away from the gate and find a way off this ship")
	GameState.add_log("Gate sealed. Power flickering. Where are we?")
	if _player != null and _player.has_method("set_input_locked"):
		_player.set_input_locked(true)
	_set_gate_active(true)
	if _gate_sfx != null and _gate_sfx.stream != null:
		_gate_sfx.play()
	if _ambient_sfx != null and _ambient_sfx.stream != null:
		_ambient_sfx.play()
	await get_tree().create_timer(arrival_lockout).timeout
	_set_gate_active(false)
	if _player != null and _player.has_method("set_input_locked"):
		_player.set_input_locked(false)

func _set_gate_active(active: bool) -> void:
	# Light up the event-horizon puddle for the kawhoosh, then dim & shut once
	# the arrival lockout ends.
	if _stargate != null and "active" in _stargate:
		_stargate.active = active
	if active:
		if _gate_back_light != null:
			_gate_back_light.light_energy = 1.6
			var t1: Tween = create_tween()
			t1.tween_property(_gate_back_light, "light_energy", 0.9, arrival_lockout)
		if _gate_key_light != null:
			_gate_key_light.light_energy = 1.6
			var t2: Tween = create_tween()
			t2.tween_property(_gate_key_light, "light_energy", 0.9, arrival_lockout)
	else:
		if _gate_back_light != null:
			_gate_back_light.light_energy = 0.9
		if _gate_key_light != null:
			_gate_key_light.light_energy = 0.9

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
	var size_x: float = float(floor_size.x) * tile_size
	var size_z: float = float(floor_size.y) * tile_size
	var thickness: float = 0.5
	# Walls: layer 1 (blocks player) + layer 2 (SpringArm camera occluder).
	var walls: StaticBody3D = StaticBody3D.new()
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	_world.add_child(walls)
	# South wall has a 1-tile cutout near x=0.5 for the corridor exit.
	var cutout_w: float = tile_size
	var cutout_h: float = 2.4
	var top_h: float = ceiling_height - cutout_h
	var door_center_x: float = 0.5
	var left_len: float = door_center_x - cutout_w * 0.5 + size_x * 0.5
	var right_len: float = size_x * 0.5 - (door_center_x + cutout_w * 0.5)
	# South wall — split around exit cutout
	_add_box_collider(walls, Vector3(-size_x * 0.5 + left_len * 0.5, ceiling_height * 0.5, -size_z * 0.5 - thickness * 0.5),
		Vector3(left_len, ceiling_height, thickness))
	_add_box_collider(walls, Vector3(size_x * 0.5 - right_len * 0.5, ceiling_height * 0.5, -size_z * 0.5 - thickness * 0.5),
		Vector3(right_len, ceiling_height, thickness))
	_add_box_collider(walls, Vector3(door_center_x, cutout_h + top_h * 0.5, -size_z * 0.5 - thickness * 0.5),
		Vector3(cutout_w, top_h, thickness))
	# +X wall (solid)
	_add_box_collider(walls, Vector3(size_x * 0.5 + thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(thickness, ceiling_height, size_z))
	# -X wall (solid)
	_add_box_collider(walls, Vector3(-size_x * 0.5 - thickness * 0.5, ceiling_height * 0.5, 0.0),
		Vector3(thickness, ceiling_height, size_z))
	# +Z wall (back, solid — gate is here)
	_add_box_collider(walls, Vector3(0.0, ceiling_height * 0.5, size_z * 0.5 + thickness * 0.5),
		Vector3(size_x, ceiling_height, thickness))
	# Ceiling (camera occluder only — player doesn't jump that high anyway).
	var ceil_body: StaticBody3D = StaticBody3D.new()
	ceil_body.collision_layer = 2
	ceil_body.collision_mask = 0
	_world.add_child(ceil_body)
	_add_box_collider(ceil_body, Vector3(0.0, ceiling_height + thickness * 0.5, 0.0),
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
	var door_index: int = floor_size.x / 2
	for x in floor_size.x:
		var px: float = -half_x + (x + 0.5) * tile_size
		_place_wall(Vector3(px, wall_height_offset, half_z), 180.0, wall_scene)
		var is_door: bool = (x == door_index) and (wall_door_scene != null)
		var s: PackedScene = wall_door_scene if is_door else wall_scene
		_place_wall(Vector3(px, wall_height_offset, -half_z), 0.0, s)
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
