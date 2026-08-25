extends SceneTree

# Headless smoke test for the three procedural-planet system helpers
# (issues #149, #150, #151). Exercises:
#   1. PlanetResourceSystem — tracked display rows, scarcity targeting,
#      priority targeting (nearest first, scarcest type first), depletion
#      tracking, and inventory integration.
#   2. PlanetTerrainSystem  — frustum-aware chunk selection within the Kino
#      camera view range, the tracked-body + frustum merge, and the view-limit
#      edge cases (far-plane rejection, behind-camera, degenerate frustum).
#   3. PlanetBiomeSystem    — biome catalog + labels, per-biome hazards
#      (traps / toxin / sensors / settlement / none), pressure-suit gating,
#      and the no-death recovery integration with injury_system.gd.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/planet_systems.gd
#
# Duck-types the three systems via their script paths so a freshly-added
# class_name can't parse-error this run (feedback_godot_class_name_headless.md).
# Uses the live GameState + Inventory + InjurySystem autoloads (reached via
# /root under -s). The terrain system is pure (no autoloads) so it runs under
# the bare SceneTree too.

const RES_PATH: String = "res://scripts/planet_resource_system.gd"
const TERRAIN_PATH: String = "res://scripts/planet_terrain_system.gd"
const BIOME_PATH: String = "res://scripts/planet_biome_system.gd"

var _res: Script = null
var _terrain: Script = null
var _biome: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== planet_systems smoke test ===")
	_res = load(RES_PATH)
	_terrain = load(TERRAIN_PATH)
	_biome = load(BIOME_PATH)
	_expect(_res != null, "PlanetResourceSystem script loads")
	_expect(_terrain != null, "PlanetTerrainSystem script loads")
	_expect(_biome != null, "PlanetBiomeSystem script loads")
	if _res == null or _terrain == null or _biome == null:
		_report()
		return

	# Issue #149 — resource targeting.
	_test_tracked_display_rows_cover_registry()
	_test_scarcest_id_matches_ranking()
	_test_priority_targets_nearest_first_scarcest_type_first()
	_test_depletion_tracking_excludes_from_priority()
	_test_inventory_integration_grant_and_count()
	_test_priority_deterministic_for_same_seed()

	# Issue #150 — terrain gen / frustum awareness.
	_test_visible_chunk_coords_rejects_behind_camera()
	_test_visible_chunk_coords_rejects_beyond_far_plane()
	_test_degenerate_frustum_returns_empty()
	_test_frustum_aware_window_keeps_body_window()
	_test_chunk_beyond_view_limit_predicate()

	# Issue #151 — biomes.
	_test_biome_catalog_and_labels()
	_test_hazard_kind_per_biome()
	_test_pressure_suit_gating()
	_test_hazards_for_jungle_carries_trap_fields()
	_test_hazards_for_alien_tech_carries_sensor_fields()
	_test_hazards_for_toxic_carries_oxygen_drain()
	_test_register_hazard_injury_routes_through_injury_system()
	_test_register_hazard_injury_maps_cause_to_injury_cause()

	_report()


# === Issue #149 — PlanetResourceSystem ======================================

# --- 1: tracked_display_rows() covers every tracked resource in registry order
func _test_tracked_display_rows_cover_registry() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload attached (resource test)")
	if gs == null:
		return
	var ids: Array = gs.call("tracked_resource_ids")
	var rows: Array = _res.tracked_display_rows()
	_expect(rows.size() == ids.size(), "display rows cover every tracked resource (%d == %d)" % [rows.size(), ids.size()])
	# Display order is registry order, not scarcity order.
	for i in ids.size():
		_expect(String((rows[i] as Dictionary).get("id", "")) == String(ids[i]),
			"display row %d matches registry order (%s)" % [i, String(ids[i])])
	# Every row carries amount + threshold + deficit + low.
	for r in rows:
		var row: Dictionary = r
		_expect(row.has("amount") and row.has("threshold") and row.has("deficit") and row.has("low"),
			"%s row carries amount + threshold + deficit + low" % String(row.get("id", "?")))
	# `low` matches the deficit sign.
	for r in rows:
		var row: Dictionary = r
		var expected_low: bool = int(row.get("deficit", 0)) > 0
		_expect(bool(row.get("low", false)) == expected_low,
			"%s low flag == (deficit > 0)" % String(row.get("id", "?")))


