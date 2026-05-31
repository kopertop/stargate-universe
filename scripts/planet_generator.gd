class_name PlanetGenerator
extends Object

# Deterministic graybox planet builder. The data row owns the seed and counts;
# this script turns that into a large heightmapped terrain, a return Stargate,
# and lime. The terrain is a procedural mesh: rolling noise hills in the middle,
# a raised mountain rim so there's no edge to walk off, and a flattened landing
# zone around the gate. Lime can sit in valleys behind ridges, so the player has
# to fly the recon Kino around to spot it.

const STARGATE_SCENE: PackedScene = preload("res://objects/stargate.tscn")
const RESOURCE_NODE_SCRIPT: Script = preload("res://scripts/resource_node.gd")
const PLANET_GATE_SCRIPT: Script = preload("res://scripts/planet_gate.gd")
const POI_NODE_SCRIPT: Script = preload("res://scripts/poi_node.gd")

# Non-lime points-of-interest the Kino's auto-search can turn up. category →
# [default count, toast/compass label]. Overridable per planet via a "poi_counts"
# dict in planets.json (e.g. {"ore": 5}).
const POI_KINDS: Dictionary = {
	"ruin":   [2, "Ancient Ruin"],
	"ore":    [3, "Ore Vein"],
	"water":  [2, "Water Source"],
	"debris": [2, "Crashed Debris"],
}

static func build(world: Node3D, planet_data: Dictionary) -> void:
	if world == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(planet_data.get("seed", 1))
	var tp: Dictionary = _terrain_params(planet_data)
	_build_terrain(world, tp)
	_build_return_gate(world, tp)
	_build_lime_nodes(world, planet_data, rng, tp)
	_build_pois(world, planet_data, rng, tp)
	_build_rocks(world, rng, tp)
	_build_landmarks(world, rng, tp)

# Bundle the terrain shaping inputs (two noise fields + the radial profile) so
# the same height function drives both the mesh and where props sit.
static func _terrain_params(planet_data: Dictionary) -> Dictionary:
	var seed: int = int(planet_data.get("seed", 1))
	var n1: FastNoiseLite = FastNoiseLite.new()
	n1.seed = seed
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n1.frequency = 0.012
	var n2: FastNoiseLite = FastNoiseLite.new()
	n2.seed = seed + 7
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n2.frequency = 0.045
	return {
		"noise": n1,
		"noise2": n2,
		"extent": float(planet_data.get("terrain_extent", 240.0)),
		"res": int(planet_data.get("terrain_resolution", 96)),
		"height": float(planet_data.get("terrain_height", 9.0)),
		"rim_height": float(planet_data.get("rim_height", 34.0)),
		"landing_radius": float(planet_data.get("landing_radius", 22.0)),
	}

# Terrain height at world (x, z). Combines: rolling hills (two noise octaves),
# a mountain rim that rises toward the map edge (so there's no cliff to fall
# off), and a flattened landing zone near the origin (gate + spawn).
static func _height(x: float, z: float, tp: Dictionary) -> float:
	var dist: float = sqrt(x * x + z * z)
	var n1: FastNoiseLite = tp["noise"]
	var n2: FastNoiseLite = tp["noise2"]
	var height: float = float(tp["height"])
	var h: float = n1.get_noise_2d(x, z) * height
	h += n2.get_noise_2d(x, z) * height * 0.45
	# Raise toward the rim: a ring of mountains walling in the playable bowl.
	var extent: float = float(tp["extent"])
	var rim_start: float = extent * 0.32
	var rim_full: float = extent * 0.5
	var rim_t: float = clampf((dist - rim_start) / max(rim_full - rim_start, 0.001), 0.0, 1.0)
	h += pow(rim_t, 2.2) * float(tp["rim_height"])
	# Flatten toward the centre so the gate + landing zone sit on stable ground.
	var land_t: float = smoothstep(0.0, 1.0, clampf(dist / max(float(tp["landing_radius"]), 0.001), 0.0, 1.0))
	return lerpf(0.0, h, land_t)

