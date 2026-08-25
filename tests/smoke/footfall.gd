extends SceneTree

# Smoke test for per-environment footfall sounds (issue #33).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/footfall.gd
#
# Asserts:
#   • FootstepLibrary registers every surface listed in the issue
#     (metal / dirt / desert / water / swamp).
#   • Every surface's sample files exist on disk AND load as AudioStreams.
#   • surface_for_spec resolution: empty spec (ship) → metal; explicit
#     footstep_surface wins; biome fallback maps for a spec that predates the
#     key; an unknown biome / surface degrades to the default (metal).
#   • Every biome in data/biomes.json carries a footstep_surface that is a
#     registered surface (the data is the canonical source; no biome ships
#     without one).
#
# Uses the FootstepLibrary class directly (static API, no autoload) plus a raw
# read of data/biomes.json so the test is independent of PlanetGenerator.

const LIB: Script = preload("res://scripts/footstep_library.gd")
const BIOMES_PATH: String = "res://data/biomes.json"
const REQUIRED_SURFACES: Array[String] = ["metal", "dirt", "desert", "water", "swamp"]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== footfall smoke test ===")

	_test_required_surfaces_registered()
	_test_every_surface_samples_load()
	_test_surface_resolution()
	_test_surface_gain()
	_test_every_biome_has_registered_surface()

	_report()


# Every surface named in the issue must be registered with a non-empty list.
func _test_required_surfaces_registered() -> void:
	for surface in REQUIRED_SURFACES:
		_expect(LIB.has_surface(surface), "surface '%s' is registered" % surface)
		var paths: Array = LIB.paths_for(surface)
		_expect(paths.size() > 0, "surface '%s' has at least one sample" % surface)


# Every sample path for every surface must exist and load as an AudioStream —
# this is the guard that catches a copied .ogg that never got its .import
# sidecar generated (Audio.play would silently fail otherwise).
func _test_every_surface_samples_load() -> void:
	for surface in (LIB.SURFACES as Dictionary).keys():
		var paths: Array = LIB.paths_for(surface)
		for path in paths:
			_expect(ResourceLoader.exists(path), "sample exists: %s" % path)
		var streams: Array = LIB.load_streams(surface)
		_expect(streams.size() == paths.size(),
			"all %d samples for '%s' load as AudioStreams (got %d)" % [paths.size(), surface, streams.size()])


# surface_for_spec covers ship default, explicit key, biome fallback, unknowns.
func _test_surface_resolution() -> void:
	# Arrange / Act / Assert — ship (no planet spec) is metal.
	_expect(LIB.surface_for_spec({}) == "metal", "empty spec (ship) → metal")
	_expect(LIB.surface_for_spec(null) == "metal", "null spec → metal")

	# Explicit footstep_surface wins over biome.
	_expect(LIB.surface_for_spec({"biome": "desert", "footstep_surface": "water"}) == "water",
		"explicit footstep_surface overrides biome")

	# Biome fallback for a spec that predates the footstep_surface key.
	_expect(LIB.surface_for_spec({"biome": "desert"}) == "desert", "biome desert → desert (fallback)")
	_expect(LIB.surface_for_spec({"biome": "toxic"}) == "swamp", "biome toxic → swamp (fallback)")
	_expect(LIB.surface_for_spec({"biome": "alien_tech"}) == "metal", "biome alien_tech → metal (fallback)")
	_expect(LIB.surface_for_spec({"biome": "jungle"}) == "dirt", "biome jungle → dirt (fallback)")

	# Unknown biome / unknown explicit surface both degrade to the default.
	_expect(LIB.surface_for_spec({"biome": "lava_world"}) == "metal", "unknown biome → metal default")
	_expect(LIB.surface_for_spec({"footstep_surface": "lava"}) == "metal", "unknown surface → metal default")


# Per-surface playback gain: metal (ship) is the 0 dB reference; soft ground is
# quieter (negative), with desert sand the softest. An unknown surface = 0 dB.
func _test_surface_gain() -> void:
	_expect(LIB.gain_db_for("metal") == 0.0, "metal gain is the 0 dB reference")
	_expect(LIB.gain_db_for("desert") < 0.0, "desert is quieter than metal")
	_expect(LIB.gain_db_for("water") < 0.0, "water is quieter than metal")
	_expect(LIB.gain_db_for("swamp") < 0.0, "swamp is quieter than metal")
	_expect(LIB.gain_db_for("dirt") < 0.0, "dirt is quieter than metal")
	_expect(LIB.gain_db_for("desert") <= LIB.gain_db_for("dirt"), "desert sand is the softest surface")
	_expect(LIB.gain_db_for("lava_world") == 0.0, "unknown surface → 0 dB (base volume)")


# data/biomes.json is the canonical surface source; every biome must declare a
# footstep_surface that the library actually knows about.
func _test_every_biome_has_registered_surface() -> void:
	var f: FileAccess = FileAccess.open(BIOMES_PATH, FileAccess.READ)
	_expect(f != null, "biomes.json opens")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_expect(parsed is Dictionary, "biomes.json parses to a Dictionary")
	if not (parsed is Dictionary):
		return
	var table: Dictionary = parsed
	for biome in table.keys():
		var block: Dictionary = table[biome]
		var surface: String = String(block.get("footstep_surface", ""))
		_expect(surface != "", "biome '%s' declares footstep_surface" % biome)
		_expect(LIB.has_surface(surface),
			"biome '%s' footstep_surface '%s' is a registered surface" % [biome, surface])


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("=== footfall: %d passed, %d failed ===" % [_passes, _failures.size()])
	if _failures.is_empty():
		quit(0)
	else:
		for f in _failures:
			print("  - %s" % f)
		quit(1)