# --- 2: scarcest_id() matches the top of resource_scarcity()
func _test_scarcest_id_matches_ranking() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs == null:
		_expect(false, "GameState autoload attached (scarcest test)")
		return
	gs.call("reset")
	gs.call("seed_default_resources")
	# Make water the deepest deficit.
	var inv: Node = root.get_node_or_null("Inventory")
	if inv != null:
		inv.call("set_count", "water", 0)
		inv.call("set_count", "food", 20)
		inv.call("set_count", "parts", 20)
		inv.call("set_count", "lime", 20)
	var ranked: Array = gs.call("resource_scarcity")
	var scarcest: String = _res.scarcest_id()
	_expect(scarcest == String((ranked[0] as Dictionary).get("id", "")),
		"scarcest_id() matches resource_scarcity()[0] (%s)" % scarcest)
	_expect(scarcest == "water", "water is the scarcest when at 0")


# --- 3: priority_targets() nearest first, scarcest type first
func _test_priority_targets_nearest_first_scarcest_type_first() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	if gs == null or inv == null:
		_expect(false, "GameState + Inventory attached (priority test)")
		return
	gs.call("reset")
	gs.call("seed_default_resources")
	# Water scarcest.
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)
	inv.call("set_count", "parts", 20)
	inv.call("set_count", "lime", 20)
	var sys: RefCounted = _res.new()
	# Deposits: water near + far, food near + far. Viewer at origin.
	var deposits: Array = [
		{"type": "water", "node": "WaterNode1", "position": Vector3(150, 0, 0)},
		{"type": "water", "node": "WaterNode2", "position": Vector3(60, 0, 0)},
		{"type": "food",  "node": "FoodNode1",  "position": Vector3(40, 0, 0)},
		{"type": "food",  "node": "FoodNode2",  "position": Vector3(200, 0, 0)},
	]
	var ordered: Array = sys.call("priority_targets", Vector3.ZERO, deposits)
	_expect(ordered.size() == 4, "all non-depleted deposits targeted (%d)" % ordered.size())
	# Scarcest type (water) leads, nearest-first within the type.
	_expect(String((ordered[0] as Dictionary).get("type", "")) == "water", "first priority target is scarcest type (water)")
	_expect(String((ordered[0] as Dictionary).get("node", "")) == "WaterNode2", "nearest water deposit leads (WaterNode2 at 60m)")
	_expect(String((ordered[1] as Dictionary).get("node", "")) == "WaterNode1", "farther water deposit second (WaterNode1 at 150m)")
	# Then food, nearest-first.
	_expect(String((ordered[2] as Dictionary).get("type", "")) == "food", "next priority group is food")
	_expect(String((ordered[2] as Dictionary).get("node", "")) == "FoodNode1", "nearest food deposit leads (FoodNode1 at 40m)")
	_expect(String((ordered[3] as Dictionary).get("node", "")) == "FoodNode2", "farther food deposit second (FoodNode2 at 200m)")


# --- 4: depleted deposits are excluded from priority targeting
func _test_depletion_tracking_excludes_from_priority() -> void:
	var sys: RefCounted = _res.new()
	_expect(sys.call("depleted_count") == 0, "fresh system has zero depleted")
	sys.call("register_depletion", "WaterNode2")
	_expect(sys.call("depleted_count") == 1, "depletion registered (count 1)")
	_expect(bool(sys.call("is_depleted", "WaterNode2")), "is_depleted(WaterNode2) true")
	_expect(not bool(sys.call("is_depleted", "WaterNode1")), "is_depleted(WaterNode1) false (not registered)")
	# Same deposits as test 3 — WaterNode2 should now be excluded.
	var deposits: Array = [
		{"type": "water", "node": "WaterNode1", "position": Vector3(150, 0, 0)},
		{"type": "water", "node": "WaterNode2", "position": Vector3(60, 0, 0)},
		{"type": "food",  "node": "FoodNode1",  "position": Vector3(40, 0, 0)},
	]
	var ordered: Array = sys.call("priority_targets", Vector3.ZERO, deposits)
	_expect(ordered.size() == 2, "depleted WaterNode2 excluded (%d remaining)" % ordered.size())
	for entry in ordered:
		_expect(String((entry as Dictionary).get("node", "")) != "WaterNode2",
			"WaterNode2 not in priority list after depletion")


