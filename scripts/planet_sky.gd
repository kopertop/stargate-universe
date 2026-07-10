class_name PlanetSky
extends RefCounted

# Alien-sky roller + applier (gallery finding: planets reused the ship's
# main-environment.tres, so every world wore the same purple-banded sky).
#
# roll(spec) is PURE and deterministic: the planet spec's seed decides every
# celestial die — sun count, moons, gas giant, ring arc, aurora, palette —
# weighted per biome by data/skies.json (desert worlds roll binary/trinary
# suns, cold/harsh worlds crowd the night sky with moons and auroras,
# alien_tech worlds get the full lightshow). Same spec → same sky forever,
# so a save reload lands under the identical heavens.
#
# apply(planet_root, spec) turns a roll into a live sky: a ShaderMaterial on
# shaders/alien_sky.gdshader (gradient + hash starfield + suns + phase-shaded
# moons + ring band + aurora curtains — no textures, no downloads), a fresh
# Environment with sky-driven ambient, and the scene Sun light re-tinted to
# the primary star so ground lighting agrees with the sky.

const SKY_SHADER: Shader = preload("res://shaders/alien_sky.gdshader")
const SKIES_PATH: String = "res://data/skies.json"
const SKY_SEED_SALT: int = 0x5C1E5   # decorrelate from terrain/loot rolls

const MAX_SUNS: int = 3
const MAX_MOONS: int = 4

# Aurora hues rolled uniformly — classic green/teal plus alien magenta/violet.
const AURORA_HUES: Array = [
	Color(0.20, 0.95, 0.55), Color(0.15, 0.85, 0.80),
	Color(0.75, 0.30, 0.95), Color(0.95, 0.35, 0.55),
]
# Companion-sun tints (the primary stays near-white; extras read alien).
const EXTRA_SUN_TINTS: Array = [
	Color(1.0, 0.55, 0.30), Color(1.0, 0.35, 0.25),
	Color(0.65, 0.75, 1.0), Color(1.0, 0.85, 0.45),
]
const MOON_TINTS: Array = [
	Color(0.82, 0.82, 0.85), Color(0.85, 0.78, 0.68),
	Color(0.70, 0.76, 0.86), Color(0.84, 0.70, 0.72),
]
const GIANT_TINTS: Array = [
	Color(0.85, 0.70, 0.55), Color(0.60, 0.70, 0.85),
	Color(0.75, 0.62, 0.80), Color(0.70, 0.80, 0.66),
]

static var _config_cache: Dictionary = {}
static var _config_loaded: bool = false


# --- config -------------------------------------------------------------------

static func config_for(biome: String) -> Dictionary:
	_load_config()
	var base: Dictionary = _config_cache.get("default", {})
	var block: Variant = _config_cache.get(biome, {})
	var merged: Dictionary = base.duplicate(true)
	if block is Dictionary:
		for k in (block as Dictionary).keys():
			merged[k] = (block as Dictionary)[k]
	return merged


