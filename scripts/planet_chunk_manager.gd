class_name PlanetChunkManager
extends Node3D

# Near-infinite planet terrain via chunk streaming (issue #85).
#
# The height field is a SINGLE global function of world (x, z) — seeded noise
# owned by PlanetGenerator. Each chunk samples that same function, so chunk
# borders stitch seamlessly with no per-chunk independent randomness (no cliffs
# or gaps). Walking toward any "edge" just reveals more world: as the tracked
# body moves, chunks newly entering the radius are built and distant ones are
# freed. The loaded-chunk count is capped by the radius, so memory stays bounded
# and there is no terrain "edge" to fall off.
#
# Content (resource/POI/prop placement) is derived deterministically from world
# position + seed (hash of chunk coords), so the same spot always yields the same
# content and discovery survives save/load. This manager owns ONLY terrain mesh +
# collision streaming; lime / POI / gate placement stays in PlanetGenerator so it
# can be reasoned about and saved as a single deterministic pass.

# Side length of one square chunk in metres.
@export var chunk_size: float = 64.0
# Vertices per chunk edge (resolution). 16 → 17x17 grid of samples per chunk.
@export var chunk_res: int = 16
# Chunk-radius around the tracked body to keep loaded (Chebyshev distance). r=2
# → up to a 5x5 = 25-chunk window. Caps loaded-chunk count (budget guard).
@export var view_radius: int = 2
# Max chunk meshes to BUILD per physics tick — spreads cost so a burst of newly
# entered chunks does not spike a single frame.
@export var build_budget_per_tick: int = 2

# Tracked body whose chunk we center on. Set by the owner (planet.gd) AFTER the
# player/drone exists. Until set, no streaming happens.
var tracked: Node3D = null

# Terrain shaping params (the global height function inputs) + ground material.
# Supplied by PlanetGenerator.configure_chunks().
var _params: Dictionary = {}
var _ground_mat: Material = null

# coord-key "ix,iz" -> StaticBody3D chunk node currently loaded.
var _chunks: Dictionary = {}
# Queue of coord Vector2i still to build (drained build_budget_per_tick/tick).
var _pending: Array[Vector2i] = []
var _last_center: Vector2i = Vector2i(2147483647, 2147483647)


func configure(params: Dictionary, ground_mat: Material) -> void:
	_params = params
	_ground_mat = ground_mat


# Force-build the full window around a world position SYNCHRONOUSLY (no per-tick
# budget). Used at scene load / in headless so the ground exists immediately
# under the spawn before the first frame; streaming takes over afterward.
func prime_around(world_pos: Vector3) -> void:
	var center: Vector2i = _chunk_coord(world_pos)
	_last_center = center
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var coord: Vector2i = center + Vector2i(dx, dz)
			if not _chunks.has(_key(coord)):
				_build_chunk(coord)


func _physics_process(_delta: float) -> void:
	if tracked == null or not is_instance_valid(tracked):
		return
	var center: Vector2i = _chunk_coord(tracked.global_position)
	if center != _last_center:
		_last_center = center
		_refresh_window(center)
	# Drain the build queue under budget so a fresh window doesn't spike a frame.
	var built: int = 0
	while built < build_budget_per_tick and not _pending.is_empty():
		var coord: Vector2i = _pending.pop_front()
		if not _chunks.has(_key(coord)):
			_build_chunk(coord)
		built += 1


# Recompute which chunks should be loaded for `center`: queue missing ones, free
# any now outside the radius. Keeps the loaded set bounded (budget guard).
func _refresh_window(center: Vector2i) -> void:
	var wanted: Dictionary = {}
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var coord: Vector2i = center + Vector2i(dx, dz)
			wanted[_key(coord)] = true
			if not _chunks.has(_key(coord)) and not _pending.has(coord):
				_pending.append(coord)
	# Free distant chunks.
	for key in _chunks.keys():
		if not wanted.has(key):
			var node: Node = _chunks[key]
			if is_instance_valid(node):
				node.queue_free()
			_chunks.erase(key)
	# Drop queued builds that are no longer wanted (player moved past them).
	var kept: Array[Vector2i] = []
	for coord in _pending:
		if wanted.has(_key(coord)):
			kept.append(coord)
	_pending = kept


func loaded_chunk_count() -> int:
	return _chunks.size()


func _chunk_coord(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / chunk_size)),
		int(floor(world_pos.z / chunk_size))
	)


func _key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


# Build one chunk's mesh + trimesh collision by sampling the GLOBAL height
# function at world coordinates. Because every chunk samples the same function at
# true world (x, z), adjacent chunks share identical edge heights → seamless.
func _build_chunk(coord: Vector2i) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Chunk_%d_%d" % [coord.x, coord.y]
	body.collision_layer = 1 | 2   # 1 = player/drone, 2 = camera spring
	body.collision_mask = 0
	body.add_to_group("planet_chunk")
	add_child(body)
	_chunks[_key(coord)] = body

	var res: int = max(chunk_res, 2)
	var origin_x: float = float(coord.x) * chunk_size
	var origin_z: float = float(coord.y) * chunk_size
	var step: float = chunk_size / float(res)
	const UV_SCALE: float = 0.06

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in res:
		for j in res:
			var x0: float = origin_x + i * step
			var z0: float = origin_z + j * step
			var x1: float = x0 + step
			var z1: float = z0 + step
			var p00: Vector3 = Vector3(x0, PlanetGenerator.height_at(x0, z0, _params), z0)
			var p10: Vector3 = Vector3(x1, PlanetGenerator.height_at(x1, z0, _params), z0)
			var p11: Vector3 = Vector3(x1, PlanetGenerator.height_at(x1, z1, _params), z1)
			var p01: Vector3 = Vector3(x0, PlanetGenerator.height_at(x0, z1, _params), z1)
			# Winding faces +Y (up); reversed leaves normals down → lit from below.
			_st_tri(st, p00, p11, p01, UV_SCALE)
			_st_tri(st, p00, p10, p11, UV_SCALE)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = mesh
	if _ground_mat != null:
		mi.material_override = _ground_mat
	body.add_child(mi)

	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)


func _st_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_scale: float) -> void:
	st.set_uv(Vector2(a.x, a.z) * uv_scale)
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z) * uv_scale)
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z) * uv_scale)
	st.add_vertex(c)