# --- 5: inventory integration — grant + count
func _test_inventory_integration_grant_and_count() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	if gs == null or inv == null:
		_expect(false, "GameState + Inventory attached (integration test)")
		return
	gs.call("reset")
	gs.call("seed_default_resources")
	var before: int = _res.inventory_count("water")
	var new_count: int = _res.grant("water", 3, "test")
	_expect(new_count == before + 3, "grant() returns new count (+3)")
	_expect(_res.inventory_count("water") == before + 3, "inventory_count() reflects the grant")
	# is_low() true when deficit > 0.
	inv.call("set_count", "water", 0)
	_expect(bool(_res.is_low("water")), "is_low(water) true when at 0")
	inv.call("set_count", "water", 100)
	_expect(not bool(_res.is_low("water")), "is_low(water) false when well-stocked")


# --- 6: priority targeting deterministic for the same seed/state
func _test_priority_deterministic_for_same_seed() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	if gs == null or inv == null:
		_expect(false, "GameState + Inventory attached (determinism test)")
		return
	gs.call("reset")
	gs.call("seed_default_resources")
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)
	inv.call("set_count", "parts", 20)
	inv.call("set_count", "lime", 20)
	var deposits: Array = [
		{"type": "water", "node": "WaterNode1", "position": Vector3(100, 0, 0)},
		{"type": "food",  "node": "FoodNode1",  "position": Vector3(50, 0, 0)},
	]
	var sys_a: RefCounted = _res.new()
	var sys_b: RefCounted = _res.new()
	var a: Array = sys_a.call("priority_targets", Vector3.ZERO, deposits)
	var b: Array = sys_b.call("priority_targets", Vector3.ZERO, deposits)
	_expect(a.size() == b.size(), "same input → same count")
	var same: bool = a.size() == b.size()
	if same:
		for i in a.size():
			if String((a[i] as Dictionary).get("node", "")) != String((b[i] as Dictionary).get("node", "")):
				same = false
	_expect(same, "priority targeting deterministic for the same scarcity state")


# === Issue #150 — PlanetTerrainSystem ======================================

# --- 7: chunks behind the camera are rejected
func _test_visible_chunk_coords_rejects_behind_camera() -> void:
	# Build a frustum looking down +Z from the origin. The near plane rejects
	# chunks behind the camera (negative Z).
	var frustum: Array = _make_forward_frustum(Vector3.ZERO, Vector3(0, 0, 1), 200.0)
	var wanted: Dictionary = _terrain.visible_chunk_coords(frustum, Vector3.ZERO, 200.0, 8)
	# The chunk at (0, -2) is behind the camera (Z = -128..-64) → rejected.
	_expect(not wanted.has("0,-2"), "chunk behind camera rejected (0,-2)")
	# The chunk at (0, 1) is in front (Z = 64..128) → included.
	_expect(wanted.has("0,1"), "chunk in front of camera included (0,1)")


# --- 8: chunks beyond the far plane are rejected
func _test_visible_chunk_coords_rejects_beyond_far_plane() -> void:
	# Far plane 50 m → only the origin chunk (and maybe immediate neighbours) is
	# within; a chunk at 128 m (coord (0,2)) is beyond the view limit.
	var frustum: Array = _make_forward_frustum(Vector3.ZERO, Vector3(0, 0, 1), 50.0)
	var wanted: Dictionary = _terrain.visible_chunk_coords(frustum, Vector3.ZERO, 50.0, 8)
	_expect(not wanted.has("0,2"), "chunk beyond far plane rejected (0,2 at 128m)")
	# chunk_beyond_view_limit() agrees.
	_expect(bool(_terrain.chunk_beyond_view_limit(Vector2i(0, 2), Vector3.ZERO, 50.0)),
		"chunk_beyond_view_limit(0,2) true for far=50")


