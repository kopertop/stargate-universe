extends SceneTree

# Headless verification of the Kino discovery → toast/compass feature and the
# COMPASS settings filters.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/kino_discovery.gd
#
# Covers (no rendering needed):
#   • A spawned KinoDrone joins group "kino_drone" (so the HUD compass can draw a
#     LIVE pip that tracks it).
#   • _detect_nearby_lime marks an in-range lime deposit discovered (the manual-
#     flight sweep — the drone isn't in group "player", so resource_node's own
#     fog-of-war never fires for it) and leaves out-of-range deposits alone.
#   • PlanetCompass._kino_positions prefers a LIVE drone node over the stored
#     deploy position, and falls back to the stored position when no live node.
#   • The compass_show_* filters round-trip through GameState serialize/deserialize.
#   • The batched discovery toast collapses a burst into one log line (singular
#     and plural forms).
#
# Scripts are load()ed at runtime (not preloaded) because they reference autoload
# globals not visible at the -s top-level compile pass. Same pattern as kino_doors.

var KinoDroneScript: Script = null
var ResourceNodeScript: Script = null
var PlanetCompassScript: Script = null
var PoiNodeScript: Script = null

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== kino discovery + compass-filter tests ===")
	KinoDroneScript = load("res://scripts/kino_drone.gd")
	ResourceNodeScript = load("res://scripts/resource_node.gd")
	PlanetCompassScript = load("res://scripts/planet_compass.gd")
	PoiNodeScript = load("res://scripts/poi_node.gd")
	if KinoDroneScript == null or ResourceNodeScript == null or PlanetCompassScript == null or PoiNodeScript == null:
		print("SHOT_ERROR could not load KinoDrone/ResourceNode/PlanetCompass/PoiNode scripts")
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(gs != null, "GameState autoload attached")
	_expect(router != null, "SceneRouter autoload attached")
	if gs == null or router == null:
		_report()
		return

	router.set("instant_mode", true)        # keep KinoDrone._ready light in headless
	gs.call("reset")
	await process_frame

	await _test_drone_joins_group()
	await _test_autosearch_marks_discoverables(gs)
	await _test_kino_positions_live_then_fallback(gs)
	_test_filter_flags_round_trip(gs)
	_test_find_toast(gs)

	_report()


# ─── helpers ─────────────────────────────────────────────────────────────

func _spawn_drone(name_suffix: String) -> Node:
	var dr: Node = KinoDroneScript.new()
	dr.name = "TestKino_" + name_suffix
	dr.set("launch_in_ship", false)
	root.add_child(dr)
	return dr


func _make_lime(node_name: String, pos: Vector3) -> Node:
	var n: Node3D = ResourceNodeScript.new()
	n.name = node_name
	n.set("resource_type", "lime")
	n.add_to_group("lime_node")
	root.add_child(n)
	n.global_position = pos
	return n


func _make_poi(node_name: String, category: String, label: String, pos: Vector3) -> Node:
	var n: Node3D = PoiNodeScript.new()
	n.name = node_name
	n.set("poi_category", category)
	n.set("poi_label", label)
	root.add_child(n)
	n.global_position = pos
	return n


func _cleanup() -> void:
	for n in root.get_children():
		if n.name.begins_with("TestKino_") or n.name.begins_with("TestLime") \
				or n.name.begins_with("TestPoi") or n.name.begins_with("TestCompass"):
			root.remove_child(n)
			n.queue_free()


# ─── tests ────────────────────────────────────────────────────────────────

func _test_drone_joins_group() -> void:
	print("\n--- a spawned KinoDrone joins group \"kino_drone\" ---")
	await _cleanup()
	var dr: Node = _spawn_drone("group")
	await process_frame
	_expect(dr.is_in_group("kino_drone"),
		"KinoDrone._ready adds itself to group \"kino_drone\" (for the live compass pip)")
	await _cleanup()


func _test_autosearch_marks_discoverables(gs: Node) -> void:
	print("\n--- _detect_nearby_discoverables finds ANY in-range POI (lime + ruin), not just lime ---")
	await _cleanup()
	gs.call("reset")
	var dr: Node = _spawn_drone("detect")
	(dr as Node3D).global_position = Vector3.ZERO
	# Within AUTO_DETECT_RANGE (24 m): a lime deposit AND a (non-lime) ruin POI.
	# Well outside range: another lime that must stay hidden.
	var near_lime: Node = _make_lime("TestLimeNear", Vector3(8.0, 0.0, 0.0))
	var near_poi: Node = _make_poi("TestPoiRuin", "ruin", "Ancient Ruin", Vector3(0.0, 0.0, 10.0))
	var far_lime: Node = _make_lime("TestLimeFar", Vector3(80.0, 0.0, 0.0))
	await process_frame

	dr.call("_detect_nearby_discoverables")
	_expect(gs.call("is_poi_discovered", "TestLimeNear"),
		"in-range lime is found by the auto-search sweep")
	_expect(gs.call("is_poi_discovered", "TestPoiRuin"),
		"in-range NON-LIME POI (ruin) is also found — sweep scans the whole \"discoverable\" group")
	_expect(not gs.call("is_poi_discovered", "TestLimeFar"),
		"out-of-range deposit is NOT found")
	_expect(near_poi.call("is_discovered") == true, "ruin node reports is_discovered()==true")
	_expect(far_lime.call("is_discovered") == false, "far lime still is_discovered()==false")
	# The recorded POI keeps its category + label (drives the compass glyph/colour).
	var rec: Dictionary = (gs.get("discovered_pois") as Dictionary).get("TestPoiRuin", {})
	_expect(String(rec.get("category")) == "ruin", "found ruin recorded with category \"ruin\"")
	_expect(String(rec.get("label")) == "Ancient Ruin", "found ruin recorded with its label")
	await _cleanup()
	gs.call("reset")


