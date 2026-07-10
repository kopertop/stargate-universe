extends SceneTree

# Smoke test for the procedural alien-sky system (scripts/planet_sky.gd):
#   * data/skies.json covers every biome in data/biomes.json (or falls back
#     to the default block) with sane ranges,
#   * roll(spec) is DETERMINISTIC — the same planet spec always wears the
#     same heavens (reload-stable),
#   * rolls respect the biome tuning: desert can crowd the sky with suns,
#     winter/alien_tech crowd it with moons, harsh biomes roll auroras,
#   * every roll stays inside the shader's uniform limits (3 suns, 4 moons),
#   * build_environment/apply produce a live sky Environment and re-aim the
#     scene sun light at the primary star.
#
# Run with:
#   godot --headless --quit-after 300 -s res://tests/smoke/planet_sky.gd

const SKY_SCRIPT: String = "res://scripts/planet_sky.gd"
const BIOMES_PATH: String = "res://data/biomes.json"

var _failures: Array[String] = []
var _passes: int = 0
var _sky: Script = null


func _initialize() -> void:
	print("=== planet-sky smoke test ===")
	_sky = load(SKY_SCRIPT)
	if _sky == null:
		_fail("load", "cannot load %s" % SKY_SCRIPT)
		_report()
		return
	_check_config_coverage()
	_check_determinism()
	_check_roll_bounds()
	_check_biome_tuning()
	_check_environment_build()
	_check_apply_to_scene()
	_report()


func _spec(biome: String, seed_val: int) -> Dictionary:
	return {"biome": biome, "seed": seed_val, "name": "Test World"}


