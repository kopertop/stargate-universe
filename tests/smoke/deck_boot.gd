extends SceneTree

# Smoke test for the merged-deck gameplay core (single scene per floor):
#   1. ShipState registries — room damage/shield/module defaults, clamps and
#      story seeds; door open/lock semantics; module build gating (damage
#      threshold = the repair-robot hook); serialize/deserialize round-trip.
#   2. deck.tscn boots for BOTH floors: every layout room (minus the artisan
#      gate room) builds a Room_<id> root, physical doors are stamped + keyed
#      into ShipState, lift/gate transition doors exist, room consoles appear
#      only in buildable rooms, deck arrival markers stamped.
#   3. Door state persistence — open a door via the registry (as the control
#      room console does), rebuild the deck, the door restores open.
#
# Run with:
#   godot --headless --quit-after 300 -s res://tests/smoke/deck_boot.gd

const DECK_SCENE: String = "res://scenes/deck.tscn"

var _failures: Array[String] = []
var _passes: int = 0

# Autoloads fetched from root — a bare `-s` SceneTree script can't reference
# autoload identifiers at compile time (same pattern as e1_flow.gd).
var _gs: Node = null
var _ship: Node = null
var _layout: Node = null


func _initialize() -> void:
	print("=== deck-boot smoke test ===")
	for autoload_name in ["GameState", "ShipLayout", "ShipState"]:
		if root.get_node_or_null(autoload_name) == null:
			_fail("autoload", "%s not found at /root (check project.godot)" % autoload_name)
	if not _failures.is_empty():
		_report()
		return
	_gs = root.get_node("GameState")
	_ship = root.get_node("ShipState")
	_layout = root.get_node("ShipLayout")
	# Same deferred hop as scene_boot.gd: let frames flow so _ready fires
	# synchronously on add_child.
	call_deferred("_run")


func _run() -> void:
	_gs.reset()
	_ship.reset()
	_check_room_registry()
	_check_door_registry()
	_check_build_gating()
	_check_save_round_trip()
	await _check_deck_floor_0()
	await _check_deck_floor_1()
	await _check_door_persistence()
	_report()


# ---- 1. ShipState registries -------------------------------------------------

func _check_room_registry() -> void:
	_ship.reset()
	_expect(is_equal_approx(_ship.room_damage("eli_quarters"), 0.0), "fresh room: 0% damage")
	_expect(is_equal_approx(_ship.room_shield("eli_quarters"), 100.0), "fresh room: 100% shield")
	_expect(_ship.room_module("eli_quarters") == "", "fresh room: no module")
	_expect(_ship.room_damage("breached_section_south") > 60.0, "shuttle dock seeds story damage")
	_expect(_ship.room_shield("breached_section_south") < 25.0, "shuttle dock seeds weakened shield")

	_ship.set_room_damage("infirmary", 250.0)
	_expect(is_equal_approx(_ship.room_damage("infirmary"), 100.0), "damage clamps to 100")
	_ship.apply_room_damage("infirmary", -500.0)
	_expect(is_equal_approx(_ship.room_damage("infirmary"), 0.0), "damage clamps to 0")
	_ship.set_room_shield("infirmary", -40.0)
	_expect(is_equal_approx(_ship.room_shield("infirmary"), 0.0), "shield clamps to 0")

	_ship.set_room_damage("infirmary", 50.0)
	var healed: float = _ship.repair_room("infirmary", 20.0)
	_expect(is_equal_approx(healed, 20.0), "repair_room returns healed amount")
	_expect(is_equal_approx(_ship.room_damage("infirmary"), 30.0), "repair_room lowers damage")


func _check_door_registry() -> void:
	_ship.reset()
	var key: String = _gs.door_key("east_corridor", "north_corridor")
	_expect(not _ship.is_door_open(key), "fresh door: closed")
	_expect(not _ship.is_door_locked(key), "fresh door: unlocked")
	_expect(_ship.set_door_open(key, true), "open succeeds when unlocked")
	_expect(_ship.is_door_open(key), "door reads open")

	_ship.set_door_locked(key, true)
	_expect(not _ship.is_door_open(key), "locking slams an open door shut")
	_expect(not _ship.set_door_open(key, true), "open refused while locked")
	_ship.set_door_locked(key, false)
	_expect(_ship.set_door_open(key, true), "open succeeds after unlock")

	_expect(_ship.is_door_locked("north_spur|sealed_section_north"),
		"sealed-section door seeds locked")