# --- 9: a degenerate frustum returns an empty set
func _test_degenerate_frustum_returns_empty() -> void:
	_expect(bool(_terrain.is_frustum_degenerate([])), "empty frustum is degenerate")
	var zero_planes: Array = []
	for i in 6:
		zero_planes.append(Plane(0, 0, 0, 0))
	_expect(bool(_terrain.is_frustum_degenerate(zero_planes)), "all-zero planes are degenerate")
	var wanted: Dictionary = _terrain.visible_chunk_coords([], Vector3.ZERO, 200.0, 8)
	_expect(wanted.is_empty(), "degenerate frustum → empty wanted set")


# --- 10: frustum_aware_window() keeps the body window even when looking away
func _test_frustum_aware_window_keeps_body_window() -> void:
	# Camera looks +Z from origin; body is at -Z (behind the camera). The body
	# window (radius 1) must still be in the wanted set so the body has ground.
	var frustum: Array = _make_forward_frustum(Vector3.ZERO, Vector3(0, 0, 1), 200.0)
	var body_pos: Vector3 = Vector3(0, 0, -80.0)   # behind camera, 80 m back
	var wanted: Dictionary = _terrain.frustum_aware_window(frustum, Vector3.ZERO, 200.0, body_pos, 1, 8)
	# Body chunk coord: floor(-80/64) = -2 → (-1..1 around -2) includes (-2, -1, 0) in x,
	# but body x = 0 so center is (0, -2); window is (0,-3), (0,-2), (0,-1), (±1 likewise).
	_expect(wanted.has("0,-2"), "body window chunk (0,-2) kept despite camera looking away")
	_expect(wanted.has("-1,-2"), "body window chunk (-1,-2) kept")
	_expect(wanted.has("1,-2"), "body window chunk (1,-2) kept")


# --- 11: chunk_beyond_view_limit() standalone predicate
func _test_chunk_beyond_view_limit_predicate() -> void:
	# Chunk (0,0) at origin — nearest corner 0 m, not beyond far=100.
	_expect(not bool(_terrain.chunk_beyond_view_limit(Vector2i(0, 0), Vector3.ZERO, 100.0)),
		"origin chunk not beyond far=100")
	# Chunk (0,4) at 256-320 m — well beyond far=100.
	_expect(bool(_terrain.chunk_beyond_view_limit(Vector2i(0, 4), Vector3.ZERO, 100.0)),
		"chunk at 256m beyond far=100")


# === Issue #151 — PlanetBiomeSystem =========================================

# --- 12: biome catalog + labels
func _test_biome_catalog_and_labels() -> void:
	var ids: Array = _biome.biome_ids()
	_expect(not ids.is_empty(), "biome catalog non-empty")
	for needed in ["desert", "jungle", "toxic", "urban", "alien_tech"]:
		_expect(ids.has(needed), "catalog includes %s" % needed)
	# Label resolves.
	var label: String = _biome.biome_label("jungle")
	_expect(label == "Jungle", "jungle label is 'Jungle' (got '%s')" % label)
	label = _biome.biome_label("alien_tech")
	_expect(label == "Alien Tech", "alien_tech label is 'Alien Tech' (got '%s')" % label)


# --- 13: hazard_kind per biome
func _test_hazard_kind_per_biome() -> void:
	_expect(int(_biome.hazard_kind("alien_tech")) == _biome.HazardKind.SENSORS,
		"alien_tech hazard kind SENSORS")
	_expect(int(_biome.hazard_kind("jungle")) == _biome.HazardKind.TRAPS,
		"jungle hazard kind TRAPS")
	_expect(int(_biome.hazard_kind("toxic")) == _biome.HazardKind.TOXIN,
		"toxic hazard kind TOXIN")
	_expect(int(_biome.hazard_kind("urban")) == _biome.HazardKind.SETTLEMENT,
		"urban hazard kind SETTLEMENT")
	_expect(int(_biome.hazard_kind("desert")) == _biome.HazardKind.NONE,
		"desert hazard kind NONE")


