extends Node3D

# Collectable drone scrap. Spawns in the air, falls with gravity, snaps only to
# upward-facing StaticBody floors (never walls/rails/characters), then becomes
# an Interactable that grants Inventory `parts`.

const GRAVITY: float = 22.0
const MIN_AIR_TIME: float = 0.08
const MAX_AIR_TIME: float = 2.2
const REST_CLEARANCE: float = 0.05
const MIN_DROP: float = 0.35

@export var grant_amount: int = 1
@export var item_id: String = "parts"
@export var prompt: String = "Collect scrap parts"
@export var enabled: bool = false

var _collected: bool = false  # @collection-ok: per-instance "already consumed" guard for a disposable interactable; collection membership is tracked via Inventory.add_item
var _collectable: bool = false
var _vel: Vector3 = Vector3.ZERO
var _spin: Vector3 = Vector3.ZERO
var _air_t: float = 0.0
var _launch_y: float = 0.0
var _mesh: MeshInstance3D = null
var _armed: bool = false


static func spawn_loot(
	parent_n: Node,
	at: Vector3,
	velocity: Vector3,
	grant: int = 1
) -> Node3D:
	if parent_n == null:
		return null
	var part: Node3D = (load("res://scripts/drone_scrap_part.gd") as GDScript).new() as Node3D
	part.name = "DroneScrapPart"
	# Arm motion BEFORE entering the tree so the first physics tick falls.
	part.set("_vel", velocity)
	part.set("_spin", Vector3(
		randf_range(-7.0, 7.0), randf_range(-7.0, 7.0), randf_range(-7.0, 7.0)
	))
	part.set("_launch_y", at.y)
	part.set("grant_amount", grant)
	part.set("_armed", true)
	parent_n.add_child(part)
	part.global_position = at
	part.call("_build_visual")
	return part


func _ready() -> void:
	set_physics_process(true)


func _build_visual() -> void:
	if _mesh != null:
		return
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.07, 0.14)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.62, 0.65, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.75, 1.0)
	mat.emission_energy_multiplier = 2.0
	_mesh.material_override = mat
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	if not _armed or _collected or _collectable:
		return
	_air_t += delta
	_vel.y -= GRAVITY * delta
	var next: Vector3 = global_position + _vel * delta
	rotation += _spin * delta

	var floor_y: float = _query_floor_y(next)
	var dropped: bool = next.y <= (_launch_y - MIN_DROP)
	var falling: bool = _vel.y < 0.0
	var on_floor: bool = next.y <= floor_y + REST_CLEARANCE
	if _air_t >= MIN_AIR_TIME and falling and dropped and on_floor:
		global_position = Vector3(next.x, floor_y + REST_CLEARANCE, next.z)
		_make_collectable()
		return
	if _air_t >= MAX_AIR_TIME:
		global_position = Vector3(next.x, floor_y + REST_CLEARANCE, next.z)
		_make_collectable()
		return
	global_position = next


func _query_floor_y(around: Vector3) -> float:
	var world: World3D = get_world_3d()
	if world == null:
		return 0.0
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	# Cast from above the scrap down past the deck.
	var from: Vector3 = Vector3(around.x, maxf(around.y, _launch_y) + 1.0, around.z)
	var to: Vector3 = Vector3(around.x, -8.0, around.z)
	var exclude: Array[RID] = []
	for _i in 16:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		q.exclude = exclude
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			return 0.0
		var col: Object = hit.get("collider")
		var normal: Vector3 = hit.get("normal", Vector3.UP) as Vector3
		# Only accept floor-like surfaces (upward normal). Skip walls/rails.
		if col is StaticBody3D and normal.y > 0.55:
			return (hit.position as Vector3).y
		if col is CollisionObject3D:
			exclude.append((col as CollisionObject3D).get_rid())
			from = (hit.position as Vector3) + Vector3.DOWN * 0.03
			continue
		return 0.0
	return 0.0


func _make_collectable() -> void:
	if _collectable or _collected:
		return
	_collectable = true
	_vel = Vector3.ZERO
	_spin = Vector3.ZERO
	rotation.x = 0.0
	rotation.z *= 0.2
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.28, 0.12, 0.22)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	add_to_group("interactable")
	enabled = true
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var m: StandardMaterial3D = _mesh.material_override as StandardMaterial3D
		m.emission = Color(0.5, 0.85, 1.0)
		m.emission_energy_multiplier = 2.8


func get_prompt() -> String:
	return prompt


func interact(_by: Node) -> void:
	if not enabled or _collected:
		return
	_collected = true
	enabled = false
	remove_from_group("interactable")
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv != null and inv.has_method("add_item"):
		inv.call("add_item", item_id, grant_amount, "drone_scrap")
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Collected %d ship parts from drone scrap." % grant_amount)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.12)
	tw.tween_callback(queue_free)
