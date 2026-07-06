extends SceneTree

# Smoke test for the misc SGU enhancements (issues #68, #30, #33, #37).
#
# Verifies the four new scripts load, expose their expected API, and the logic
# holds for the acceptance criteria in each issue:
#
#   #68 GateTravel — persistent-open lifecycle (open across repeat crossings,
#      closes ONLY on scrubber_repaired), dialing interface (can_dial /
#      available_destinations), destination registry.
#   #30 ancient_pbr_shader.gdshader — parses as a spatial Shader, exposes the
#      PBR uniforms (albedo_tint, metallic, roughness_base, panel_scale, etc.).
#   #33 FootfallSounds — registers the new surfaces (grass, stone, ship_hull)
#      on top of the FootstepLibrary set, resolves surfaces by context, and
#      reports per-surface gain.
#   #37 CrateStyles — registers all four styles (military, supply, ancient,
#      damaged), each with the required visual parameters, and the material
#      builders return StandardMaterial3D with the style's colors.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/misc_enhancements.gd

const GateTravel: Script = preload("res://scripts/gate_travel.gd")
const FootfallSounds: Script = preload("res://scripts/footfall_sounds.gd")
const CrateStyles: Script = preload("res://scripts/crate_styles.gd")
const SHADER_PATH: String = "res://scripts/ancient_pbr_shader.gdshader"