func _biome_ids() -> Array:
	var f: FileAccess = FileAccess.open(BIOMES_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return (parsed as Dictionary).keys() if parsed is Dictionary else []


# ---- 1. config coverage --------------------------------------------------------

func _check_config_coverage() -> void:
	var biomes: Array = _biome_ids()
	_expect(not biomes.is_empty(), "biomes.json lists biomes")
	for b in biomes:
		var cfg: Dictionary = _sky.config_for(String(b))
		_expect(cfg.has("palettes") and not (cfg["palettes"] as Array).is_empty(),
			"%s: sky palettes configured" % b)
		var suns: Array = cfg.get("suns", []) as Array
		_expect(suns.size() == 2 and int(suns[0]) >= 1 and int(suns[1]) <= 3,
			"%s: sun range sane" % b)
		var moons: Array = cfg.get("moons", []) as Array
		_expect(moons.size() == 2 and int(moons[0]) >= 0 and int(moons[1]) <= 4,
			"%s: moon range sane" % b)
	var fallback: Dictionary = _sky.config_for("no_such_biome_xyz")
	_expect(fallback.has("palettes"), "unknown biome falls back to the default block")


# ---- 2. determinism --------------------------------------------------------------

func _check_determinism() -> void:
	var a: Dictionary = _sky.roll(_spec("desert", 104729))
	var b: Dictionary = _sky.roll(_spec("desert", 104729))
	_expect(str(a) == str(b), "same spec rolls the identical sky (reload-stable)")
	var c: Dictionary = _sky.roll(_spec("desert", 999331))
	_expect(str(a) != str(c), "a different seed rolls a different sky")


# ---- 3. bounds --------------------------------------------------------------------

func _check_roll_bounds() -> void:
	var all_ok: bool = true
	for b in _biome_ids():
		for s in [7, 1234, 55555, 987654, 31337]:
			var p: Dictionary = _sky.roll(_spec(String(b), int(s)))
			var suns: Array = p["suns"]
			var moons: Array = p["moons"]
			if suns.size() < 1 or suns.size() > 3 or moons.size() > 4:
				all_ok = false
				_fail("bounds", "%s seed %s: %d suns / %d moons" % [b, s, suns.size(), moons.size()])
			# Primary star must sit above the horizon so the world is lit.
			if (suns[0]["dir"] as Vector3).y <= 0.0:
				all_ok = false
				_fail("bounds", "%s seed %s: primary sun below horizon" % [b, s])
	_expect(all_ok, "all biomes × seeds stay inside shader limits, primary sun up")


# ---- 4. biome tuning ---------------------------------------------------------------

func _check_biome_tuning() -> void:
	# Sample many seeds per biome and compare the AVERAGES the config promises.
	var desert_suns: int = 0
	var winter_moons: int = 0
	var desert_moons: int = 0
	var winter_multi: int = 0
	var harsh_auroras: int = 0
	const N: int = 120
	for i in N:
		var s: int = 1000 + i * 37
		desert_suns += ((_sky.roll(_spec("desert", s)))["suns"] as Array).size()
		desert_moons += ((_sky.roll(_spec("desert", s)))["moons"] as Array).size()
		var wm: int = ((_sky.roll(_spec("winter", s)))["moons"] as Array).size()
		winter_moons += wm
		if wm >= 2:
			winter_multi += 1
		if float((_sky.roll(_spec("toxic", s)))["aurora_amount"]) > 0.0 \
				or float((_sky.roll(_spec("alien_tech", s)))["aurora_amount"]) > 0.0:
			harsh_auroras += 1
	_expect(desert_suns > N, "desert skies roll extra suns (avg > 1 per world)")
	_expect(winter_moons > desert_moons, "winter skies carry more moons than desert")
	_expect(winter_multi > N / 2, "most winter skies show 2+ moons")
	_expect(harsh_auroras > N / 2, "harsh biomes (toxic/alien_tech) roll auroras often")
	# Desert never rolls an aurora per config.
	var desert_aurora: bool = false
	for i in 40:
		if float((_sky.roll(_spec("desert", 77 + i)))["aurora_amount"]) > 0.0:
			desert_aurora = true
	_expect(not desert_aurora, "desert config keeps auroras off")


# ---- 5. environment build -----------------------------------------------------------

func _check_environment_build() -> void:
	var params: Dictionary = _sky.roll(_spec("alien_tech", 424242))
	var env: Environment = _sky.build_environment(params)
	_expect(env != null and env.background_mode == Environment.BG_SKY, "environment renders a sky")
	_expect(env.sky != null and env.sky.sky_material is ShaderMaterial, "sky uses the alien-sky shader material")
	var mat: ShaderMaterial = env.sky.sky_material
	_expect(mat.shader != null and mat.shader.resource_path.ends_with("alien_sky.gdshader"),
		"shader is shaders/alien_sky.gdshader")
	_expect(int(mat.get_shader_parameter("sun_count")) == (params["suns"] as Array).size(),
		"sun_count uniform matches the roll")
	_expect(int(mat.get_shader_parameter("moon_count")) == (params["moons"] as Array).size(),
		"moon_count uniform matches the roll")
	_expect(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY,
		"ambient light sourced from the sky")


# ---- 6. apply to a planet-shaped scene ------------------------------------------------

func _check_apply_to_scene() -> void:
	var fake_planet: Node3D = Node3D.new()
	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.name = "Environment"
	fake_planet.add_child(env_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	fake_planet.add_child(sun)
	root.add_child(fake_planet)

	var spec: Dictionary = _spec("desert", 104729)
	var params: Dictionary = _sky.apply(fake_planet, spec)
	_expect(env_node.environment != null and env_node.environment.background_mode == Environment.BG_SKY,
		"apply installs the sky environment on the scene")
	var primary: Dictionary = (params["suns"] as Array)[0]
	_expect(sun.light_color != Color.WHITE or (primary["color"] as Color).is_equal_approx(Color.WHITE),
		"apply tints the scene sun toward the primary star")
	var light_forward: Vector3 = -sun.transform.basis.z
	_expect(light_forward.dot(-(primary["dir"] as Vector3)) > 0.9,
		"scene sun light aims along the primary star direction")
	fake_planet.queue_free()


# ---- harness -------------------------------------------------------------------

func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _fail(context: String, message: String) -> void:
	_failures.append("%s: %s" % [context, message])
	print("  FAIL  %s: %s" % [context, message])


func _report() -> void:
	print("")
	print("=== summary ===")
	print("passes: %d" % _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("failures: %d" % _failures.size())
		for f in _failures:
			print("  - %s" % f)
		print("RESULT: FAIL")
		quit(1)