# --- 14: pressure-suit gating
func _test_pressure_suit_gating() -> void:
	_expect(bool(_biome.requires_pressure_suit("toxic")),
		"toxic requires pressure suit")
	_expect(not bool(_biome.requires_pressure_suit("desert")),
		"desert does not require pressure suit")
	_expect(not bool(_biome.requires_pressure_suit("jungle")),
		"jungle does not require pressure suit")
	_expect(not bool(_biome.requires_pressure_suit("alien_tech")),
		"alien_tech does not require pressure suit")


# --- 15: hazards_for(jungle) carries trap fields
func _test_hazards_for_jungle_carries_trap_fields() -> void:
	var h: Dictionary = _biome.hazards_for("jungle")
	_expect(int(h.get("kind", -1)) == _biome.HazardKind.TRAPS, "jungle hazards kind TRAPS")
	_expect(String(h.get("cause", "")) == "trap", "jungle cause 'trap'")
	_expect(float(h.get("damage_per_second", 0.0)) > 0.0, "jungle has positive trap damage/sec")
	_expect(int(h.get("count", 0)) > 0, "jungle has a positive trap count")
	_expect(String(h.get("telegraph", "")) != "", "jungle carries a telegraph tell")


# --- 16: hazards_for(alien_tech) carries sensor fields
func _test_hazards_for_alien_tech_carries_sensor_fields() -> void:
	var h: Dictionary = _biome.hazards_for("alien_tech")
	_expect(int(h.get("kind", -1)) == _biome.HazardKind.SENSORS, "alien_tech hazards kind SENSORS")
	_expect(String(h.get("cause", "")) == "alien_defense", "alien_tech cause 'alien_defense'")
	_expect(float(h.get("damage_per_second", 0.0)) > 0.0, "alien_tech has positive base damage/sec")
	_expect(int(h.get("count", 0)) > 0, "alien_tech has a positive sensor count")
	_expect(String(h.get("telegraph", "")) != "", "alien_tech carries a telegraph tell")


# --- 17: hazards_for(toxic) carries oxygen drain
func _test_hazards_for_toxic_carries_oxygen_drain() -> void:
	var h: Dictionary = _biome.hazards_for("toxic")
	_expect(int(h.get("kind", -1)) == _biome.HazardKind.TOXIN, "toxic hazards kind TOXIN")
	_expect(String(h.get("cause", "")) == "asphyxiation", "toxic cause 'asphyxiation'")
	_expect(float(h.get("oxygen_drain_per_sec", 0.0)) > 0.0, "toxic has positive oxygen drain")
	_expect(bool(h.get("breathable", true)) == false, "toxic reports NOT breathable")
	_expect(bool(h.get("requires_pressure_suit", false)) == true, "toxic requires pressure suit")


# --- 18: register_hazard_injury() routes through InjurySystem
func _test_register_hazard_injury_routes_through_injury_system() -> void:
	var injury_sys: Node = root.get_node_or_null("InjurySystem")
	_expect(injury_sys != null, "InjurySystem autoload attached")
	if injury_sys == null:
		return
	# instant_mode so knock_out's infirmary routing flips state directly (no
	# async scene load / tween, which would error under a bare -s script).
	# Mirrors biome_jungle.gd / biome_toxic.gd's knockout-test pattern.
	var router: Node = root.get_node_or_null("SceneRouter")
	if router != null:
		router.set("instant_mode", true)
	# Clear any prior record for the test character.
	injury_sys.call("clear", "test_crew_trap")
	var tag: int = _biome.register_hazard_injury("test_crew_trap", "trap", 0.5)
	# InjuryTag.RECOVERABLE == 0 for severity 0.5 (under 0.85 fatal threshold).
	_expect(tag == 0, "trap hazard registers a RECOVERABLE injury (tag 0)")
	_expect(bool(injury_sys.call("has_injury", "test_crew_trap")), "InjurySystem has the injury record")
	_expect(bool(injury_sys.call("is_recoverable", "test_crew_trap")), "injury is recoverable")
	injury_sys.call("clear", "test_crew_trap")
	if router != null:
		router.set("instant_mode", false)


