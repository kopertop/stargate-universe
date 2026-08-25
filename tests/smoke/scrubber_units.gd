extends SceneTree

# Smoke test for the optional CO2-scrubber registry (the discover/open/recharge
# maintenance units beyond the E1 story scrubber). Verifies the ONE-collection
# API: lazy defaults, discovery, open/close toggle, one-lime recharge with
# auto-close, idempotency, and the serialize/deserialize round-trip.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/scrubber_units.gd

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== scrubber-units smoke test ===")
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(gs != null, "GameState autoload attached")
	_expect(inv != null, "Inventory autoload attached")
	if gs == null or inv == null:
		_report()
		return

	gs.reset()

	# --- registry is configured + starts empty ------------------------------
	_expect((gs.AUX_SCRUBBERS as Array).size() == 3, "three optional scrubbers configured")
	_expect((gs.scrubber_units as Dictionary).is_empty(), "reset: registry starts empty")

	var id: String = "north_corridor"

	# --- lazy defaults: an unknown unit reads undiscovered/closed/unrepaired -
	_expect(not gs.is_scrubber_unit_discovered(id), "unknown unit: not discovered")
	_expect(not gs.is_scrubber_unit_open(id), "unknown unit: closed")
	_expect(not gs.is_scrubber_unit_repaired(id), "unknown unit: not repaired")

	# --- discovery: identifies + opens the panel, once ----------------------
	_expect(gs.discover_scrubber_unit(id, "North Section Scrubber"), "discover returns true the first time")
	_expect(gs.is_scrubber_unit_discovered(id), "after discover: discovered")
	_expect(gs.is_scrubber_unit_open(id), "after discover: panel open")
	_expect(not gs.discover_scrubber_unit(id), "discover is idempotent (false second time)")

	# --- open/close toggle at will ------------------------------------------
	gs.set_scrubber_unit_open(id, false)
	_expect(not gs.is_scrubber_unit_open(id), "can close the panel")
	gs.set_scrubber_unit_open(id, true)
	_expect(gs.is_scrubber_unit_open(id), "can re-open the panel")

	# --- recharge needs lime ------------------------------------------------
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "no lime yet")
	_expect(not gs.repair_scrubber_unit(id), "recharge fails without lime")
	_expect(not gs.is_scrubber_unit_repaired(id), "still not repaired without lime")

	# --- recharge with lime: spends ONE, auto-closes the panel --------------
	gs.add_resource(gs.AIR_LIME_RESOURCE, 2, "test")
	_expect(gs.repair_scrubber_unit(id), "recharge succeeds with lime")
	_expect(gs.is_scrubber_unit_repaired(id), "repaired flag set")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 2 - gs.SCRUBBER_REPAIR_LIME_COST,
		"recharge spends exactly ONE lime")
	_expect(not gs.is_scrubber_unit_open(id), "panel auto-slides shut on recharge")
	_expect(not gs.repair_scrubber_unit(id), "recharge is idempotent (no double-spend)")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 2 - gs.SCRUBBER_REPAIR_LIME_COST,
		"idempotent recharge does not spend more lime")
	_expect(gs.aux_scrubbers_repaired_count() == 1, "one optional scrubber repaired")

	# --- a repaired unit can still be opened/closed for inspection ----------
	gs.set_scrubber_unit_open(id, true)
	_expect(gs.is_scrubber_unit_open(id), "repaired unit re-opens for inspection")

	# --- registry survives a save round-trip --------------------------------
	var snap: Dictionary = gs.serialize()
	gs.reset()
	_expect((gs.scrubber_units as Dictionary).is_empty(), "reset clears registry before load")
	gs.deserialize(snap, int(snap.get("version", 2)))
	_expect(gs.is_scrubber_unit_repaired(id), "deserialize restores repaired state")
	_expect(gs.is_scrubber_unit_open(id), "deserialize restores open state")
	_expect(gs.aux_scrubbers_repaired_count() == 1, "deserialize restores repaired count")

	# --- the E1 story scrubber is independent of the registry ---------------
	_expect(not gs.scrubber_repaired, "E1 story scrubber unaffected by aux registry")

	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
