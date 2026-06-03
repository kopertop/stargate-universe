class_name PlanetGenerator
extends Object

# Biome-parameterized, near-infinite procedural planet builder (issue #85).
#
# A per-run PlanetSpec drives generation:
#   { "seed": int, "biome": String, "resource_table": Dictionary,
#     "hazard_params": Dictionary }
# build(world, spec) reads the biome's parameter block from data/biomes.json
# (terrain shaping, ground palette, prop set, walkability), then:
#   * installs a PlanetChunkManager that STREAMS terrain chunks around the body
#     (near-infinite — walking toward any edge reveals more world; no walling rim
#     or fixed bowl). The height field is a SINGLE global function of world
#     (x, z) — height_at() — so chunk borders stitch seamlessly.
#   * places the return Stargate at the fixed "home" anchor (origin),
#   * scatters lime + non-lime POIs deterministically from seed + world position,
#   * seats walk-around props flush on the ground (no jump-requiring ledges).
#
# Walkable everywhere reachable: terrain_height is low and frequencies gentle so
# local slope stays well under the CharacterBody3D floor limit; max_slope_deg()
# lets tests assert it. Props are obstacles to walk AROUND, not steps to hop.
#
# Back-compat: build() also accepts a legacy planets.json row (no "biome" key) —
# it is normalized into a desert spec so the existing Air lime planet keeps
# rendering until the Desert-biome sub-issue migrates the data row.

const STARGATE_SCENE: PackedScene = preload("res://objects/stargate.tscn")
const RESOURCE_NODE_SCRIPT: Script = preload("res://scripts/resource_node.gd")
const PLANET_GATE_SCRIPT: Script = preload("res://scripts/planet_gate.gd")
const POI_NODE_SCRIPT: Script = preload("res://scripts/poi_node.gd")
const CHUNK_MANAGER_SCRIPT: Script = preload("res://scripts/planet_chunk_manager.gd")
const HAZARD_ZONE_SCRIPT: Script = preload("res://scripts/hazard_zone.gd")
const SENSOR_ZONE_SCRIPT: Script = preload("res://scripts/sensor_zone.gd")
const NPC_SCRIPT: Script = preload("res://scripts/npc.gd")

const BIOMES_PATH: String = "res://data/biomes.json"
const DEFAULT_BIOME: String = "desert"

# Biomes the dial/selection flow may roll BY DEFAULT (no story prerequisite).
# A biome whose hazard block declares a `requires_flag` is excluded from the
# pool until that GameState flag is set — see eligible_biomes()/select_biome().
# The Toxic biome carries `requires_flag: "pressure_suits_found"`, so it never
# generates until the crew has found pressure suits (issue #89, decoupled from
# the Equipment epic — a standalone story flag gates it).

# Non-lime points-of-interest the Kino's auto-search can turn up. category →
# [default count, toast/compass label].
const POI_KINDS: Dictionary = {
	"ruin":   [2, "Ancient Ruin"],
	"ore":    [3, "Ore Vein"],
	"water":  [2, "Water Source"],
	"debris": [2, "Crashed Debris"],
}


# Build a planet from a PlanetSpec (or a legacy planets.json row). Returns the
# installed PlanetChunkManager so the scene can hand it the body to track.
static func build(world: Node3D, spec_or_row: Dictionary) -> Node3D:
	if world == null:
		return null
	var spec: Dictionary = _normalize_spec(spec_or_row)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var params: Dictionary = build_params(spec)

	var manager: Node3D = _install_chunk_manager(world, params)
	# Distant low-res backdrop so the floor renders to the horizon (no visible
	# streamed-window edge). High-res chunks stream on top near the body; this is
	# what an aerial Kino sees far out. Visual only (no collision).
	_build_far_ground(world, params)
	_build_return_gate(world, params)
	# Resource-scarcity targeting (issue #86): when the spec's resource_table
	# carries a `clusters` list (scarcest resource guaranteed + 1-2 extras), place
	# a generalized deposit cluster per chosen type. Otherwise fall back to the
	# legacy lime-only placement so a bare planets.json row still renders lime.
	var rt: Dictionary = spec.get("resource_table", {}) if spec.get("resource_table", {}) is Dictionary else {}
	if rt.get("clusters", null) is Array and not (rt["clusters"] as Array).is_empty():
		_build_resource_clusters(world, rt["clusters"], rng, params)
	else:
		_build_lime_nodes(world, spec, rng, params)
	_build_pois(world, spec, rng, params)
	_build_props(world, rng, params)
	# Urban/suburban settlement (issue #90): seat graybox buildings + negotiation
	# residents driven by the biome's `settlement` / `negotiation` blocks. A biome
	# with neither block (desert, jungle, …) places none — so this is urban-only.
	_build_settlement(world, spec, rng, params)
	_build_negotiation_npcs(world, spec, rng, params)
	# Hazard zones: damage traps / hazardous flora (issue #88). Built from the
	# biome's `hazard.traps` block (or a spec hazard_params override), so a biome
	# with no traps block (desert, temperate, …) places none.
	_build_hazard_zones(world, spec, rng, params)
	# Alien-tech security sensors (issue #91): scatter trip-beam/sensor-cone Area3D
	# alarms from the biome's `hazard.sensors` block. A biome with no sensors block
	# (desert, jungle, …) places none — so this is alien-tech-only.
	_build_sensor_zones(world, spec, rng, params)
	return manager


# --- Spec normalization ----------------------------------------------------