static func _build_terrain(world: Node3D, tp: Dictionary) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "PlanetGround"
	body.collision_layer = 1 | 2   # 1 = player/drone, 2 = camera spring
	body.collision_mask = 0
	world.add_child(body)

	var res: int = int(tp["res"])
	var extent: float = float(tp["extent"])
	var step: float = extent / float(res)
	var half: float = extent * 0.5
	const UV_SCALE: float = 0.25

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in res:
		for j in res:
			var x0: float = -half + i * step
			var z0: float = -half + j * step
			var x1: float = x0 + step
			var z1: float = z0 + step
			var p00: Vector3 = Vector3(x0, _height(x0, z0, tp), z0)
			var p10: Vector3 = Vector3(x1, _height(x1, z0, tp), z0)
			var p11: Vector3 = Vector3(x1, _height(x1, z1, tp), z1)
			var p01: Vector3 = Vector3(x0, _height(x0, z1, tp), z1)
			# Winding chosen so SurfaceTool.generate_normals() faces +Y (up) —
			# the reverse order leaves normals pointing down, which lights the
			# ground from below and reads as an upside-down/inside-out world.
			_st_tri(st, p00, p11, p01, UV_SCALE)
			_st_tri(st, p00, p10, p11, UV_SCALE)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = mesh
	mi.material_override = _ground_mat()
	body.add_child(mi)

	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)

static func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_scale: float) -> void:
	st.set_uv(Vector2(a.x, a.z) * uv_scale)
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z) * uv_scale)
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z) * uv_scale)
	st.add_vertex(c)

static func _ground_mat() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.39, 0.28)
	m.roughness = 0.95
	m.metallic = 0.0
	# Double-sided so a graybox terrain never vanishes on a winding flip.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func _build_return_gate(world: Node3D, tp: Dictionary) -> void:
	var ground_y: float = _height(0.0, -9.0, tp)
	var gate: Node3D = STARGATE_SCENE.instantiate()
	gate.name = "PlanetReturnStargate"
	gate.position = Vector3(0.0, ground_y + 3.2, -9.0)
	gate.rotation.y = PI
	gate.set("active", true)
	world.add_child(gate)

	var portal: Area3D = Area3D.new()
	portal.set_script(PLANET_GATE_SCRIPT)
	portal.name = "PlanetReturnGate"
	portal.position = Vector3(0.0, ground_y + 2.0, -9.0)
	portal.set("mode", "to_ship")
	portal.set("target_scene", "res://scenes/gate_room.tscn")
	# Land past the platform (not on the dais) and bring the away team back too.
	portal.set("target_spawn", "FromPlanet")
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.4, 3.0, 1.2)
	cs.shape = shape
	portal.add_child(cs)
	world.add_child(portal)

static func _build_lime_nodes(world: Node3D, planet_data: Dictionary, rng: RandomNumberGenerator, tp: Dictionary) -> void:
	var count: int = int(planet_data.get("lime_nodes", 4))
	var amount: int = int(planet_data.get("lime_per_node", 1))
	var min_r: float = float(planet_data.get("lime_min_radius", 40.0))
	var max_r: float = float(planet_data.get("lime_max_radius", 95.0))
	# Lime reads as WHITE rock / sand (a chalky mineral deposit), not crystals.
	# A faint white emission keeps deposits spottable from the Kino / at distance.
	var lime_mat: StandardMaterial3D = StandardMaterial3D.new()
	lime_mat.albedo_color = Color(0.93, 0.94, 0.91)
	lime_mat.roughness = 0.9
	lime_mat.metallic = 0.0
	lime_mat.emission_enabled = true
	lime_mat.emission = Color(0.86, 0.90, 0.96)
	lime_mat.emission_energy_multiplier = 0.28

	var label: String = String(planet_data.get("name", "lime planet"))
	var idx: int = 0

	# Standard spread — evenly distributed around the gate at mid radii.
	for i in count:
		var angle: float = (TAU / float(count)) * float(i) + rng.randf_range(-0.4, 0.4)
		var dist: float = rng.randf_range(min_r, max_r)
		idx += 1
		_spawn_lime_deposit(world, idx, angle, dist, amount, label, lime_mat, tp)

	# Optional far cluster — N deposits packed into a small angular arc at the
	# very edge of the map. Drives a "venture-far" risk/reward beat on top of
	# the convenient near-gate spread.
	var far_count: int = int(planet_data.get("lime_far_count", 0))
	if far_count > 0:
		var far_min: float = float(planet_data.get("lime_far_min_radius", min_r * 4.0))
		var far_max: float = float(planet_data.get("lime_far_max_radius", min_r * 5.0))
		var far_arc: float = float(planet_data.get("lime_far_arc", 0.6))  # radians of spread
		var cluster_center: float = rng.randf_range(0.0, TAU)
		for j in far_count:
			var angle: float = cluster_center + rng.randf_range(-far_arc * 0.5, far_arc * 0.5)
			var dist: float = rng.randf_range(far_min, far_max)
			idx += 1
			_spawn_lime_deposit(world, idx, angle, dist, amount, label, lime_mat, tp)