static func _load_config() -> void:
	if _config_loaded:
		return
	_config_loaded = true
	var f: FileAccess = FileAccess.open(SKIES_PATH, FileAccess.READ)
	if f == null:
		push_error("PlanetSky: cannot open %s" % SKIES_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_config_cache = parsed


# --- the roll -----------------------------------------------------------------

# Deterministic sky parameters for a planet spec. Everything the shader needs,
# as plain data — unit-testable without a renderer.
static func roll(spec: Dictionary) -> Dictionary:
	var biome: String = String(spec.get("biome", "desert"))
	var cfg: Dictionary = config_for(biome)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (int(spec.get("seed", 0)) ^ SKY_SEED_SALT) & 0x7fffffff

	# Palette: one [top, horizon] pair from the biome's set.
	var palettes: Array = cfg.get("palettes", []) as Array
	var top: Color = Color(0.18, 0.32, 0.58)
	var horizon: Color = Color(0.62, 0.74, 0.86)
	if not palettes.is_empty():
		var pick: Array = palettes[rng.randi_range(0, palettes.size() - 1)] as Array
		top = _col(pick[0])
		horizon = _col(pick[1])

	# Suns: [min,max] band; each slot past min must win extra_sun_chance.
	var sun_range: Array = cfg.get("suns", [1, 1]) as Array
	var sun_min: int = clampi(int(sun_range[0]), 1, MAX_SUNS)
	var sun_max: int = clampi(int(sun_range[1]), sun_min, MAX_SUNS)
	var extra_chance: float = float(cfg.get("extra_sun_chance", 0.0))
	var sun_count: int = sun_min
	while sun_count < sun_max and rng.randf() < extra_chance:
		sun_count += 1
	var suns: Array = []
	var primary_az: float = rng.randf_range(0.0, TAU)
	for i in sun_count:
		var el: float = rng.randf_range(0.55, 1.0) if i == 0 else rng.randf_range(0.25, 0.75)
		var az: float = primary_az + (0.0 if i == 0 else rng.randf_range(0.35, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0))
		var tint: Color = Color(1.0, 0.97, 0.90) if i == 0 else (EXTRA_SUN_TINTS[rng.randi_range(0, EXTRA_SUN_TINTS.size() - 1)] as Color)
		suns.append({
			"dir": _dir(az, el),
			"color": tint,
			"size": rng.randf_range(0.035, 0.055) if i == 0 else rng.randf_range(0.018, 0.035),
		})

	# Moons + optional parent gas giant (a huge banded disc low on the sky).
	var moon_range: Array = cfg.get("moons", [0, 2]) as Array
	var moon_count: int = rng.randi_range(int(moon_range[0]), int(moon_range[1]))
	var giant: bool = rng.randf() < float(cfg.get("gas_giant_chance", 0.0))
	moon_count = mini(moon_count, MAX_MOONS - (1 if giant else 0))
	var moons: Array = []
	for i in moon_count:
		var phase: float = rng.randf_range(0.0, TAU)
		moons.append({
			"dir": _dir(rng.randf_range(0.0, TAU), rng.randf_range(0.25, 1.1)),
			"color": MOON_TINTS[rng.randi_range(0, MOON_TINTS.size() - 1)],
			"size": rng.randf_range(0.02, 0.05),
			"phase": Vector2(cos(phase), sin(phase)),
			"band": 0.0,
		})
	if giant:
		var gphase: float = rng.randf_range(0.0, TAU)
		moons.append({
			"dir": _dir(rng.randf_range(0.0, TAU), rng.randf_range(0.18, 0.45)),
			"color": GIANT_TINTS[rng.randi_range(0, GIANT_TINTS.size() - 1)],
			"size": rng.randf_range(0.11, 0.19),
			"phase": Vector2(cos(gphase), sin(gphase)),
			"band": rng.randf_range(0.7, 1.0),
		})

	# Ring arc across the sky.
	var ring: float = 0.0
	var ring_normal: Vector3 = Vector3.UP
	if rng.randf() < float(cfg.get("ring_chance", 0.0)):
		ring = rng.randf_range(0.55, 1.0)
		var tilt: float = rng.randf_range(0.25, 0.8)
		ring_normal = _dir(rng.randf_range(0.0, TAU), 1.5708 - tilt)

	# Aurora curtains.
	var aurora: float = 0.0
	var aurora_col: Color = AURORA_HUES[0]
	if rng.randf() < float(cfg.get("aurora_chance", 0.0)):
		aurora = rng.randf_range(0.5, 1.0)
		aurora_col = AURORA_HUES[rng.randi_range(0, AURORA_HUES.size() - 1)]

	var density: float = float(cfg.get("star_density", 0.3)) * rng.randf_range(0.8, 1.2)

	return {
		"biome": biome,
		"top": top,
		"horizon": horizon,
		"ground": horizon.darkened(0.6),
		"suns": suns,
		"moons": moons,
		"ring_amount": ring,
		"ring_normal": ring_normal,
		"ring_color": Color(0.82, 0.76, 0.66),
		"aurora_amount": aurora,
		"aurora_color": aurora_col,
		"star_density": clampf(density, 0.0, 1.0),
		"star_seed": float(rng.randi_range(1, 9999)),
	}


# --- application ----------------------------------------------------------------

# Build the Environment + sky material for a roll and install it on the planet
# scene: WorldEnvironment child named "Environment", DirectionalLight3D "Sun".
static func apply(planet_root: Node, spec: Dictionary) -> Dictionary:
	var params: Dictionary = roll(spec)
	var env_node: WorldEnvironment = planet_root.get_node_or_null("Environment") as WorldEnvironment
	if env_node != null:
		env_node.environment = build_environment(params)
	var sun: DirectionalLight3D = planet_root.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null and not (params["suns"] as Array).is_empty():
		var primary: Dictionary = (params["suns"] as Array)[0]
		# Blend toward the star's tint but keep light near-white so albedo reads.
		sun.light_color = Color.WHITE.lerp(primary["color"] as Color, 0.35)
		# Point the scene light along the primary sun so shadows agree with the
		# sky. LOCAL transform on purpose: the Sun is a direct child of the
		# planet root (local == global), and global_transform is unreadable in
		# headless -s harnesses before the first tree tick.
		var d: Vector3 = (primary["dir"] as Vector3).normalized()
		sun.transform = Transform3D(Basis.looking_at(-d), sun.position)
	return params


static func build_environment(params: Dictionary) -> Environment:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("top_color", params["top"])
	mat.set_shader_parameter("horizon_color", params["horizon"])
	mat.set_shader_parameter("ground_color", params["ground"])
	mat.set_shader_parameter("star_density", params["star_density"])
	mat.set_shader_parameter("star_seed", params["star_seed"])

	var suns: Array = params["suns"]
	var sun_dirs: PackedVector3Array = PackedVector3Array()
	var sun_colors: PackedVector3Array = PackedVector3Array()
	var sun_sizes: PackedFloat32Array = PackedFloat32Array()
	for i in MAX_SUNS:
		var row: Dictionary = suns[i] if i < suns.size() else {"dir": Vector3.UP, "color": Color.BLACK, "size": 0.0}
		sun_dirs.append(row["dir"])
		sun_colors.append(_v3(row["color"]))
		sun_sizes.append(float(row["size"]))
	mat.set_shader_parameter("sun_count", suns.size())
	mat.set_shader_parameter("sun_dirs", sun_dirs)
	mat.set_shader_parameter("sun_colors", sun_colors)
	mat.set_shader_parameter("sun_sizes", sun_sizes)

	var moons: Array = params["moons"]
	var moon_dirs: PackedVector3Array = PackedVector3Array()
	var moon_colors: PackedVector3Array = PackedVector3Array()
	var moon_sizes: PackedFloat32Array = PackedFloat32Array()
	var moon_phase_band: PackedVector3Array = PackedVector3Array()
	for i in MAX_MOONS:
		var row: Dictionary = moons[i] if i < moons.size() else {"dir": Vector3.UP, "color": Color.BLACK, "size": 0.0, "phase": Vector2.RIGHT, "band": 0.0}
		moon_dirs.append(row["dir"])
		moon_colors.append(_v3(row["color"]))
		moon_sizes.append(float(row["size"]))
		var ph: Vector2 = row["phase"]
		moon_phase_band.append(Vector3(ph.x, ph.y, float(row["band"])))
	mat.set_shader_parameter("moon_count", moons.size())
	mat.set_shader_parameter("moon_dirs", moon_dirs)
	mat.set_shader_parameter("moon_colors", moon_colors)
	mat.set_shader_parameter("moon_sizes", moon_sizes)
	mat.set_shader_parameter("moon_phase_band", moon_phase_band)

	mat.set_shader_parameter("ring_amount", params["ring_amount"])
	mat.set_shader_parameter("ring_normal", params["ring_normal"])
	mat.set_shader_parameter("ring_color", _v3(params["ring_color"]))
	mat.set_shader_parameter("aurora_amount", params["aurora_amount"])
	mat.set_shader_parameter("aurora_color", _v3(params["aurora_color"]))

	var sky: Sky = Sky.new()
	sky.sky_material = mat
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	return env


# --- helpers -------------------------------------------------------------------

static func _dir(azimuth: float, elevation: float) -> Vector3:
	return Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		cos(elevation) * cos(azimuth)
	).normalized()


static func _col(rgb: Array) -> Color:
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
