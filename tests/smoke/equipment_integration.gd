extends SceneTree

# End-to-end integration test for the equipment feature (#75).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/equipment_integration.gd
#
# Ties the four merged sub-issues together and locks the parent acceptance
# criteria that no single sub-suite covers on its own:
#   1. Full loop: grant → equip → the 3D model shows gear → SAVE (serialize) →
#      a FRESH Inventory + a FRESH EquipmentMount LOAD (deserialize) → the gear
#      is still equipped AND re-renders correctly on boot.
#   2. Swapping within a slot returns the old item to the pool and never leaves a
#      duplicate gear node mounted (the #75 "never duplicates gear" criterion),
#      verified on the live model.
#   3. The documented functional-effect hook SEAMS report the cosmetic-first
#      baseline today (no protection / zero capacity), prove the generic
#      accumulators sum/any-true correctly when an `effects` def IS present, and
#      survive the save round-trip — so a follow-up issue can wire effects in
#      without a refactor.
#
# Drives the save round-trip through Inventory.serialize/deserialize directly:
# that is the EXACT per-system payload SaveManager._build_snapshot stores and
# load_and_resume restores (see save_manager.gd), so this exercises the real
# persistence path without needing a full scene transition. Uses the live
# Inventory autoload; duck-types the mount via load() (a freshly-added
# class_name may parse-error in the same headless run — memory).

const MOUNT_SCRIPT_PATH: String = "res://scripts/equipment_mount.gd"
const CHARACTER_SCENE: String = "res://objects/character.tscn"
const SAVE_VERSION: int = 2

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== equipment_integration smoke test ===")

	var inv: Node = root.get_node_or_null("Inventory")
	_expect(inv != null, "Inventory autoload attached")
	if inv == null:
		_report()
		return
	inv.call("reset")

	# Build a character + its mount, wired to the live Inventory, exactly as
	# player.gd does (model wrapper + EquipmentMount under it).
	var model_a: Node3D = (load(CHARACTER_SCENE) as PackedScene).instantiate()
	root.add_child(model_a)
	var MountScript: Script = load(MOUNT_SCRIPT_PATH)
	_expect(MountScript != null, "equipment_mount.gd loads")
	var mount_a: Node3D = _make_mount(MountScript, model_a, inv)

	# --- 1. grant + equip a multi-slot loadout; the model shows the gear -----
	inv.call("add_item", "marine_helmet", 1, "test")
	inv.call("add_item", "field_backpack", 1, "test")
	inv.call("add_item", "combat_boots", 1, "test")
	_expect(bool(inv.call("equip", "marine_helmet")), "equip marine_helmet (head)")
	_expect(bool(inv.call("equip", "field_backpack")), "equip field_backpack (back)")
	_expect(bool(inv.call("equip", "combat_boots")), "equip combat_boots (legs)")

	_expect(_gear_count(mount_a) == 3, "three gear nodes mounted for a three-slot loadout")
	_expect(_gear_for_item(mount_a, "marine_helmet") != null, "head gear visible on the model")
	_expect(_gear_for_item(mount_a, "field_backpack") != null, "back gear visible on the model")
	_expect(_gear_for_item(mount_a, "combat_boots") != null, "legs gear visible on the model")

	# --- 2. swap within the head slot: old item returns, no duplicate gear ---
	inv.call("add_item", "recon_cap", 1, "test")
	_expect(bool(inv.call("equip", "recon_cap")), "equip recon_cap into the occupied head slot")
	_expect(_gear_for_item(mount_a, "marine_helmet") == null, "swapped-out helmet gear removed from model")
	_expect(_gear_for_item(mount_a, "recon_cap") != null, "swapped-in recon_cap gear mounted")
	_expect(_gear_count(mount_a) == 3, "swap keeps gear count at 3 (no duplicate head gear)")
	_expect(int(inv.call("count", "marine_helmet")) == 1, "swapped-out helmet returned to the pool")
	# Put the helmet back so the saved loadout is head=marine_helmet for clarity.
	_expect(bool(inv.call("equip", "marine_helmet")), "re-equip marine_helmet (head)")
	_expect(_gear_count(mount_a) == 3, "re-equip still no duplicate gear")

	# --- SAVE: capture the per-system payload SaveManager would persist ------
	var snapshot: Dictionary = inv.call("serialize")
	var loadout_block: Dictionary = snapshot.get("equipped", {})
	_expect(loadout_block.size() == 3, "serialize captures the 3-slot loadout")
	_expect(String(loadout_block.get("head", "")) == "marine_helmet", "saved head = marine_helmet")
	_expect(String(loadout_block.get("back", "")) == "field_backpack", "saved back = field_backpack")
	_expect(String(loadout_block.get("legs", "")) == "combat_boots", "saved legs = combat_boots")

	# Tear the first character down (simulating leaving the scene).
	model_a.queue_free()
	mount_a = null

	# --- LOAD on a fresh boot: new Inventory state + new model + new mount ---
	# Mirror SaveManager.start_new_game()/load_and_resume(): reset, then
	# deserialize the stored block into the SAME live Inventory autoload (that is
	# what the real load path does — it does not swap the autoload instance).
	inv.call("reset")
	_expect(inv.call("equipped_items").is_empty(), "reset clears the loadout (fresh boot)")
	inv.call("deserialize", snapshot, SAVE_VERSION)
	_expect(String(inv.call("equipped_in", "head")) == "marine_helmet", "loaded head slot restored")
	_expect(String(inv.call("equipped_in", "back")) == "field_backpack", "loaded back slot restored")
	_expect(String(inv.call("equipped_in", "legs")) == "combat_boots", "loaded legs slot restored")

	# A BRAND-NEW model + mount built after load must render the restored loadout
	# from its first reconcile — the "renders correctly on boot" criterion.
	var model_b: Node3D = (load(CHARACTER_SCENE) as PackedScene).instantiate()
	root.add_child(model_b)
	var mount_b: Node3D = _make_mount(MountScript, model_b, inv)
	_expect(_gear_count(mount_b) == 3, "freshly-booted mount renders all 3 restored slots")
	_expect(_gear_for_item(mount_b, "marine_helmet") != null, "boot: head gear rendered")
	_expect(_gear_for_item(mount_b, "field_backpack") != null, "boot: back gear rendered")
	_expect(_gear_for_item(mount_b, "combat_boots") != null, "boot: legs gear rendered")

	# --- 3. functional-effect hook seams: cosmetic-first baseline today ------
	# No shipped equipment def carries an `effects` block, so the seams report
	# the no-effect baseline even with a full loadout equipped.
	_expect(not bool(inv.call("has_atmosphere_protection")),
		"cosmetic-first: equipped helmet grants NO atmosphere protection yet")
	_expect(int(inv.call("carry_capacity_modifier")) == 0,
		"cosmetic-first: equipped backpack grants NO carry-capacity bonus yet")
	_expect(not bool(inv.call("equipped_effect_flag", "atmosphere_protection")),
		"generic flag seam reports false with no effect data")
	_expect(abs(float(inv.call("equipped_effect_total", "carry_capacity", 0.0))) < 0.001,
		"generic total seam reports 0 with no effect data")

	# Prove the accumulators light up correctly the moment effect data exists.
	# Inject a synthetic effects-bearing def at runtime and equip it (this stands
	# in for the follow-up issue authoring `effects` in data/items.json — no
	# shipped data is mutated).
	_inject_effect_defs(inv)
	inv.call("add_item", "test_o2_helmet", 1, "test")
	inv.call("add_item", "test_big_pack", 1, "test")
	_expect(bool(inv.call("equip", "test_o2_helmet")), "equip synthetic protective helmet")
	_expect(bool(inv.call("equip", "test_big_pack")), "equip synthetic capacity pack")
	_expect(bool(inv.call("has_atmosphere_protection")),
		"seam: protective head gear flips atmosphere protection true")
	_expect(int(inv.call("carry_capacity_modifier")) == 4,
		"seam: capacity pack contributes +4 carry capacity (additive accumulator)")

	# The effect state rides on the loadout, so it survives the save round-trip
	# (a follow-up consumer reading the seam after load gets the right answer).
	var snap2: Dictionary = inv.call("serialize")
	inv.call("reset")
	_expect(not bool(inv.call("has_atmosphere_protection")), "reset clears the effect-bearing loadout")
	inv.call("deserialize", snap2, SAVE_VERSION)
	_expect(bool(inv.call("has_atmosphere_protection")),
		"seam survives save/load: protection restored with the loadout")
	_expect(int(inv.call("carry_capacity_modifier")) == 4,
		"seam survives save/load: +4 capacity restored with the loadout")

	model_b.queue_free()
	_report()