func _check_build_gating() -> void:
	_ship.reset()
	# Builds charge their data-declared build_cost from the shared resource pool
	# now — stock plenty of Ship Parts so this check stays about the GATING rules
	# (the cost economics have their own suite in tests/smoke/ftl_cycle.gd).
	_set_parts(99)
	_expect(not _ship.modules().is_empty(), "module catalog loads from data/room_modules.json")
	_expect(not _ship.is_room_buildable("north_corridor"), "corridors are unbuildable")
	_expect(not _ship.is_room_buildable("elevator_north"), "elevators are unbuildable")
	_expect(not _ship.is_room_buildable("control_interface_room"), "the bridge is unbuildable")
	_expect(_ship.is_room_buildable("eli_quarters"), "quarters are buildable")

	_expect(_ship.build_blocker("north_corridor", "hydroponics_unit") != "",
		"build refused in a corridor")
	_expect(_ship.build_blocker("breached_section_south", "hydroponics_unit") != "",
		"build refused above the damage threshold (repair robot needed)")
	_expect(_ship.build_blocker("eli_quarters", "no_such_module") != "",
		"build refused for an unknown module")
	_expect(_ship.build_blocker("eli_quarters", "hydroponics_unit") == "",
		"build allowed in an intact quarters room")

	_expect(_ship.build_module("eli_quarters", "hydroponics_unit"), "build_module succeeds")
	_expect(_ship.room_module("eli_quarters") == "hydroponics_unit", "module recorded")
	_expect(not _ship.build_module("eli_quarters", "hydroponics_unit"),
		"rebuilding the same module is a no-op")

	# Repairing the damaged shuttle dock under the threshold unlocks building —
	# the repair-robot loop in miniature.
	_ship.repair_room("breached_section_south", 45.0)
	_expect(_ship.build_blocker("breached_section_south", "machine_shop") == "",
		"build allowed once repairs bring damage under the threshold")

	_ship.clear_room_module("eli_quarters")
	_expect(_ship.room_module("eli_quarters") == "", "clear_room_module dismantles")


func _check_save_round_trip() -> void:
	_ship.reset()
	_set_parts(99)
	_ship.set_room_damage("infirmary", 42.0)
	_ship.set_room_shield("infirmary", 61.0)
	_ship.build_module("eli_quarters", "research_lab")
	var key: String = _gs.door_key("east_corridor", "north_corridor")
	_ship.set_door_open(key, true)
	_ship.set_door_locked("cr_corridor_2|eli_quarters", true)
	_ship.merged_decks_enabled = true

	var snap: Dictionary = _ship.serialize()
	_ship.reset()
	_expect(is_equal_approx(_ship.room_damage("infirmary"), 0.0), "reset clears room state")
	_ship.deserialize(snap)
	_expect(is_equal_approx(_ship.room_damage("infirmary"), 42.0), "round-trip restores damage")
	_expect(is_equal_approx(_ship.room_shield("infirmary"), 61.0), "round-trip restores shield")
	_expect(_ship.room_module("eli_quarters") == "research_lab", "round-trip restores module")
	_expect(_ship.is_door_open(key), "round-trip restores door open state")
	_expect(_ship.is_door_locked("cr_corridor_2|eli_quarters"), "round-trip restores door lock")
	_expect(_ship.merged_decks_enabled, "round-trip restores merged-decks flag")


# ---- 2. deck scenes ------------------------------------------------------------

func _check_deck_floor_0() -> void:
	_gs.reset()
	_ship.reset()
	var deck: Node = await _boot_deck("")
	if deck == null:
		return

	# Every floor-0 layout room except the artisan gate room gets a root.
	var missing: Array[String] = []
	for room in _layout.rooms_on_floor(0):
		var rid: String = String(room["id"])
		if rid == "gate_room":
			continue
		if deck.get_node_or_null("World/Room_%s" % rid) == null:
			missing.append(rid)
	_expect(missing.is_empty(), "floor 0: all rooms built (missing: %s)" % ", ".join(missing))
	_expect(deck.get_node_or_null("World/Room_gate_room") == null,
		"floor 0: artisan gate room NOT procedurally built")

	var doors: Dictionary = _gather_doors(deck)
	_expect(doors["physical"].size() >= 12,
		"floor 0: physical doors stamped (%d found)" % doors["physical"].size())
	_expect(doors["by_id"].has(_gs.door_key("east_corridor", "north_corridor")),
		"floor 0: east↔north corridor door keyed into ShipState")
	_expect(doors["transitions"].has("gate_room"), "floor 0: gate-room transition door present")
	_expect(doors["transitions"].has("elevator_room_floor_1"), "floor 0: lift door to upper deck present")

	var locked_door: Node = doors["by_id"].get("north_spur|sealed_section_north", null)
	_expect(locked_door != null and not locked_door.call("is_open"),
		"floor 0: seeded-locked sealed-section door is shut")

	_expect(deck.get_node_or_null("World/Room_eli_quarters/RoomConsole") != null,
		"floor 0: buildable room has a room console")
	_expect(deck.get_node_or_null("World/Room_north_corridor/RoomConsole") == null,
		"floor 0: corridor has NO room console")
	_expect(deck.get_node_or_null("World/Room_control_interface_room/RoomConsole") == null,
		"floor 0: control room keeps its 4 control consoles, no build console")
	_expect(deck.get_node_or_null("World/Room_control_interface_room/ControlConsoleEast") != null,
		"floor 0: control-room accent consoles built")
	_expect(deck.has_method("open_ship_systems_panel"),
		"floor 0: deck exposes the ship-systems panel hook for control consoles")

	_expect(deck.get_node_or_null(
		"Markers/Deck_stargate_corridor_east_connector_From_gate_room") != null,
		"floor 0: gate-room arrival marker stamped")
	_expect(_ship.merged_decks_enabled, "booting a deck enables merged-deck routing")

	# Damage overlay: shuttle dock seeds 65% damage → hazard dressing exists.
	_expect(deck.get_node_or_null("World/Room_breached_section_south/DamageOverlay") != null,
		"floor 0: damaged shuttle dock gets its hazard overlay")

	deck.free()