# Build one mineable lime deposit at (angle, radius) on the heightmapped
# terrain. Shared by the standard spread and the optional far cluster.
static func _spawn_lime_deposit(world: Node3D, idx: int, angle: float, dist: float,
		amount: int, source_label: String, lime_mat: StandardMaterial3D, tp: Dictionary) -> void:
	var x: float = cos(angle) * dist
	var z: float = sin(angle) * dist
	var node: StaticBody3D = StaticBody3D.new()
	node.set_script(RESOURCE_NODE_SCRIPT)
	node.name = "LimeNode%d" % idx
	node.position = Vector3(x, _height(x, z, tp), z)
	node.set("resource_type", GameState.AIR_LIME_RESOURCE)
	node.set("amount", amount)
	node.set("source_label", source_label)
	node.add_to_group("lime_node")   # shared handle for companions + compass

	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.65, 0.0)
	node.add_child(cs)

	# A low pile of white rock chunks (chalky lime deposit).
	_add_box(node, Vector3(0.0, 0.22, 0.0), Vector3(1.15, 0.44, 0.95), lime_mat)
	_add_box(node, Vector3(-0.34, 0.50, 0.10), Vector3(0.52, 0.46, 0.50), lime_mat)
	_add_box(node, Vector3(0.30, 0.44, -0.22), Vector3(0.46, 0.40, 0.52), lime_mat)
	_add_box(node, Vector3(0.10, 0.64, 0.22), Vector3(0.34, 0.32, 0.36), lime_mat)
	world.add_child(node)

# Scatter the non-lime POIs (ruins, ore, water, debris) around the bowl, between
# the landing zone and the rim, so the auto-search Kino has varied things to find.
# Deterministic: driven by the same seeded RNG, so a node name always maps to the
# same spot (discovery survives save/load).
static func _build_pois(world: Node3D, planet_data: Dictionary, rng: RandomNumberGenerator, tp: Dictionary) -> void:
	var counts: Dictionary = planet_data.get("poi_counts", {})
	var min_r: float = float(tp["landing_radius"]) + 28.0
	var max_r: float = float(tp["extent"]) * 0.45
	for cat in POI_KINDS.keys():
		var spec: Array = POI_KINDS[cat]
		var n: int = int(counts.get(cat, spec[0]))
		var label: String = String(spec[1])
		for i in n:
			var angle: float = rng.randf_range(0.0, TAU)
			var dist: float = rng.randf_range(min_r, max_r)
			var x: float = cos(angle) * dist
			var z: float = sin(angle) * dist
			var poi: Node3D = POI_NODE_SCRIPT.new()
			# Set name + exports BEFORE add_child so _ready restores discovery and
			# builds the right category visual.
			poi.name = "Poi_%s_%d" % [cat, i + 1]
			poi.set("poi_category", cat)
			poi.set("poi_label", label)
			poi.position = Vector3(x, _height(x, z, tp), z)
			world.add_child(poi)


static func _build_rocks(world: Node3D, rng: RandomNumberGenerator, tp: Dictionary) -> void:
	var rock_mat: StandardMaterial3D = StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.25, 0.24, 0.22)
	rock_mat.roughness = 0.9
	var spread: float = float(tp["extent"]) * 0.42
	for i in 48:
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(6.0, spread)
		var size: float = rng.randf_range(0.5, 2.6)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var rock: MeshInstance3D = MeshInstance3D.new()
		rock.name = "Rock%d" % i
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(size * rng.randf_range(0.8, 1.8), size * 0.6, size)
		rock.mesh = mesh
		rock.material_override = rock_mat
		rock.position = Vector3(x, _height(x, z, tp) + size * 0.25, z)
		rock.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
		world.add_child(rock)

static func _build_landmarks(world: Node3D, rng: RandomNumberGenerator, tp: Dictionary) -> void:
	var marker_mat: StandardMaterial3D = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(0.56, 0.50, 0.36)
	marker_mat.metallic = 0.15
	marker_mat.roughness = 0.8
	var extent: float = float(tp["extent"])
	for i in 8:
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(extent * 0.18, extent * 0.34)
		var h: float = 2.6 + rng.randf_range(0.0, 2.2)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		_add_box(
			world,
			Vector3(x, _height(x, z, tp) + h * 0.5, z),
			Vector3(0.55, h, 0.55),
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