func _test_kino_positions_live_then_fallback(gs: Node) -> void:
	print("\n--- compass _kino_positions: live node wins, deploy position is the fallback ---")
	await _cleanup()
	gs.call("reset")
	var compass: Node = PlanetCompassScript.new()
	compass.name = "TestCompass"
	root.add_child(compass)
	compass.call("set_scene_path", "res://scenes/planet.tscn")

	# Stored deploy position (fallback source) far from the live node.
	gs.call("deploy_kino", "res://scenes/planet.tscn", Vector3(100.0, 0.0, 100.0))

	# A live drone node at a distinct position.
	var dr: Node = _spawn_drone("live")
	(dr as Node3D).global_position = Vector3(5.0, 0.0, -5.0)
	await process_frame

	var live: Array = compass.call("_kino_positions")
	_expect(live.size() == 1, "live drone present → exactly one position returned (live wins over stored)")
	if live.size() == 1:
		_expect((live[0] as Vector3).distance_to(Vector3(5.0, 0.0, -5.0)) < 0.01,
			"returned position is the LIVE drone's current position, not the deploy point")

	# Drop the live node → falls back to the stored deploy position.
	root.remove_child(dr)
	dr.queue_free()
	await process_frame
	var fallback: Array = compass.call("_kino_positions")
	_expect(fallback.size() == 1, "no live node → fall back to the stored deploy position")
	if fallback.size() == 1:
		_expect((fallback[0] as Vector3).distance_to(Vector3(100.0, 0.0, 100.0)) < 0.01,
			"fallback position is the stored deploy point")
	root.remove_child(compass)
	compass.queue_free()
	await _cleanup()
	gs.call("reset")


func _test_filter_flags_round_trip(gs: Node) -> void:
	print("\n--- compass_show_* filters proxy through Settings ---")
	gs.call("reset")
	# Defaults are all-on.
	_expect(gs.get("compass_show_lime") == true and gs.get("compass_show_gate") == true,
		"filters default to ON after reset")
	gs.set("compass_show_lime", false)
	gs.set("compass_show_pois", false)
	gs.set("compass_show_companions", false)
	# Compass flags live on Settings (persisted via settings.cfg), not in save.json.
	# Verify the proxy reads back the written values.
	_expect(gs.get("compass_show_lime") == false, "proxy reads compass_show_lime=false")
	_expect(gs.get("compass_show_pois") == false, "proxy reads compass_show_pois=false")
	_expect(gs.get("compass_show_kinos") == true, "proxy reads untouched compass_show_kinos=true")
	# serialize() no longer includes compass flags (they're in Settings, not save.json).
	var snap: Dictionary = gs.call("serialize")
	_expect(not snap.has("compass_show_lime"), "serialize excludes compass flags (Settings owns them)")
	gs.call("reset")
	_expect(gs.get("compass_show_pois") == true, "reset restored the default before reload")
	# After reset, the Settings defaults are restored (all ON).
	_expect(gs.get("compass_show_lime") == true, "reset restored compass_show_lime to default")
	gs.call("reset")


func _test_find_toast(gs: Node) -> void:
	print("\n--- per-find toast names each thing, drained one at a time ---")
	gs.call("reset")
	# _announce_poi early-returns in instant_mode, so drive the drain directly with
	# a staged queue (the per-find naming + one-at-a-time logic under test).
	var before: int = (gs.get("log_entries") as Array).size()
	var q: Array[String] = ["Ancient Ruin", "Ore Vein"]
	gs.set("_poi_toast_queue", q)
	gs.call("_emit_next_poi_toast")
	var entries: Array = gs.get("log_entries")
	_expect(entries.size() == before + 1, "first emit logs exactly one line (one find at a time)")
	_expect(String(entries[entries.size() - 1]) == "Kino found: Ancient Ruin",
		"toast names the FIRST find: '%s'" % String(entries[entries.size() - 1]))
	gs.call("_emit_next_poi_toast")
	entries = gs.get("log_entries")
	_expect(String(entries[entries.size() - 1]) == "Kino found: Ore Vein",
		"next emit names the SECOND find: '%s'" % String(entries[entries.size() - 1]))
	# Queue now empty → another emit adds nothing.
	var n0: int = (gs.get("log_entries") as Array).size()
	gs.call("_emit_next_poi_toast")
	_expect((gs.get("log_entries") as Array).size() == n0, "draining an empty queue adds nothing")
	gs.call("reset")


# ─── reporting ─────────────────────────────────────────────────────────────

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - ", f)
		quit(1)