# Uniforms the ancient_pbr shader must expose for a PBR hero-prop material.
const EXPECTED_SHADER_UNIFORMS: Array[String] = [
	"albedo_tint", "metallic", "roughness_base", "panel_scale", "seam_width",
	"seam_depth", "wear_amount", "detail_scale", "detail_normal", "detail_rough",
	"detail_normal_strength", "triplanar_sharpness", "rivet_amount",
	"rivet_radius", "panel_variation", "emission_color", "emission_energy",
	"seam_emission",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== misc enhancements smoke test (#68, #30, #33, #37) ===")
	_test_gate_travel()
	_test_ancient_pbr_shader()
	_test_footfall_sounds()
	_test_crate_styles()
	_report()


# ── #68 GateTravel ────────────────────────────────────────────────────────────
func _test_gate_travel() -> void:
	print("\n--- #68 GateTravel ---")

	# Destination registry.
	_expect(GateTravel.DESTINATIONS.has(GateTravel.DEST_LIME_PLANET),
		"lime_planet is a registered destination")
	var dest: Dictionary = GateTravel.DESTINATIONS[GateTravel.DEST_LIME_PLANET]
	_expect(String(dest.get("target_scene", "")) != "",
		"lime_planet has a target_scene")
	_expect(String(dest.get("target_spawn", "")) != "",
		"lime_planet has a target_spawn")
	_expect(String(dest.get("quest_step", "")) != "",
		"lime_planet has a quest_step")
	_expect(String(dest.get("label", "")) == "Lime Planet",
		"lime_planet label is 'Lime Planet'")

	# destination_label helper.
	_expect(GateTravel.destination_label(GateTravel.DEST_LIME_PLANET) == "Lime Planet",
		"destination_label returns 'Lime Planet'")
	_expect(GateTravel.destination_label("nonexistent") == "",
		"destination_label returns '' for unknown id")

	# Build a stub GameState to exercise the lifecycle without the real autoload.
	var gs: Node = _stub_game_state()
	root.add_child(gs)

	# Gate is closed when nothing is dialed.
	_expect(GateTravel.is_gate_open(gs) == false,
		"gate closed when nothing is dialed")

	# Dial the lime planet → gate opens.
	gs.set("lime_planet_dialed", true)
	_expect(GateTravel.is_gate_open(gs) == true,
		"gate open after dialing lime planet")

	# A return crossing does NOT close the gate (the persistent-open rule).
	gs.set("returned_from_lime_planet", true)
	_expect(GateTravel.is_gate_open(gs) == true,
		"gate STAYS open after a return crossing (persistent-open lifecycle)")

	# Repeat crossings keep the gate open.
	for i in 4:
		_expect(GateTravel.is_gate_open(gs) == true,
			"gate open on repeat crossing #%d" % (i + 1))

	# The terminal condition closes the gate.
	gs.set("scrubber_repaired", true)
	_expect(GateTravel.is_gate_open(gs) == false,
		"gate closes ONLY on scrubber_repaired (terminal condition)")

	# can_dial window.
	gs.call("reset")
	gs.set("quest_step", "QUEST_MINE_LIME")
	_expect(GateTravel.can_dial(gs, GateTravel.DEST_LIME_PLANET) == true,
		"can_dial during MINE_LIME")
	gs.set("quest_step", "QUEST_RETURN_DESTINY")
	_expect(GateTravel.can_dial(gs, GateTravel.DEST_LIME_PLANET) == true,
		"can_dial during RETURN_DESTINY (re-travel window)")
	gs.set("quest_step", "QUEST_REPAIR_SCRUBBER")
	_expect(GateTravel.can_dial(gs, GateTravel.DEST_LIME_PLANET) == true,
		"can_dial during REPAIR_SCRUBBER (open window)")
	gs.set("scrubber_repaired", true)
	_expect(GateTravel.can_dial(gs, GateTravel.DEST_LIME_PLANET) == false,
		"cannot dial once the gate has closed (scrubber repaired)")
	_expect(GateTravel.can_dial(gs, "nonexistent") == false,
		"cannot dial an unknown destination")

	# is_dial_open: already-open gate reports open without re-dialing.
	gs.call("reset")
	gs.set("lime_planet_dialed", true)
	_expect(GateTravel.is_dial_open(gs, GateTravel.DEST_LIME_PLANET) == true,
		"is_dial_open true for an already-open gate")
	_expect(GateTravel.is_dial_open(gs, "nonexistent") == false,
		"is_dial_open false for unknown destination")

	# available_destinations lists the dialable destinations.
	gs.call("reset")
	gs.set("quest_step", "QUEST_MINE_LIME")
	var avail: Array[String] = GateTravel.available_destinations(gs)
	_expect(avail.has(GateTravel.DEST_LIME_PLANET),
		"available_destinations includes lime_planet during MINE_LIME")
	gs.set("scrubber_repaired", true)
	avail = GateTravel.available_destinations(gs)
	_expect(not avail.has(GateTravel.DEST_LIME_PLANET),
		"available_destinations excludes lime_planet once closed")

	# Crossing counter (telemetry) round-trip.
	gs.call("reset")
	_expect(GateTravel.crossing_count(gs, GateTravel.DEST_LIME_PLANET) == 0,
		"crossing_count starts at 0")
	GateTravel.increment_crossing_count(gs, GateTravel.DEST_LIME_PLANET)
	_expect(GateTravel.crossing_count(gs, GateTravel.DEST_LIME_PLANET) == 1,
		"crossing_count increments to 1")
	GateTravel.increment_crossing_count(gs, GateTravel.DEST_LIME_PLANET)
	_expect(GateTravel.crossing_count(gs, GateTravel.DEST_LIME_PLANET) == 2,
		"crossing_count increments to 2")

	gs.free()


# ── #30 ancient_pbr_shader.gdshader ────────────────────────────────────────────
func _test_ancient_pbr_shader() -> void:
	print("\n--- #30 ancient_pbr_shader.gdshader ---")
	var sh: Resource = load(SHADER_PATH)
	_expect(sh is Shader, "ancient_pbr_shader.gdshader loads as a Shader")
	if not (sh is Shader):
		return
	var shader: Shader = sh as Shader
	_expect(shader.code.length() > 0, "shader has source code")
	_expect(shader.get_mode() == Shader.MODE_SPATIAL, "shader is a spatial shader")
	# Verify the PBR uniform surface.
	var names: Dictionary = {}
	for u in shader.get_shader_uniform_list():
		names[String(u.get("name", ""))] = true
	for want in EXPECTED_SHADER_UNIFORMS:
		_expect(names.has(want), "shader exposes uniform '%s'" % want)


# ── #33 FootfallSounds ───────────────────────────────────────────────────────
func _test_footfall_sounds() -> void:
	print("\n--- #33 FootfallSounds ---")
	var fs: Object = FootfallSounds.new()

	# New surfaces (issue explicit list: metal deck, dirt, grass, stone, ship hull).
	for id in ["metal", "dirt", "grass", "stone", "ship_hull"]:
		_expect(fs.has_surface(id), "surface '%s' is registered" % id)

	# metal + dirt are inherited from FootstepLibrary; grass/stone/ship_hull are new.
	_expect(not FootfallSounds.HULL_SURFACES.is_empty(),
		"HULL_SURFACES seeds the new surface set")
	_expect(FootfallSounds.HULL_SURFACES.has("grass"),
		"grass is a HULL_SURFACES entry")
	_expect(FootfallSounds.HULL_SURFACES.has("stone"),
		"stone is a HULL_SURFACES entry")
	_expect(FootfallSounds.HULL_SURFACES.has("ship_hull"),
		"ship_hull is a HULL_SURFACES entry")

	# paths_for returns a non-empty array for each surface.
	for id in fs.all_surface_ids():
		var p: Array = fs.paths_for(id)
		_expect(p.size() > 0, "surface '%s' has at least one sample path" % id)

	# Unknown surface falls back to the default (metal).
	var unk: Array = fs.paths_for("nonexistent_surface")
	_expect(unk.size() > 0, "unknown surface falls back to a non-empty default list")

	# Per-surface gain: soft ground quieter than metal; hull louder.
	var metal_gain: float = fs.gain_db("metal")
	_expect(fs.gain_db("grass") < metal_gain, "grass quieter than metal")
	_expect(fs.gain_db("ship_hull") > metal_gain, "ship_hull louder than metal")

	# Context resolution.
	_expect(fs.resolve_surface({}) == "metal", "empty context → metal (ship)")
	_expect(fs.resolve_surface({"location": "ship"}) == "metal",
		"location=ship → metal")
	_expect(fs.resolve_surface({"location": "exterior_hull"}) == "ship_hull",
		"location=exterior_hull → ship_hull")
	_expect(fs.resolve_surface({"biome": "desert"}) == "desert",
		"biome=desert → desert (FootstepLibrary fallback)")
	_expect(fs.resolve_surface({"biome": "temperate"}) == "grass",
		"biome=temperate → grass (richer than bare dirt)")
	# Explicit surface wins over biome.
	_expect(fs.resolve_surface({"biome": "desert", "footstep_surface": "stone"}) == "stone",
		"explicit footstep_surface wins over biome")

	# Runtime registration.
	fs.register_surface("custom_biome", ["res://sounds/footstep_custom_00.ogg"], -2.0)
	_expect(fs.has_surface("custom_biome"), "register_surface adds a new surface")
	_expect(fs.gain_db("custom_biome") == -2.0, "registered surface has the given gain")

	fs.free()


# ── #37 CrateStyles ──────────────────────────────────────────────────────────
func _test_crate_styles() -> void:
	print("\n--- #37 CrateStyles ---")

	# All four styles registered.
	for id in [CrateStyles.STYLE_MILITARY, CrateStyles.STYLE_SUPPLY,
			CrateStyles.STYLE_ANCIENT, CrateStyles.STYLE_DAMAGED]:
		_expect(CrateStyles.has_style(id), "style '%s' is registered" % id)

	# all_style_ids returns exactly the four.
	var ids: Array[String] = CrateStyles.all_style_ids()
	_expect(ids.size() == 4, "four styles registered (got %d)" % ids.size())
	for id in [CrateStyles.STYLE_MILITARY, CrateStyles.STYLE_SUPPLY,
			CrateStyles.STYLE_ANCIENT, CrateStyles.STYLE_DAMAGED]:
		_expect(ids.has(id), "all_style_ids includes '%s'" % id)

	# Each style carries the required visual parameters.
	for id in ids:
		var s: Dictionary = CrateStyles.style_for(id)
		_expect(s.has("body_color"), "style '%s' has body_color" % id)
		_expect(s.has("panel_color"), "style '%s' has panel_color" % id)
		_expect(s.has("bracket_color"), "style '%s' has bracket_color" % id)
		_expect(s.has("interior_color"), "style '%s' has interior_color" % id)
		_expect(s.has("accent_color"), "style '%s' has accent_color" % id)
		_expect(s.has("accent_energy"), "style '%s' has accent_energy" % id)
		_expect(s.has("metallic"), "style '%s' has metallic" % id)
		_expect(s.has("roughness"), "style '%s' has roughness" % id)
		_expect(s.has("has_glow"), "style '%s' has has_glow" % id)
		_expect(s.has("lid_hinge"), "style '%s' has lid_hinge" % id)
		_expect(s.has("bracket_t"), "style '%s' has bracket_t" % id)
		_expect(s.has("damaged"), "style '%s' has damaged" % id)

	# Ancient style glows; military + supply do not.
	_expect(bool(CrateStyles.style_for(CrateStyles.STYLE_ANCIENT).get("has_glow")),
		"ancient style has_glow = true")
	_expect(not bool(CrateStyles.style_for(CrateStyles.STYLE_MILITARY).get("has_glow")),
		"military style has_glow = false")
	_expect(not bool(CrateStyles.style_for(CrateStyles.STYLE_SUPPLY).get("has_glow")),
		"supply style has_glow = false")

	# Damaged style flags damage.
	_expect(CrateStyles.is_damaged(CrateStyles.STYLE_DAMAGED),
		"damaged style is_damaged = true")
	_expect(not CrateStyles.is_damaged(CrateStyles.STYLE_ANCIENT),
		"ancient style is_damaged = false")

	# Lid hinge: ancient + damaged hinge; military + supply don't.
	_expect(CrateStyles.has_hinged_lid(CrateStyles.STYLE_ANCIENT),
		"ancient has hinged lid")
	_expect(CrateStyles.has_hinged_lid(CrateStyles.STYLE_DAMAGED),
		"damaged has hinged lid")
	_expect(not CrateStyles.has_hinged_lid(CrateStyles.STYLE_MILITARY),
		"military has no hinged lid")
	_expect(not CrateStyles.has_hinged_lid(CrateStyles.STYLE_SUPPLY),
		"supply has no hinged lid")

	# Material builders return StandardMaterial3D with the style's colors.
	var body: StandardMaterial3D = CrateStyles.body_material(CrateStyles.STYLE_MILITARY)
	_expect(body is StandardMaterial3D, "body_material returns a StandardMaterial3D")
	_expect(body.albedo_color.is_equal_approx(CrateStyles.style_for(CrateStyles.STYLE_MILITARY)["body_color"]),
		"military body_material albedo matches the style body_color")

	var accent: StandardMaterial3D = CrateStyles.accent_material(CrateStyles.STYLE_ANCIENT)
	_expect(accent.emission_enabled == true,
		"ancient accent_material is emissive (has_glow)")
	var military_accent: StandardMaterial3D = CrateStyles.accent_material(CrateStyles.STYLE_MILITARY)
	_expect(military_accent.emission_enabled == false,
		"military accent_material is NOT emissive (no glow)")

	# Unknown style falls back to ancient (the canonical look).
	var unk: Dictionary = CrateStyles.style_for("nonexistent")
	_expect(unk.get("has_glow") == true,
		"unknown style falls back to ancient (has_glow)")

	# default_style_id is ancient.
	_expect(CrateStyles.default_style_id() == CrateStyles.STYLE_ANCIENT,
		"default_style_id is ancient")


# ── helpers ──────────────────────────────────────────────────────────────────

# A stub GameState that exposes the quest_step / flags GateTravel queries,
# plus the QUEST_* ordering constants _step_at_or_after walks. We do NOT use
# the real GameState autoload here — this test must run without depending on
# the autoload's full init, and the stub lets us assert the lifecycle in
# isolation.
func _stub_game_state() -> Node:
	var n: Node = Node.new()
	n.name = "StubGameState"
	n.set_script(load("res://tests/smoke/_stub_game_state.gd"))
	return n


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)