# --- helpers -----------------------------------------------------------------

# Build an EquipmentMount under a model wrapper, wired to the live Inventory,
# and self-heal it (headless: no frame ticks so _ready does not fire — memory).
func _make_mount(mount_script: Script, model: Node3D, inv: Node) -> Node3D:
	var mount: Node3D = mount_script.new()
	mount.name = "EquipmentMount"
	mount.call("setup", model, inv)
	model.add_child(mount)
	mount.call("reconcile")
	return mount


# Register synthetic effect-bearing defs straight into the Inventory catalog so
# the seam accumulators have data to read WITHOUT touching shipped data/items.json.
# Mirrors the def shape add_item/is_equippable/equip rely on, plus an `effects`
# block (the contract the follow-up issue authors per real item).
func _inject_effect_defs(inv: Node) -> void:
	var defs: Array = [
		{
			"id": "test_o2_helmet", "name": "O2 Helmet", "category": "equipment",
			"slot": "head", "stackable": false,
			"effects": {"atmosphere_protection": true},
		},
		{
			"id": "test_big_pack", "name": "Big Pack", "category": "equipment",
			"slot": "back", "stackable": false,
			"effects": {"carry_capacity": 4},
		},
	]
	var by_id: Dictionary = inv.get("_by_id")
	var catalog: Array = inv.get("_catalog")
	for d in defs:
		by_id[String(d["id"])] = d
		catalog.append(d)


func _gear_count(mount: Node) -> int:
	var n: int = 0
	for g in _all_gear(mount):
		n += 1
	return n


func _all_gear(mount: Node) -> Array:
	var out: Array = []
	var search_root: Node = mount.get_parent() if mount.get_parent() != null else mount
	var stack: Array = [search_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta("equip_item_id"):
			out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out


func _gear_for_item(mount: Node, item_id: String) -> Node:
	for g in _all_gear(mount):
		if String((g as Node).get_meta("equip_item_id", "")) == item_id:
			return g
	return null


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
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
