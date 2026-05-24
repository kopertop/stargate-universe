class_name PlanetGenerator
extends Object

# Deterministic graybox planet builder. The data row owns the seed and counts;
# this script turns that into terrain, landmarks, a return Stargate, and lime.

const STARGATE_SCENE: PackedScene = preload("res://objects/stargate.tscn")
const RESOURCE_NODE_SCRIPT: Script = preload("res://scripts/resource_node.gd")
const PLANET_GATE_SCRIPT: Script = preload("res://scripts/planet_gate.gd")

static func build(world: Node3D, planet_data: Dictionary) -> void:
	if world == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(planet_data.get("seed", 1))
	var radius: float = float(planet_data.get("radius", 30.0))
	_build_ground(world, radius)
	_build_return_gate(world)
	_build_lime_nodes(world, planet_data, rng, radius)
	_build_rocks(world, rng, radius)
	_build_landmarks(world, rng, radius)

static func _build_ground(world: Node3D, radius: float) -> void:
	var ground_mat: StandardMaterial3D = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.42, 0.39, 0.28)
	ground_mat.roughness = 0.92
	ground_mat.metallic = 0.0

	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "PlanetGround"
	ground.collision_layer = 1 | 2
	ground.collision_mask = 0
	world.add_child(ground)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(radius * 2.0, 0.35, radius * 2.0)
	cs.shape = shape
	cs.position = Vector3(0.0, -0.18, 0.0)
	ground.add_child(cs)

	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = shape.size
	mi.mesh = mesh
	mi.material_override = ground_mat
	mi.position = cs.position
	ground.add_child(mi)

static func _build_return_gate(world: Node3D) -> void:
	var gate: Node3D = STARGATE_SCENE.instantiate()
	gate.name = "PlanetReturnStargate"
	gate.position = Vector3(0.0, 3.2, -9.0)
	gate.rotation.y = PI
	gate.set("active", true)
	world.add_child(gate)

	var portal: Area3D = Area3D.new()
	portal.set_script(PLANET_GATE_SCRIPT)
	portal.name = "PlanetReturnGate"
	portal.position = Vector3(0.0, 2.0, -9.0)
	portal.set("mode", "to_ship")
	portal.set("target_scene", "res://scenes/gate_room.tscn")
	portal.set("target_spawn", "FromGate")
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.4, 3.0, 1.2)
	cs.shape = shape
	portal.add_child(cs)
	world.add_child(portal)

static func _build_lime_nodes(world: Node3D, planet_data: Dictionary, rng: RandomNumberGenerator, radius: float) -> void:
	var count: int = int(planet_data.get("lime_nodes", 4))
	var amount: int = int(planet_data.get("lime_per_node", 1))
	var lime_mat: StandardMaterial3D = StandardMaterial3D.new()
	lime_mat.albedo_color = Color(0.70, 0.92, 0.34)
	lime_mat.emission_enabled = true
	lime_mat.emission = Color(0.38, 0.75, 0.14)
	lime_mat.emission_energy_multiplier = 1.2
	lime_mat.roughness = 0.55
	var stone_mat: StandardMaterial3D = StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.34, 0.32, 0.27)
	stone_mat.roughness = 0.85

	for i in count:
		var angle: float = (TAU / float(count)) * float(i) + rng.randf_range(-0.28, 0.28)
		var dist: float = rng.randf_range(9.0, radius * 0.62)
		var node: StaticBody3D = StaticBody3D.new()
		node.set_script(RESOURCE_NODE_SCRIPT)
		node.name = "LimeNode%d" % (i + 1)
		node.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		node.set("resource_type", GameState.AIR_LIME_RESOURCE)
		node.set("amount", amount)
		node.set("source_label", String(planet_data.get("name", "lime planet")))

		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(1.2, 1.2, 1.2)
		cs.shape = shape
		cs.position = Vector3(0.0, 0.65, 0.0)
		node.add_child(cs)

		_add_box(node, Vector3(0.0, 0.25, 0.0), Vector3(1.25, 0.5, 1.0), stone_mat)
		_add_crystal(node, Vector3(-0.28, 0.82, 0.0), 0.55, lime_mat)
		_add_crystal(node, Vector3(0.18, 0.70, 0.18), 0.42, lime_mat)
		_add_crystal(node, Vector3(0.36, 0.58, -0.20), 0.32, lime_mat)
		world.add_child(node)

static func _build_rocks(world: Node3D, rng: RandomNumberGenerator, radius: float) -> void:
	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.25, 0.24, 0.22)
	rock_mat.roughness = 0.9
	for i in 18:
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(5.0, radius * 0.9)
		var size: float = rng.randf_range(0.35, 1.4)
		var rock: MeshInstance3D = MeshInstance3D.new()
		rock.name = "Rock%d" % i
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(size * rng.randf_range(0.8, 1.8), size * 0.55, size)
		rock.mesh = mesh
		rock.material_override = rock_mat
		rock.position = Vector3(cos(angle) * dist, size * 0.25, sin(angle) * dist)
		rock.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
		world.add_child(rock)

static func _build_landmarks(world: Node3D, rng: RandomNumberGenerator, radius: float) -> void:
	var marker_mat: StandardMaterial3D = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.56, 0.50, 0.36)
	marker_mat.metallic = 0.15
	marker_mat.roughness = 0.8
	for i in 5:
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(radius * 0.42, radius * 0.78)
		_add_box(
			world,
			Vector3(cos(angle) * dist, 1.3, sin(angle) * dist),
			Vector3(0.55, 2.6 + rng.randf_range(0.0, 1.8), 0.55),
			marker_mat
		)

static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

static func _add_crystal(parent: Node3D, pos: Vector3, height: float, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.24, height, 0.24)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(0.18, pos.x * 3.0 + pos.z, 0.24)
	parent.add_child(mi)
