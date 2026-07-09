extends SceneTree

# Smoke test for the mine→build/repair ECONOMY seam of the core loop:
#
#   * ResourceNode.interact() banks resources into the shared Inventory pool
#     (the actual on-planet mining path — previously untested),
#   * ShipState.build_module CHARGES the module's data-declared build_cost
#     (data/room_modules.json) from that pool,
#   * ShipState.repair_room_with_parts spends Ship Parts to restore the
#     deck-registry structural damage that gates module construction.
#
# The FTL loop itself (SHIP → JUMPING → PLANET, issue #130) is covered by
# tests/smoke/ftl_loop.gd — this file owns only the resource economics.
#
# Run with:
#   godot --headless --quit-after 300 -s res://tests/smoke/build_economy.gd

var _failures: Array[String] = []
var _passes: int = 0

# Autoloads fetched from root — a bare `-s` SceneTree script can't reference
# autoload identifiers at compile time (same pattern as deck_boot.gd).
var _gs: Node = null
var _ship: Node = null
var _inv: Node = null


func _initialize() -> void:
	print("=== build-economy smoke test ===")
	for autoload_name in ["GameState", "ShipState", "ShipLayout", "Inventory"]:
		if root.get_node_or_null(autoload_name) == null:
			_fail("autoload", "%s not found at /root (check project.godot)" % autoload_name)
	if not _failures.is_empty():
		_report()
		return
	_gs = root.get_node("GameState")
	_ship = root.get_node("ShipState")
	_inv = root.get_node("Inventory")
	call_deferred("_run")


func _run() -> void:
	_check_mining_interact()
	_check_build_economy()
	_check_repair_economy()
	_report()


# ---- 1. mining: ResourceNode.interact() banks into the pool -------------------

func _check_mining_interact() -> void:
	_gs.reset()
	_inv.call("set_count", "parts", 0)
	var node_script: Script = load("res://scripts/resource_node.gd")
	var node: StaticBody3D = node_script.new()
	node.resource_type = "parts"
	node.amount = 3
	root.add_child(node)
	node.interact(null)
	_expect(_gs.resource_count("parts") == 3, "mining a deposit banks its resource")
	_expect(node.depleted, "mined deposit depletes")
	node.interact(null)
	_expect(_gs.resource_count("parts") == 3, "a depleted deposit yields nothing more")
	node.queue_free()


# ---- 2. build economy (mined parts are the sink) ------------------------------

func _check_build_economy() -> void:
	_gs.reset()
	_ship.reset()
	_inv.call("set_count", "parts", 0)
	var blocker: String = _ship.build_blocker("eli_quarters", "hydroponics_unit")
	_expect(blocker != "", "build refused with an empty parts pool")
	_expect(blocker.contains("Parts"), "blocker names the missing resource")

	_inv.call("set_count", "parts", 5)
	_expect(_ship.build_blocker("eli_quarters", "hydroponics_unit") != "",
		"build refused when parts fall short of the module cost")

	_inv.call("set_count", "parts", 7)
	_expect(_ship.build_cost("hydroponics_unit").get("parts", 0) == 6,
		"hydroponics cost read from data/room_modules.json")
	_expect(_ship.build_module("eli_quarters", "hydroponics_unit"),
		"build succeeds once the pool covers the cost")
	_expect(_gs.resource_count("parts") == 1, "build charges EXACTLY the module cost")
	_expect(not _ship.build_module("eli_quarters", "research_lab"),
		"next build refused — pool spent")


# ---- 3. repair economy (parts restore damage, unblocking builds) ---------------

func _check_repair_economy() -> void:
	_gs.reset()
	_ship.reset()
	_ship.set_room_damage("eli_quarters", 50.0)
	_inv.call("set_count", "parts", 0)
	_expect(_ship.repair_blocker("eli_quarters") != "", "repair refused with no parts")
	_expect(not _ship.repair_room_with_parts("eli_quarters"), "priced repair fails dry")

	_inv.call("set_count", "parts", 10)
	_expect(_ship.repair_room_with_parts("eli_quarters"), "repair spends parts")
	_expect(is_equal_approx(_ship.room_damage("eli_quarters"), 25.0),
		"one spend restores %d%%" % int(_ship.REPAIR_PER_SPEND_PCT))
	_expect(_gs.resource_count("parts") == 9, "repair charged 1 part")
	_expect(_ship.repair_room_with_parts("eli_quarters"), "second repair spends again")
	_expect(is_equal_approx(_ship.room_damage("eli_quarters"), 0.0), "room fully restored")
	_expect(_ship.repair_blocker("eli_quarters") != "", "pristine room refuses further repairs")

	# The story-damaged section: repair down past the threshold, then build in it.
	_expect(_ship.build_blocker("breached_section_south", "storage_depot") != "",
		"story-damaged section refuses builds at 65% damage")
	_expect(_ship.repair_room_with_parts("breached_section_south"), "repair 65% → 40%")
	_expect(_ship.repair_room_with_parts("breached_section_south"), "repair 40% → 15%")
	_expect(_ship.build_blocker("breached_section_south", "storage_depot") == "",
		"repaired section accepts builds (parts remain for the depot cost)")
	_expect(_ship.build_module("breached_section_south", "storage_depot"),
		"module built in the repaired section")


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