# Accept either a real PlanetSpec or a legacy planets.json row. A legacy row has
# no "biome" key — fold its lime/seed fields into a desert spec so the Air lime
# planet keeps working unchanged.
static func _normalize_spec(src: Dictionary) -> Dictionary:
	if src.has("biome"):
		return {
			"seed": int(src.get("seed", 1)),
			"biome": String(src.get("biome", DEFAULT_BIOME)),
			"resource_table": src.get("resource_table", {}) if src.get("resource_table", {}) is Dictionary else {},
			"hazard_params": src.get("hazard_params", {}) if src.get("hazard_params", {}) is Dictionary else {},
			"name": String(src.get("name", "Planet")),
		}
	# Legacy planets.json row → desert spec, carrying the old lime placement.
	return {
		"seed": int(src.get("seed", 1)),
		"biome": DEFAULT_BIOME,
		"resource_table": {
			"lime_nodes": int(src.get("lime_nodes", 5)),
			"lime_per_node": int(src.get("lime_per_node", 1)),
			"lime_min_radius": float(src.get("lime_min_radius", 70.0)),
			"lime_max_radius": float(src.get("lime_max_radius", 200.0)),
			"lime_far_count": int(src.get("lime_far_count", 0)),
			"lime_far_min_radius": float(src.get("lime_far_min_radius", 380.0)),
			"lime_far_max_radius": float(src.get("lime_far_max_radius", 440.0)),
			"lime_far_arc": float(src.get("lime_far_arc", 0.7)),
			"poi_counts": src.get("poi_counts", {}) if src.get("poi_counts", {}) is Dictionary else {},
		},
		"hazard_params": src.get("atmosphere", {}) if src.get("atmosphere", {}) is Dictionary else {},
		"name": String(src.get("name", "Lime World")),
	}