func _check_deck_floor_1() -> void:
	_gs.reset()
	_ship.reset()
	var deck: Node = await _boot_deck("hydroponics")
	if deck == null:
		return
	_expect(int(deck.get("floor_index")) == 1, "next_room_id resolves the deck's floor")
	for rid in ["hydroponics", "quarters_room_1", "elevator_room_floor_1", "room_1753576770763"]:
		_expect(deck.get_node_or_null("World/Room_%s" % rid) != null, "floor 1: %s built" % rid)

	var doors: Dictionary = _gather_doors(deck)
	_expect(doors["by_id"].has(_gs.door_key("quarters_room_1", "room_1753576770763")),
		"floor 1: quarters corridor↔quarters is a physical door (adjacent after layout fix)")
	_expect(doors["transitions"].has("elevator_north"), "floor 1: lift door to main deck present")
	_expect(deck.get_node_or_null("World/Room_quarters_room_1/RoomConsole") != null,
		"floor 1: quarters room console present")

	# Module install re-dresses the room live (module_built → ModuleVisuals).
	# _gs.reset() above left only the seed stock; builds charge build_cost now.
	_set_parts(99)
	_expect(_ship.build_module("quarters_room_1", "hydroponics_unit"), "floor 1: module builds")
	_expect(deck.get_node_or_null("World/Room_quarters_room_1/ModuleVisuals") != null,
		"floor 1: module visuals applied on build")
	deck.free()


# ---- 3. door-state persistence --------------------------------------------------

func _check_door_persistence() -> void:
	_gs.reset()
	_ship.reset()
	var key: String = _gs.door_key("east_corridor", "north_corridor")
	# Remote-open the door the way the control-room console does…
	_ship.set_door_open(key, true)
	# …then build the deck fresh (≈ scene reload / save resume).
	var deck: Node = await _boot_deck("")
	if deck == null:
		return
	var doors: Dictionary = _gather_doors(deck)
	var door: Node = doors["by_id"].get(key, null)
	_expect(door != null and door.call("is_open"),
		"door persisted OPEN across a deck rebuild")
	# Console lock: door slams shut and refuses interaction.
	_ship.set_door_locked(key, true)
	_expect(door != null and not door.call("is_open"), "console lock slams the live door shut")
	deck.free()
	_ship.reset()
	_gs.reset()


# ---- helpers ---------------------------------------------------------------------

func _boot_deck(next_room: String) -> Node:
	_gs.next_room_id = next_room
	var packed: PackedScene = load(DECK_SCENE) as PackedScene
	if packed == null:
		_fail(DECK_SCENE, "load() returned null")
		return null
	var inst: Node = packed.instantiate()
	if inst == null:
		_fail(DECK_SCENE, "instantiate() returned null")
		return null
	root.add_child(inst)
	await process_frame
	return inst


# Walk the deck for door.gd instances. Returns {"physical": Array, "by_id":
# Dictionary door_id -> node, "transitions": Dictionary target_room_id -> node}.
func _gather_doors(deck: Node) -> Dictionary:
	var out: Dictionary = {"physical": [], "by_id": {}, "transitions": {}}
	_gather_doors_walk(deck, out)
	return out


func _gather_doors_walk(node: Node, out: Dictionary) -> void:
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("door.gd"):
		if bool(node.get("physical_mode")):
			(out["physical"] as Array).append(node)
			(out["by_id"] as Dictionary)[String(node.get("door_id"))] = node
		else:
			(out["transitions"] as Dictionary)[String(node.get("target_room_id"))] = node
	for child in node.get_children():
		_gather_doors_walk(child, out)


# Stock the shared resource pool with Ship Parts (Inventory autoload-backed).
func _set_parts(count: int) -> void:
	var inv: Node = root.get_node_or_null("Inventory")
	if inv != null:
		inv.call("set_count", "parts", count)


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  OK  ", label)
		_passes += 1
	else:
		_fail("deck", label)


func _fail(context: String, message: String) -> void:
	_failures.append("[%s] %s" % [context, message])
	printerr("  FAIL  [%s] %s" % [context, message])


func _report() -> void:
	print("\n=== deck-boot: %d passed, %d failed ===" % [_passes, _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		for f in _failures:
			printerr("  - " + f)
		printerr("RESULT: FAIL")
		quit(1)