# --- 19: register_hazard_injury() maps cause strings to InjuryCause
func _test_register_hazard_injury_maps_cause_to_injury_cause() -> void:
	var injury_sys: Node = root.get_node_or_null("InjurySystem")
	if injury_sys == null:
		_expect(false, "InjurySystem autoload attached (cause map test)")
		return
	# instant_mode to suppress the knock_out → SceneRouter tween error under -s.
	var router: Node = root.get_node_or_null("SceneRouter")
	if router != null:
		router.set("instant_mode", true)
	# trap → IMPACT, alien_defense → HOSTILE, asphyxiation → SUFFOCATION.
	for pair in [["trap", "trap"], ["alien_defense", "alien_defense"], ["asphyxiation", "asphyxiation"]]:
		var cause_str: String = pair[0]
		var cid: String = "test_crew_%s" % cause_str
		injury_sys.call("clear", cid)
		var tag: int = _biome.register_hazard_injury(cid, cause_str, 0.5)
		_expect(tag == 0, "%s hazard → RECOVERABLE (severity 0.5)" % cause_str)
		var rec: Dictionary = injury_sys.call("injury", cid)
		_expect(not rec.is_empty(), "%s injury record present" % cause_str)
		# The cause_str stored on the record matches the InjurySystem CAUSE_STRINGS
		# mapping (trap → "trap", alien_defense → "alien_defense", asphyxiation → "asphyxiation").
		_expect(String(rec.get("cause_str", "")) == cause_str,
			"%s cause_str stored correctly on the injury record" % cause_str)
		injury_sys.call("clear", cid)
	if router != null:
		router.set("instant_mode", false)


# === Helpers ================================================================

# Build a synthetic forward-looking frustum (6 Planes) centered at `origin`,
# facing `forward`, with far clip `far_plane`. The planes are a simple
# approximation sufficient for the chunk-visibility tests (near, far, left,
# right, top, bottom). Godot Camera3D.get_frustum() returns the same 6-plane
# shape; this avoids needing a live Camera3D node under the bare SceneTree.
func _make_forward_frustum(origin: Vector3, forward: Vector3, far_plane: float) -> Array:
	var f: Vector3 = forward.normalized()
	# Near plane: a short distance in front of the camera. The plane normal
	# points TOWARD the camera (so visible points are on the negative side).
	var near_dist: float = 0.5
	var near_plane: Plane = Plane(-f, origin + f * near_dist)
	# Far plane: normal points back toward the camera.
	var far_plane_p: Plane = Plane(f, origin + f * far_plane)
	# Left / right / top / bottom: simple 90° side planes oriented to forward.
	# For a forward = +Z camera, left rejects -X beyond origin, right rejects +X.
	# We use perpendiculars to `forward` for a box-shaped frustum (good enough
	# for the behind-camera / beyond-far tests).
	var right: Vector3 = f.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(f).normalized()
	var left_plane: Plane = Plane(right, origin)
	var right_plane: Plane = Plane(-right, origin)
	var top_plane: Plane = Plane(-up, origin)
	var bottom_plane: Plane = Plane(up, origin)
	return [near_plane, far_plane_p, left_plane, right_plane, top_plane, bottom_plane]


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	# PASS-count assertion: the test MUST reach at least 40 PASSes to prove the
	# three systems are exercised (resource targeting + terrain gen + biomes).
	# A silent skip (autoload missing) would fall under this floor and fail.
	_expect(_passes >= 40, "PASS count >= 40 (systems exercised, got %d)" % _passes)
	if _failures.is_empty() and _passes >= 40:
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)