# Read a biome's parameter block from data/biomes.json. Missing file/biome falls
# back to a safe built-in desert block so generation never hard-fails.
static func biome_params(biome: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(BIOMES_PATH, FileAccess.READ)
	var fallback: Dictionary = _builtin_desert_block()
	if f == null:
		return fallback
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return fallback
	var table: Dictionary = parsed
	if table.has(biome) and table[biome] is Dictionary:
		return table[biome]
	if table.has(DEFAULT_BIOME) and table[DEFAULT_BIOME] is Dictionary:
		return table[DEFAULT_BIOME]
	return fallback


# Read the full biome table (id → block) from biomes.json. Empty on a missing /
# malformed file so callers degrade to the built-in default rather than crash.
static func biome_table() -> Dictionary:
	var f: FileAccess = FileAccess.open(BIOMES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# The story flag (if any) a biome's hazard block requires before it may be rolled
# by the selection flow. "" = always eligible. Toxic returns "pressure_suits_found".
static func biome_required_flag(biome: String) -> String:
	var bp: Dictionary = biome_params(biome)
	var hz: Variant = bp.get("hazard", {})
	if hz is Dictionary:
		return String((hz as Dictionary).get("requires_flag", ""))
	return ""


# The biomes the dial/selection flow may roll, given the set of satisfied story
# flags. A biome with a `requires_flag` is EXCLUDED until that flag is true in
# `flags` (a {flag_name: bool} dict — e.g. GameState exposes
# `{"pressure_suits_found": true}`). Order is stable (biomes.json key order) so
# selection is deterministic for a given seed. Issue #89: Toxic only appears once
# pressure_suits_found is set.
static func eligible_biomes(flags: Dictionary = {}) -> Array:
	var table: Dictionary = biome_table()
	var out: Array = []
	for biome in table.keys():
		if not (table[biome] is Dictionary):
			continue
		var hz: Variant = (table[biome] as Dictionary).get("hazard", {})
		var req: String = String((hz as Dictionary).get("requires_flag", "")) if hz is Dictionary else ""
		if req != "" and flags.get(req, false) != true:
			continue
		out.append(String(biome))
	return out


# Deterministically pick ONE biome from the eligible pool for a planet run, seeded
# off `seed` so the same seed + flag set always rolls the same biome. Returns
# DEFAULT_BIOME when the pool is somehow empty (file missing). A toxic roll is only
# possible when pressure_suits_found is among the satisfied flags.
static func select_biome(seed: int, flags: Dictionary = {}) -> String:
	var pool: Array = eligible_biomes(flags)
	if pool.is_empty():
		return DEFAULT_BIOME
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	return String(pool[rng.randi_range(0, pool.size() - 1)])


static func _builtin_desert_block() -> Dictionary:
	return {
		"label": "Desert",
		"terrain": {"height": 3.0, "frequency": 0.006, "detail_frequency": 0.018,
			"detail_strength": 0.25, "slope_limit_deg": 30.0},
		"ground_color": [0.66, 0.56, 0.36],
		"prop_set": "rocks", "prop_density": 0.7,
		"hazard": {"type": "heat", "temperature_c": 48,
			"gate_window": DEFAULT_HOT_GATE_WINDOW, "water_drain_per_sec": DEFAULT_HOT_WATER_DRAIN},
		"walkability": {"max_prop_height": 1.6},
	}


# Departure-window + water-drain defaults. The temperate baseline (180 s, slow
# drain) is the reference a hot biome must beat: heat SHORTENS the window and
# RAISES water drain (issue #87). Used when a biome's hazard block omits them.
const DEFAULT_GATE_WINDOW: float = 180.0
const DEFAULT_WATER_DRAIN: float = 1.0 / 60.0   # ~1 water per minute (temperate)
const DEFAULT_HOT_GATE_WINDOW: float = 150.0
const DEFAULT_HOT_WATER_DRAIN: float = 0.05      # ~1 water per 20 s (heat)


# Departure window (seconds) for a spec's biome, sourced from its hazard block.
# Heat biomes carry a shorter window than the temperate baseline.
static func gate_window_for(spec: Dictionary) -> float:
	var hz: Dictionary = _hazard_block(spec)
	return float(hz.get("gate_window", DEFAULT_GATE_WINDOW))


# Water drained per second on the surface for a spec's biome (heat drains faster).
static func water_drain_for(spec: Dictionary) -> float:
	var hz: Dictionary = _hazard_block(spec)
	return float(hz.get("water_drain_per_sec", DEFAULT_WATER_DRAIN))


# Whether a spec's biome has a breathable atmosphere. A toxin/no-atmosphere biome
# (toxic) reports false; everything else true. Drives the on-surface oxygen drain.
static func breathable_for(spec: Dictionary) -> bool:
	var hz: Dictionary = _hazard_block(spec)
	return hz.get("breathable", true) != false


# Oxygen drained per second on the surface for a spec's biome (issue #89). A
# breathable biome drains 0; a toxin/no-atmosphere biome (toxic) drains at its
# `oxygen_drain_per_sec`. When `suited` is true (the crew has pressure suits —
# GameState.pressure_suits_found), the drain is slowed by the biome's
# `suit_drain_multiplier` (a suit doesn't make it free, just survivable).
static func oxygen_drain_for(spec: Dictionary, suited: bool = false) -> float:
	var hz: Dictionary = _hazard_block(spec)
	if breathable_for(spec):
		return 0.0
	var base: float = float(hz.get("oxygen_drain_per_sec", 0.0))
	if suited:
		base *= float(hz.get("suit_drain_multiplier", 1.0))
	return base


# The biome's hazard block. Prefers the spec's own hazard_params (carried from a
# dialed biome / legacy planets.json atmosphere) but falls back to the biome
# definition in biomes.json so window/drain resolve even for a bare spec.
static func _hazard_block(spec: Dictionary) -> Dictionary:
	var hp: Variant = spec.get("hazard_params", {})
	if hp is Dictionary and (hp as Dictionary).has("gate_window"):
		return hp
	var bp: Dictionary = biome_params(String(spec.get("biome", DEFAULT_BIOME)))
	var hz: Variant = bp.get("hazard", {})
	return hz if hz is Dictionary else {}


# Bundle the global height-function inputs (two seeded noise octaves + biome
# shaping) so the SAME function drives chunk meshes AND where props sit. Pure
# data: safe to pass to PlanetChunkManager and to height_at().
static func build_params(spec: Dictionary) -> Dictionary:
	var seed: int = int(spec.get("seed", 1))
	var biome: String = String(spec.get("biome", DEFAULT_BIOME))
	var bp: Dictionary = biome_params(biome)
	var terrain: Dictionary = bp.get("terrain", {}) if bp.get("terrain", {}) is Dictionary else {}

	var n1: FastNoiseLite = FastNoiseLite.new()
	n1.seed = seed
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n1.frequency = float(terrain.get("frequency", 0.010))
	var n2: FastNoiseLite = FastNoiseLite.new()
	n2.seed = seed + 7
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n2.frequency = float(terrain.get("detail_frequency", 0.040))

	var col: Array = bp.get("ground_color", [0.5, 0.5, 0.5]) if bp.get("ground_color", []) is Array else [0.5, 0.5, 0.5]
	var hz: Dictionary = bp.get("hazard", {}) if bp.get("hazard", {}) is Dictionary else {}
	return {
		"seed": seed,
		"biome": biome,
		"noise": n1,
		"noise2": n2,
		"height": float(terrain.get("height", 5.5)),
		"detail_strength": float(terrain.get("detail_strength", 0.35)),
		"slope_limit_deg": float(terrain.get("slope_limit_deg", 30.0)),
		"landing_radius": 22.0,
		"ground_color": _to_color(col),
		"prop_set": String(bp.get("prop_set", "rocks")),
		"prop_density": float(bp.get("prop_density", 0.7)),
		"max_prop_height": float((bp.get("walkability", {}) as Dictionary).get("max_prop_height", 1.8)) \
			if bp.get("walkability", {}) is Dictionary else 1.8,
		"hazard_type": String(hz.get("type", "none")),
		"gate_window": float(hz.get("gate_window", DEFAULT_GATE_WINDOW)),
		"water_drain_per_sec": float(hz.get("water_drain_per_sec", DEFAULT_WATER_DRAIN)),
		"traps": traps_block(spec),
		"sensors": sensors_block(spec),
	}


# Resolve the trap/hazardous-flora block for a spec (issue #88). A spec's own
# hazard_params.traps wins (dialed planet / per-run override → density tunable
# from data), else the biome's hazard.traps from biomes.json. Empty when the
# biome defines no traps (so non-jungle biomes scatter none).
static func traps_block(spec: Dictionary) -> Dictionary:
	var hp: Variant = spec.get("hazard_params", {})
	if hp is Dictionary and (hp as Dictionary).get("traps", null) is Dictionary:
		return (hp as Dictionary)["traps"]
	var bp: Dictionary = biome_params(String(spec.get("biome", DEFAULT_BIOME)))
	var hz: Variant = bp.get("hazard", {})
	if hz is Dictionary and (hz as Dictionary).get("traps", null) is Dictionary:
		return (hz as Dictionary)["traps"]
	return {}


# Resolve the security-sensor/alarm block for a spec (issue #91). A spec's own
# hazard_params.sensors wins (dialed planet / per-run override → density tunable
# from data), else the biome's hazard.sensors from biomes.json. Empty when the
# biome defines no sensors (so non-alien-tech biomes scatter none).
static func sensors_block(spec: Dictionary) -> Dictionary:
	var hp: Variant = spec.get("hazard_params", {})
	if hp is Dictionary and (hp as Dictionary).get("sensors", null) is Dictionary:
		return (hp as Dictionary)["sensors"]
	var bp: Dictionary = biome_params(String(spec.get("biome", DEFAULT_BIOME)))
	var hz: Variant = bp.get("hazard", {})
	if hz is Dictionary and (hz as Dictionary).get("sensors", null) is Dictionary:
		return (hz as Dictionary)["sensors"]
	return {}


static func _to_color(arr: Array) -> Color:
	if arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(0.5, 0.5, 0.5)


# Resolve the settlement (graybox buildings) block for a spec (issue #90). A
# spec hazard_params.settlement override wins; else the biome's `settlement`
# block from biomes.json. Empty when the biome defines none (so only urban
# scatters buildings).
static func settlement_block(spec: Dictionary) -> Dictionary:
	var hp: Variant = spec.get("hazard_params", {})
	if hp is Dictionary and (hp as Dictionary).get("settlement", null) is Dictionary:
		return (hp as Dictionary)["settlement"]
	var bp: Dictionary = biome_params(String(spec.get("biome", DEFAULT_BIOME)))
	var s: Variant = bp.get("settlement", {})
	return s if s is Dictionary else {}


# Resolve the negotiation (talkable residents) block for a spec (issue #90). A
# spec hazard_params.negotiation override wins; else the biome's `negotiation`
# block from biomes.json. Empty when the biome defines none (urban-only).
static func negotiation_block(spec: Dictionary) -> Dictionary:
	var hp: Variant = spec.get("hazard_params", {})
	if hp is Dictionary and (hp as Dictionary).get("negotiation", null) is Dictionary:
		return (hp as Dictionary)["negotiation"]
	var bp: Dictionary = biome_params(String(spec.get("biome", DEFAULT_BIOME)))
	var n: Variant = bp.get("negotiation", {})
	return n if n is Dictionary else {}


# --- Global height function -------------------------------------------------

# Terrain height at world (x, z). The single source of truth for terrain shape:
# every chunk samples this at true world coordinates, so neighbouring chunks
# agree on shared-edge heights (seamless — no cliffs/gaps). Two gentle noise
# octaves + a flattened landing zone around the origin (gate + spawn). NO walling
# rim and NO radial bowl — the world is open in every direction (streamed).
#
# Walkable: amplitude is small and frequencies low, so the gradient (hence local
# slope) stays well under the CharacterBody3D floor limit everywhere.
static func height_at(x: float, z: float, params: Dictionary) -> float:
	var n1: FastNoiseLite = params["noise"]
	var n2: FastNoiseLite = params["noise2"]
	var amp: float = float(params.get("height", 5.5))
	var detail: float = float(params.get("detail_strength", 0.35))
	var h: float = n1.get_noise_2d(x, z) * amp
	h += n2.get_noise_2d(x, z) * amp * detail
	# Flatten toward the centre so the gate + landing zone sit on stable ground.
	var dist: float = sqrt(x * x + z * z)
	var landing: float = float(params.get("landing_radius", 22.0))
	var land_t: float = smoothstep(0.0, 1.0, clampf(dist / max(landing, 0.001), 0.0, 1.0))
	return lerpf(0.0, h, land_t)


# Worst-case local slope (degrees) of the height field over a sampled region,
# centred on the origin out to `radius`, stepping every `step` metres. Tests
# assert this stays under the CharacterBody3D floor limit (jump never required).
static func max_slope_deg(params: Dictionary, radius: float, step: float) -> float:
	var worst: float = 0.0
	var x: float = -radius
	while x <= radius:
		var z: float = -radius
		while z <= radius:
			var h: float = height_at(x, z, params)
			var hx: float = height_at(x + step, z, params)
			var hz: float = height_at(x, z + step, params)
			var slope_x: float = rad_to_deg(atan(abs(hx - h) / step))
			var slope_z: float = rad_to_deg(atan(abs(hz - h) / step))
			worst = max(worst, max(slope_x, slope_z))
			z += step
		x += step
	return worst


# --- Terrain streaming ------------------------------------------------------

static func _install_chunk_manager(world: Node3D, params: Dictionary) -> Node3D:
	var manager: Node3D = CHUNK_MANAGER_SCRIPT.new()
	manager.name = "PlanetGround"   # keep the historical node name (scene_boot, saves)
	world.add_child(manager)
	manager.call("configure", params, _ground_mat(params))
	# Prime the window around the origin SYNCHRONOUSLY so ground exists under the
	# spawn before the first frame; planet.gd hands the body over for streaming.
	manager.call("prime_around", Vector3.ZERO)
	return manager


# Far-ground backdrop: ONE large, low-resolution ground mesh sampling the SAME
# global height function so it stitches with the streamed chunks, sat a touch
# BELOW them (epsilon) so the high-res chunks always win near the body (no
# z-fighting). Covers out to the camera far plane so an aerial Kino sees floor to
# the horizon instead of the streamed-window edge ("edge of the world" fix).
# Visual only — collision stays with the streamed chunks. Built once; centered at
# origin, which covers the recon/landing area the Kino patrols.
const FAR_GROUND_HALF_EXTENT: float = 4000.0   # metres from origin (>= Kino cam far)
const FAR_GROUND_CELLS: int = 200              # 40 m cells over the 8 km span — coarse
const FAR_GROUND_DROP: float = 0.5             # sit this far under the streamed chunks
static func _build_far_ground(world: Node3D, params: Dictionary) -> void:
	var span: float = FAR_GROUND_HALF_EXTENT * 2.0
	var step: float = span / float(FAR_GROUND_CELLS)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const UV_SCALE: float = 0.06
	for i in FAR_GROUND_CELLS:
		for j in FAR_GROUND_CELLS:
			var x0: float = -FAR_GROUND_HALF_EXTENT + float(i) * step
			var z0: float = -FAR_GROUND_HALF_EXTENT + float(j) * step
			var x1: float = x0 + step
			var z1: float = z0 + step
			var p00: Vector3 = Vector3(x0, height_at(x0, z0, params) - FAR_GROUND_DROP, z0)
			var p10: Vector3 = Vector3(x1, height_at(x1, z0, params) - FAR_GROUND_DROP, z0)
			var p11: Vector3 = Vector3(x1, height_at(x1, z1, params) - FAR_GROUND_DROP, z1)
			var p01: Vector3 = Vector3(x0, height_at(x0, z1, params) - FAR_GROUND_DROP, z1)
			# Same +Y winding as the streamed chunks (see _build_chunk).
			st.set_uv(Vector2(p00.x, p00.z) * UV_SCALE); st.add_vertex(p00)
			st.set_uv(Vector2(p11.x, p11.z) * UV_SCALE); st.add_vertex(p11)
			st.set_uv(Vector2(p01.x, p01.z) * UV_SCALE); st.add_vertex(p01)
			st.set_uv(Vector2(p00.x, p00.z) * UV_SCALE); st.add_vertex(p00)
			st.set_uv(Vector2(p10.x, p10.z) * UV_SCALE); st.add_vertex(p10)
			st.set_uv(Vector2(p11.x, p11.z) * UV_SCALE); st.add_vertex(p11)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "FarGround"
	mi.mesh = st.commit()
	mi.material_override = _ground_mat(params)
	# Never let the backdrop be frustum-culled away when only its far edge is in view.
	mi.extra_cull_margin = FAR_GROUND_HALF_EXTENT
	world.add_child(mi)


static func _ground_mat(params: Dictionary) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = params.get("ground_color", Color(0.42, 0.39, 0.28))
	m.roughness = 0.95
	m.metallic = 0.0
	# Double-sided so a graybox terrain never vanishes on a winding flip.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- Return gate (fixed home anchor) ----------------------------------------

static func _build_return_gate(world: Node3D, params: Dictionary) -> void:
	var ground_y: float = height_at(0.0, -9.0, params)
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
	portal.set("target_spawn", "FromPlanet")
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(4.4, 3.0, 1.2)
	cs.shape = shape
	portal.add_child(cs)
	world.add_child(portal)


# --- Resource deposits ------------------------------------------------------
#
# Per-resource visual identity for generalized deposit nodes (issue #86). Each
# entry: albedo + emission tint so water/food/parts/lime read distinctly while
# reusing the SAME deposit geometry + resource_node.gd mineable behaviour.
const RESOURCE_LOOKS: Dictionary = {
	"lime":  {"albedo": [0.93, 0.94, 0.91], "emission": [0.86, 0.90, 0.96], "energy": 0.28},
	"water": {"albedo": [0.42, 0.62, 0.86], "emission": [0.30, 0.55, 0.92], "energy": 0.40},
	"food":  {"albedo": [0.46, 0.66, 0.38], "emission": [0.40, 0.70, 0.30], "energy": 0.22},
	"parts": {"albedo": [0.62, 0.60, 0.58], "emission": [0.70, 0.55, 0.30], "energy": 0.18},
}


# Place one mineable deposit cluster per chosen resource type (issue #86). Each
# cluster entry: { type, nodes, per_node, min_radius, max_radius }. Node names
# are unique-per-type ("WaterNode1", "FoodNode2", lime stays "LimeNode<n>" for
# back-compat / existing discovery keys) so discovery survives save/load.
static func _build_resource_clusters(world: Node3D, clusters: Array,
		rng: RandomNumberGenerator, params: Dictionary) -> void:
	for cluster in clusters:
		if not (cluster is Dictionary):
			continue
		var c: Dictionary = cluster
		var type: String = String(c.get("type", GameState.AIR_LIME_RESOURCE))
		var count: int = int(c.get("nodes", 4))
		var amount: int = int(c.get("per_node", 1))
		var min_r: float = float(c.get("min_radius", 50.0))
		var max_r: float = float(c.get("max_radius", 120.0))
		var mat: StandardMaterial3D = _resource_mat(type)
		for i in count:
			var angle: float = (TAU / float(max(count, 1))) * float(i) + rng.randf_range(-0.4, 0.4)
			var dist: float = rng.randf_range(min_r, max_r)
			_spawn_resource_deposit(world, type, i + 1, angle, dist, amount, mat, params)


# Per-type deposit material from RESOURCE_LOOKS (falls back to lime's chalky
# white for an unknown type so a deposit is never invisible).
static func _resource_mat(type: String) -> StandardMaterial3D:
	var look: Dictionary = RESOURCE_LOOKS.get(type, RESOURCE_LOOKS["lime"]) if RESOURCE_LOOKS.has(type) else RESOURCE_LOOKS["lime"]
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = _to_color(look.get("albedo", [0.93, 0.94, 0.91]))
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = _to_color(look.get("emission", [0.86, 0.90, 0.96]))
	mat.emission_energy_multiplier = float(look.get("energy", 0.28))
	return mat


static func _build_lime_nodes(world: Node3D, spec: Dictionary, rng: RandomNumberGenerator, params: Dictionary) -> void:
	var rt: Dictionary = spec.get("resource_table", {}) if spec.get("resource_table", {}) is Dictionary else {}
	var count: int = int(rt.get("lime_nodes", 4))
	var amount: int = int(rt.get("lime_per_node", 1))
	var min_r: float = float(rt.get("lime_min_radius", 40.0))
	var max_r: float = float(rt.get("lime_max_radius", 95.0))
	var lime_mat: StandardMaterial3D = _resource_mat(GameState.AIR_LIME_RESOURCE)

	var idx: int = 0
	for i in count:
		var angle: float = (TAU / float(max(count, 1))) * float(i) + rng.randf_range(-0.4, 0.4)
		var dist: float = rng.randf_range(min_r, max_r)
		idx += 1
		_spawn_resource_deposit(world, GameState.AIR_LIME_RESOURCE, idx, angle, dist, amount, lime_mat, params)

	var far_count: int = int(rt.get("lime_far_count", 0))
	if far_count > 0:
		var far_min: float = float(rt.get("lime_far_min_radius", min_r * 4.0))
		var far_max: float = float(rt.get("lime_far_max_radius", min_r * 5.0))
		var far_arc: float = float(rt.get("lime_far_arc", 0.6))
		var cluster_center: float = rng.randf_range(0.0, TAU)
		for j in far_count:
			var angle: float = cluster_center + rng.randf_range(-far_arc * 0.5, far_arc * 0.5)
			var dist: float = rng.randf_range(far_min, far_max)
			idx += 1
			_spawn_resource_deposit(world, GameState.AIR_LIME_RESOURCE, idx, angle, dist, amount, lime_mat, params)


# Generalized mineable deposit (issue #86). Lime keeps node name "LimeNode<idx>"
# and group "lime_node" for back-compat; other types use "<Type>Node<idx>" and a
# per-type group so per-type scans (compass, fog-of-war) can target them.
static func _spawn_resource_deposit(world: Node3D, type: String, idx: int, angle: float,
		dist: float, amount: int, mat: StandardMaterial3D, params: Dictionary) -> void:
	var x: float = cos(angle) * dist
	var z: float = sin(angle) * dist
	var node: StaticBody3D = StaticBody3D.new()
	node.set_script(RESOURCE_NODE_SCRIPT)
	node.name = "%sNode%d" % [type.capitalize(), idx]
	node.position = Vector3(x, height_at(x, z, params), z)
	node.set("resource_type", type)
	node.set("amount", amount)
	node.set("source_label", "%s deposit" % type.capitalize())
	node.add_to_group("%s_node" % type)

	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	cs.shape = shape
	cs.position = Vector3(0.0, 0.65, 0.0)
	node.add_child(cs)

	_add_box(node, Vector3(0.0, 0.22, 0.0), Vector3(1.15, 0.44, 0.95), mat)
	_add_box(node, Vector3(-0.34, 0.50, 0.10), Vector3(0.52, 0.46, 0.50), mat)
	_add_box(node, Vector3(0.30, 0.44, -0.22), Vector3(0.46, 0.40, 0.52), mat)
	_add_box(node, Vector3(0.10, 0.64, 0.22), Vector3(0.34, 0.32, 0.36), mat)
	world.add_child(node)


# --- Non-lime POIs ----------------------------------------------------------

# Deterministic from seed: a node name always maps to the same spot (discovery
# survives save/load). Placed in a ring between the landing zone and the lime
# band so the auto-search Kino has varied things to find.
static func _build_pois(world: Node3D, spec: Dictionary, rng: RandomNumberGenerator, params: Dictionary) -> void:
	var rt: Dictionary = spec.get("resource_table", {}) if spec.get("resource_table", {}) is Dictionary else {}
	var counts: Dictionary = rt.get("poi_counts", {}) if rt.get("poi_counts", {}) is Dictionary else {}
	var min_r: float = float(params.get("landing_radius", 22.0)) + 28.0
	var max_r: float = min_r + 120.0
	for cat in POI_KINDS.keys():
		var pspec: Array = POI_KINDS[cat]
		var n: int = int(counts.get(cat, pspec[0]))
		var label: String = String(pspec[1])
		for i in n:
			var angle: float = rng.randf_range(0.0, TAU)
			var dist: float = rng.randf_range(min_r, max_r)
			var x: float = cos(angle) * dist
			var z: float = sin(angle) * dist
			var poi: Node3D = POI_NODE_SCRIPT.new()
			poi.name = "Poi_%s_%d" % [cat, i + 1]
			poi.set("poi_category", cat)
			poi.set("poi_label", label)
			poi.position = Vector3(x, height_at(x, z, params), z)
			world.add_child(poi)


# --- Walk-around props ------------------------------------------------------

# Seat biome props FLUSH on the ground as obstacles to walk AROUND, capped at the
# biome's max_prop_height so none is a step the player must HOP. Deterministic
# from seed (the shared RNG), placed in a band near the landing zone.
static func _build_props(world: Node3D, rng: RandomNumberGenerator, params: Dictionary) -> void:
	var prop_mat: StandardMaterial3D = StandardMaterial3D.new()
	var base: Color = params.get("ground_color", Color(0.42, 0.39, 0.28))
	prop_mat.albedo_color = base.darkened(0.35)
	prop_mat.roughness = 0.9
	var density: float = float(params.get("prop_density", 0.7))
	var cap: float = float(params.get("max_prop_height", 1.8))
	var n: int = int(round(48.0 * density))
	for i in n:
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(8.0, 160.0)
		# Height capped UNDER the floor-step a CharacterBody3D would have to jump.
		var h: float = rng.randf_range(0.4, cap)
		var w: float = rng.randf_range(0.5, 1.8)
		var d: float = rng.randf_range(0.5, 1.8)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var prop: StaticBody3D = StaticBody3D.new()
		prop.name = "Prop%d" % i
		prop.collision_layer = 1   # walk-blocker (player), not camera
		prop.collision_mask = 0
		prop.add_to_group("planet_prop")
		# Seat flush: bottom at ground, mesh + collider both lifted by h/2.
		prop.position = Vector3(x, height_at(x, z, params), z)
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(w, h, d)
		mesh_inst.mesh = mesh
		mesh_inst.material_override = prop_mat
		mesh_inst.position = Vector3(0.0, h * 0.5, 0.0)
		prop.add_child(mesh_inst)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(w, h, d)
		cs.shape = box
		cs.position = Vector3(0.0, h * 0.5, 0.0)
		prop.add_child(cs)
		prop.rotation.y = rng.randf_range(0.0, TAU)
		world.add_child(prop)


# --- Urban settlement: buildings + negotiation residents (issue #90) --------
#
# The Urban/suburban biome is the NEGOTIATION biome: no combat, no damage
# hazard — the "hazard" is social (a bad trade costs time / closes a resource,
# never death). It seats graybox buildings on the walkable streets and places
# talkable residents (the existing npc.gd + DialogScreen choice-tree system) who
# can be negotiated with for a needed resource, a warning, or passage.

# Seat graybox settlement buildings FLUSH on the ground as walk-around blocks,
# laid out in a loose ring around the landing zone so streets stay walkable
# between them. Buildings are visual structures (taller than scatter props) but
# the player never has to jump them — they're obstacles to route around, like
# the ship's room walls. Deterministic from the shared RNG (placement survives
# save/load). No-op for a biome with no `settlement` block.
static func _build_settlement(world: Node3D, spec: Dictionary,
		rng: RandomNumberGenerator, params: Dictionary) -> void:
	var s: Dictionary = settlement_block(spec)
	if s.is_empty():
		return
	var count: int = int(s.get("building_count", 0))
	if count <= 0:
		return
	var min_r: float = float(s.get("min_radius", 18.0))
	var max_r: float = float(s.get("max_radius", 130.0))
	var col: Array = s.get("building_color", [0.52, 0.52, 0.56]) if s.get("building_color", []) is Array else [0.52, 0.52, 0.56]
	var base: Color = _to_color(col)
	for i in count:
		var angle: float = (TAU / float(max(count, 1))) * float(i) + rng.randf_range(-0.5, 0.5)
		var dist: float = rng.randf_range(min_r, max_r)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var w: float = rng.randf_range(3.0, 6.0)
		var d: float = rng.randf_range(3.0, 6.0)
		var h: float = rng.randf_range(3.5, 8.0)
		var building: StaticBody3D = StaticBody3D.new()
		building.name = "Building%d" % (i + 1)
		building.collision_layer = 1 | 2   # block player AND camera (it's a wall)
		building.collision_mask = 0
		building.add_to_group("settlement_building")
		building.position = Vector3(x, height_at(x, z, params), z)
		building.rotation.y = rng.randf_range(0.0, TAU)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		# Slight per-building tonal variation so the street doesn't read as clones.
		mat.albedo_color = base.lightened(rng.randf_range(-0.12, 0.12))
		mat.roughness = 0.92
		_add_box(building, Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, d), mat)
		var cs: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(w, h, d)
		cs.shape = box
		cs.position = Vector3(0.0, h * 0.5, 0.0)
		building.add_child(cs)
		world.add_child(building)


# Place the biome's negotiation residents (issue #90). Each resident is a
# graybox StaticBody3D running npc.gd with a choice-tree dialogue from data; at
# least one offers a `trade` that yields a needed resource via the dialog
# `action: "trade:<resource>:<amount>"` path (npc.gd::grant_trade). Residents are
# in group "negotiation_npc" so a test / compass can enumerate them. No-op for a
# biome with no `negotiation` block. Deterministic placement from the shared RNG.
static func _build_negotiation_npcs(world: Node3D, spec: Dictionary,
		rng: RandomNumberGenerator, params: Dictionary) -> void:
	var neg: Dictionary = negotiation_block(spec)
	if neg.is_empty():
		return
	var residents: Array = neg.get("residents", []) if neg.get("residents", []) is Array else []
	if residents.is_empty():
		return
	var count: int = int(neg.get("npc_count", residents.size()))
	count = min(count, residents.size())
	var min_r: float = float(neg.get("min_radius", 16.0))
	var max_r: float = float(neg.get("max_radius", 60.0))
	for i in count:
		var r: Dictionary = residents[i] if residents[i] is Dictionary else {}
		if r.is_empty():
			continue
		var angle: float = (TAU / float(max(count, 1))) * float(i) + rng.randf_range(-0.3, 0.3)
		var dist: float = rng.randf_range(min_r, max_r)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		_spawn_negotiation_npc(world, r, i + 1, Vector3(x, height_at(x, z, params), z))


# Build one negotiation resident: a graybox capsule body running npc.gd, wired
# with the resident's choice-tree dialogue. A resident whose `trade` names a
# resource grants it once via the dialog action path. Graybox (no GLB) keeps the
# urban crowd headless-safe and avoids the Kenney colormap-sibling trap.
static func _spawn_negotiation_npc(world: Node3D, r: Dictionary, idx: int, pos: Vector3) -> void:
	var name_s: String = String(r.get("name", "Resident %d" % idx))
	var body: StaticBody3D = StaticBody3D.new()
	body.set_script(NPC_SCRIPT)
	# Unique per-instance node name so NPCState position/dialogue keys never
	# collide (NPCState keys by node name globally).
	body.name = "Resident%d_%s" % [idx, name_s.replace(" ", "")]
	body.position = pos
	body.set("character_name", name_s)
	var tree: Array = r.get("tree", []) if r.get("tree", []) is Array else []
	body.set("dialogue_tree", tree)

	var tint: Color = _to_color(r.get("tint", [0.7, 0.65, 0.55]) if r.get("tint", []) is Array else [0.7, 0.65, 0.55])
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.8
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cap: CapsuleMesh = CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	mi.mesh = cap
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(mi)

	# Interact + walk-block collider sized ~1.7 m tall so the chest-height
	# interact ray (1.1 m) lands a hit (feedback_interactable_ray_chest_height).
	# Interactable._ready sets collision_layer = 4; npc.gd adds layer 1 after.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	cs.shape = shape
	cs.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(cs)

	body.add_to_group("negotiation_npc")
	world.add_child(body)


# --- Hazard zones (damage traps / hazardous flora) --------------------------
#
# Scatter HazardZone Area3D volumes from the biome's trap block (issue #88).
# Each zone deals steady damage while the player stands in it and routes the
# no-death knockout when health hits 0 (cause-tagged). Telegraphed FAIRLY: a
# distinct red-tinted flora cluster marks the trap so a careful player can read
# it. Deterministic from the shared RNG so placement survives save/load.
#
# Density + strength come from `params.traps` (resolved from biome hazard.traps
# or a spec hazard_params override) — hazard density is tunable from data.
const HAZARD_FLORA_TINT: Color = Color(0.52, 0.16, 0.20)   # sickly red-green warning hue
static func _build_hazard_zones(world: Node3D, spec: Dictionary,
		rng: RandomNumberGenerator, params: Dictionary) -> void:
	var traps: Dictionary = params.get("traps", {}) if params.get("traps", {}) is Dictionary else {}
	if traps.is_empty():
		return
	var count: int = int(traps.get("count", 0))
	if count <= 0:
		return
	var dps: float = float(traps.get("damage_per_second", 12.0))
	var tick: float = float(traps.get("tick_interval", 0.5))
	var radius: float = float(traps.get("radius", 2.4))
	var min_r: float = float(traps.get("min_radius", 26.0))
	var max_r: float = float(traps.get("max_radius", 150.0))
	var trap_cause: String = String(traps.get("cause", "trap"))
	var tell: String = String(traps.get("telegraph", "rustling vines"))

	var flora_mat: StandardMaterial3D = StandardMaterial3D.new()
	flora_mat.albedo_color = HAZARD_FLORA_TINT
	flora_mat.roughness = 0.85
	flora_mat.emission_enabled = true
	flora_mat.emission = HAZARD_FLORA_TINT
	flora_mat.emission_energy_multiplier = 0.22

	for i in count:
		var angle: float = (TAU / float(max(count, 1))) * float(i) + rng.randf_range(-0.4, 0.4)
		var dist: float = rng.randf_range(min_r, max_r)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var ground_y: float = height_at(x, z, params)

		var zone: Area3D = HAZARD_ZONE_SCRIPT.new()
		zone.name = "HazardZone%d" % (i + 1)
		zone.position = Vector3(x, ground_y, z)
		zone.set("damage_per_second", dps)
		zone.set("tick_interval", tick)
		zone.set("cause", trap_cause)
		zone.set("telegraph", tell)

		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(radius * 2.0, 3.0, radius * 2.0)
		cs.shape = shape
		cs.position = Vector3(0.0, 1.5, 0.0)
		zone.add_child(cs)

		# The "tell": a low cluster of red-tinted flora fronds the player can read.
		_add_box(zone, Vector3(0.0, 0.30, 0.0), Vector3(0.9, 0.6, 0.9), flora_mat)
		_add_box(zone, Vector3(-0.5, 0.55, 0.3), Vector3(0.4, 1.1, 0.4), flora_mat)
		_add_box(zone, Vector3(0.45, 0.65, -0.25), Vector3(0.4, 1.3, 0.4), flora_mat)
		world.add_child(zone)


# --- Security sensors / alarms (alien-tech biome, issue #91) -----------------
#
# Scatter SensorZone Area3D trip-beams from the biome's `hazard.sensors` block.
# Crossing one raises a persistent alarm whose defense damage ESCALATES while the
# alarm is up; a flooring tick routes the no-death knockout (cause-tagged
# "alien_defense"). Telegraphed FAIRLY: each sensor owns a tall, glowing emissive
# beam pillar + a warning floor strip so a careful player can read it and route
# AROUND — avoidance is skill, not luck. Deterministic from the shared RNG so
# placement survives save/load.
#
# Density + strength come from `params.sensors` (resolved from biome hazard.sensors
# or a spec hazard_params override) — hazard density is tunable from data.
const SENSOR_BEAM_TINT: Color = Color(0.85, 0.30, 0.28)    # alert-red Ancient light-beam
const SENSOR_STRIP_TINT: Color = Color(0.30, 0.78, 0.85)   # cyan floor warning strip
static func _build_sensor_zones(world: Node3D, spec: Dictionary,
		rng: RandomNumberGenerator, params: Dictionary) -> void:
	var sensors: Dictionary = params.get("sensors", {}) if params.get("sensors", {}) is Dictionary else {}
	if sensors.is_empty():
		return
	var count: int = int(sensors.get("count", 0))
	if count <= 0:
		return
	var base_dps: float = float(sensors.get("base_damage_per_second", 10.0))
	var escalation: float = float(sensors.get("escalation", 1.5))
	var max_dps: float = float(sensors.get("max_damage_per_second", 60.0))
	var tick: float = float(sensors.get("tick_interval", 0.5))
	var radius: float = float(sensors.get("radius", 2.0))
	var min_r: float = float(sensors.get("min_radius", 24.0))
	var max_r: float = float(sensors.get("max_radius", 150.0))
	var alarm_cause: String = String(sensors.get("cause", "alien_defense"))
	var tell: String = String(sensors.get("telegraph", "humming light-beam"))

	var beam_mat: StandardMaterial3D = StandardMaterial3D.new()
	beam_mat.albedo_color = SENSOR_BEAM_TINT
	beam_mat.roughness = 0.4
	beam_mat.emission_enabled = true
	beam_mat.emission = SENSOR_BEAM_TINT
	beam_mat.emission_energy_multiplier = 1.6

	var strip_mat: StandardMaterial3D = StandardMaterial3D.new()
	strip_mat.albedo_color = SENSOR_STRIP_TINT
	strip_mat.roughness = 0.5
	strip_mat.emission_enabled = true
	strip_mat.emission = SENSOR_STRIP_TINT
	strip_mat.emission_energy_multiplier = 0.6

	for i in count:
		var angle: float = (TAU / float(max(count, 1))) * float(i) + rng.randf_range(-0.4, 0.4)
		var dist: float = rng.randf_range(min_r, max_r)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		var ground_y: float = height_at(x, z, params)

		var zone: Area3D = SENSOR_ZONE_SCRIPT.new()
		zone.name = "SensorZone%d" % (i + 1)
		zone.position = Vector3(x, ground_y, z)
		zone.set("base_damage_per_second", base_dps)
		zone.set("escalation", escalation)
		zone.set("max_damage_per_second", max_dps)
		zone.set("tick_interval", tick)
		zone.set("cause", alarm_cause)
		zone.set("telegraph", tell)

		var cs: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = Vector3(radius * 2.0, 4.0, radius * 2.0)
		cs.shape = shape
		cs.position = Vector3(0.0, 2.0, 0.0)
		zone.add_child(cs)

		# The "tell": a tall glowing red beam pillar (the sensor cone) + a cyan
		# floor warning strip around it — both read as DANGER from a distance.
		_add_box(zone, Vector3(0.0, 2.2, 0.0), Vector3(0.18, 4.4, 0.18), beam_mat)
		_add_box(zone, Vector3(0.0, 0.06, 0.0), Vector3(radius * 2.0, 0.12, radius * 2.0), strip_mat)
		world.add_child(zone)


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
