extends SceneTree

# Smoke test for the data-driven Inventory projection (issue #41).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/inventory.gd
#
# Asserts:
#   • data/items.json loads + the catalog has the expected ids.
#   • Picking up an item (via the GameState mutators) surfaces it in
#     Inventory.entries() — INCLUDING both fuses, the regression that would
#     have caught the looted-fuse bug (only "Kino Remote" + "Rations" showed).
#   • count()/has() match the canonical GameState sources (lime gate intact).
#   • show_in_inventory + count>0 filtering.
#   • Derived/migration: a loaded save (GameState fields set directly, no
#     inventory block) is reflected with no Inventory deserialize — the
#     projection needs no separate persistence or migration.
#
# Uses the live autoloads (GameState + Inventory) like quest_log.gd / e1_flow.gd.

const EXPECTED_CATALOG_IDS: Array[String] = [
	"tablet",
	"kino_remote",
	"sidearm",
	"kino_orb",
	"rations",
	"lime",
	"small_fuse",
	"large_fuse",
	"marine_helmet",
	"recon_cap",
	"tac_vest",
	"field_backpack",
	"combat_boots",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== inventory smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(gs != null, "GameState autoload attached")
	_expect(inv != null, "Inventory autoload attached")
	if gs == null or inv == null:
		_report()
		return

	gs.reset()

	# --- 1. catalog loads --------------------------------------------------
	var ids: Array = inv.call("catalog_ids")
	for expected in EXPECTED_CATALOG_IDS:
		_expect(ids.has(expected), "catalog contains '%s'" % expected)

	# --- 2. fresh state holds tracked resources + starter tools ------------
	# reset() seeds tracked-resource opening stock (water/food/parts/lime —
	# issue #86) plus tablet/sidearm (weapons-tools). Nothing else.
	var fresh_ids: Array = _entry_ids(inv)
	var tracked_ids: Array = gs.call("tracked_resource_ids")
	var starter_ids: Array = ["tablet"]
	for fid in fresh_ids:
		_expect(
			tracked_ids.has(fid) or starter_ids.has(fid),
			"fresh inventory only carries tracked/starter items (stray: %s)" % fid
		)
	_expect(int(inv.call("count", "water")) > 0, "water seeded with opening stock after reset")
	_expect(int(inv.call("count", "small_fuse")) == 0, "small_fuse count starts at 0")
	_expect(bool(inv.call("has", "tablet")), "tablet seeded on reset")
	_expect(not bool(inv.call("has", "sidearm")), "sidearm not seeded on reset")
	_expect(String(inv.call("hotbar_item", 0)) == "tablet", "hotbar slot 0 is tablet")

	# --- 3. picking up items surfaces them (THE BUG REGRESSION) ------------
	gs.call("find_small_fuse")
	_expect(int(inv.call("count", "small_fuse")) == 1, "find_small_fuse → count 1")
	_expect(bool(inv.call("has", "small_fuse", 1)), "has(small_fuse) true after pickup")
	_expect(_entry_ids(inv).has("small_fuse"), "small_fuse appears in entries()")

	gs.call("find_large_fuse")
	var ids_after_fuses: Array = _entry_ids(inv)
	_expect(ids_after_fuses.has("small_fuse") and ids_after_fuses.has("large_fuse"),
		"BOTH fuses appear in entries() (the looted-fuse regression)")

	# Fuses are stackable counted items now: looting a second small fuse stacks
	# to 2, and consuming ONE (what the door panel does) leaves 1.
	gs.call("find_small_fuse")
	_expect(int(inv.call("count", "small_fuse")) == 2, "second small fuse stacks to 2")
	inv.call("remove_item", "small_fuse", 1, "fitted into the door panel")
	_expect(int(inv.call("count", "small_fuse")) == 1, "consuming one small fuse leaves 1 (2 - 1 = 1)")
	# Consume the last one → drops out of the pack entirely.
	inv.call("remove_item", "small_fuse", 1, "door panel")
	_expect(int(inv.call("count", "small_fuse")) == 0, "consuming the last small fuse empties it")
	_expect(not _entry_ids(inv).has("small_fuse"), "spent small_fuse drops out of entries()")
	_expect(bool(inv.call("has", "large_fuse")), "large_fuse is NOT consumed alongside the small fuse")

	gs.call("find_rations")
	_expect(int(inv.call("count", "rations")) == 1, "rations count 1 after find_rations")
	_expect(_entry_ids(inv).has("rations"), "rations appears in entries()")

	# --- 4. resource gate parity (lime) ------------------------------------
	gs.call("add_resource", gs.AIR_LIME_RESOURCE, gs.AIR_LIME_REQUIRED, "test")
	_expect(int(inv.call("count", "lime")) == gs.AIR_LIME_REQUIRED, "lime count mirrors resource pool")
	_expect(bool(inv.call("has", "lime", gs.AIR_LIME_REQUIRED)),
		"Inventory.has(lime, REQUIRED) matches the repair gate")
	_expect(not bool(inv.call("has", "lime", gs.AIR_LIME_REQUIRED + 1)),
		"Inventory.has(lime, REQUIRED+1) is false")

	# --- 5. kino remote ----------------------------------------------------
	_expect(int(inv.call("count", "kino_remote")) == 0, "kino_remote absent before acquire")
	gs.call("acquire_kino")
	_expect(int(inv.call("count", "kino_remote")) == 1, "kino_remote present after acquire")
	_expect(_entry_ids(inv).has("kino_remote"), "kino_remote appears in entries()")

	# --- 6. entries are catalog-ordered + carry metadata -------------------
	var entries: Array = inv.call("entries")
	for e in entries:
		_expect(e.has("id") and e.has("def") and e.has("count"),
			"entry has id/def/count keys")
		_expect(String((e["def"] as Dictionary).get("name", "")) != "",
			"entry '%s' has a display name" % String(e["id"]))

	# --- 7. reset + save round-trip ----------------------------------------
	gs.call("reset")
	# reset() clears looted story items back to tracked resources + starter tools
	# (tablet only). No fuses/rations/kino/sidearm survive.
	var post_reset_ids: Array = _entry_ids(inv)
	var tracked_after: Array = gs.call("tracked_resource_ids")
	var starter_after: Array = ["tablet"]
	var only_baseline: bool = true
	for rid in post_reset_ids:
		if not tracked_after.has(rid) and not starter_after.has(rid):
			only_baseline = false
	_expect(only_baseline, "GameState.reset() clears non-baseline items from the store")
	_expect(not _entry_ids(inv).has("small_fuse"), "reset() drops looted story items")
	_expect(bool(inv.call("has", "tablet")), "reset() re-seeds tablet")
	# Clear the seeded baseline too so the save round-trip below starts clean.
	inv.call("reset")
	inv.call("add_item", "lime", 2, "test")
	inv.call("add_item", "small_fuse", 1, "test")
	var snap: Dictionary = inv.call("serialize")
	inv.call("reset")
	_expect(int(inv.call("count", "lime")) == 0, "reset empties the store")
	inv.call("deserialize", snap, 2)
	_expect(int(inv.call("count", "lime")) == 2 and int(inv.call("count", "small_fuse")) == 1,
		"serialize → reset → deserialize round-trips the pool")

	# --- 8. legacy-save migration ------------------------------------------
	# An old save stored items on the GameState block (kino_acquired / *_fuse_found
	# / kino_orbs / a resources dict). GameState.deserialize seeds the pool from
	# them; here we drive that path directly with a legacy-shaped block.
	gs.call("reset")
	gs.call("deserialize", {
		"kino_acquired": true,
		"small_fuse_found": true,
		"kino_orbs": 2,
		"resources": {"lime": 3},
	}, 1)
	_expect(bool(inv.call("has", "kino_remote")), "legacy migration: kino_acquired → kino_remote")
	_expect(int(inv.call("count", "small_fuse")) == 1, "legacy migration: small_fuse_found → small_fuse")
	_expect(int(inv.call("count", "kino_orb")) == 2, "legacy migration: kino_orbs → kino_orb count")
	_expect(int(inv.call("count", "lime")) == 3, "legacy migration: resources dict → lime count")

	# --- 9. equipment: slot metadata loads (issue #71) ---------------------
	gs.call("reset")
	_expect(bool(inv.call("is_equippable", "marine_helmet")), "marine_helmet is_equippable")
	_expect(String(inv.call("slot_of", "marine_helmet")) == "head", "marine_helmet → head slot")
	_expect(String(inv.call("slot_of", "tac_vest")) == "torso", "tac_vest → torso slot")
	_expect(String(inv.call("slot_of", "field_backpack")) == "back", "field_backpack → back slot")
	_expect(String(inv.call("slot_of", "combat_boots")) == "legs", "combat_boots → legs slot")
	_expect(not bool(inv.call("is_equippable", "rations")), "non-equipment item is not equippable")
	var helmet_def: Dictionary = inv.call("definition", "marine_helmet")
	_expect(String(helmet_def.get("model", "")).begins_with("res://models/equipment/"),
		"equipment def carries a model path")
	_expect(String(helmet_def.get("socket", "")) == "Head", "equipment def carries a socket hint")

	# --- 10. equip / unequip mutate ONE _equipped dict + emit --------------
	var equip_events: Array = []
	inv.connect("equipment_changed", func(slot: String, item_id: String) -> void:
		equip_events.append([slot, item_id]))

	# Can't equip what you don't hold.
	_expect(not bool(inv.call("equip", "marine_helmet")), "equip fails when item not held")

	inv.call("add_item", "marine_helmet", 1, "test")
	_expect(bool(inv.call("equip", "marine_helmet")), "equip succeeds when item held")
	_expect(String(inv.call("equipped_in", "head")) == "marine_helmet", "equipped_in(head) reflects equip")
	_expect(bool(inv.call("is_equipped", "marine_helmet")), "is_equipped(marine_helmet) true")
	_expect(int(inv.call("count", "marine_helmet")) == 0, "equipping consumes the item from the pool")
	_expect(not _entry_ids(inv).has("marine_helmet"), "equipped item drops out of inventory entries()")
	_expect(equip_events.size() == 1 and equip_events[0][0] == "head" and equip_events[0][1] == "marine_helmet",
		"equipment_changed emitted once with (head, marine_helmet)")

	# --- 11. slots are independent (equip legs, head unaffected) -----------
	inv.call("add_item", "combat_boots", 1, "test")
	_expect(bool(inv.call("equip", "combat_boots")), "equip combat_boots into legs")
	_expect(String(inv.call("equipped_in", "legs")) == "combat_boots", "legs slot filled independently")
	_expect(String(inv.call("equipped_in", "head")) == "marine_helmet", "head slot unaffected by legs equip")
	var loadout: Dictionary = inv.call("equipped_items")
	_expect(loadout.size() == 2 and loadout.get("head", "") == "marine_helmet" and loadout.get("legs", "") == "combat_boots",
		"equipped_items() returns the full two-slot loadout")

	# --- 12. equipping a full slot swaps cleanly (old item returns) --------
	# recon_cap is also a head item; equipping it must evict marine_helmet back
	# into the pool and seat recon_cap, all on the ONE _equipped dict.
	inv.call("add_item", "recon_cap", 1, "test")
	equip_events.clear()
	_expect(bool(inv.call("equip", "recon_cap")), "equip recon_cap into the occupied head slot")
	_expect(String(inv.call("equipped_in", "head")) == "recon_cap", "head slot now holds recon_cap")
	_expect(int(inv.call("count", "marine_helmet")) == 1, "swapped-out marine_helmet returns to the pool")
	_expect(_entry_ids(inv).has("marine_helmet"), "swapped-out item reappears in entries()")
	_expect(int(inv.call("count", "recon_cap")) == 0, "swapped-in item consumed from the pool")
	_expect(not bool(inv.call("is_equipped", "marine_helmet")), "marine_helmet no longer equipped after swap")
	_expect(equip_events.size() == 1 and equip_events[0][0] == "head" and equip_events[0][1] == "recon_cap",
		"swap emits equipment_changed(head, recon_cap) once")

	# --- 13. unequip clears the slot + returns item to pool ----------------
	equip_events.clear()
	inv.call("unequip", "head")
	_expect(String(inv.call("equipped_in", "head")) == "", "unequip clears the slot")
	_expect(not bool(inv.call("is_equipped", "recon_cap")), "is_equipped false after unequip")
	_expect(int(inv.call("count", "recon_cap")) == 1, "unequip returns the item to the pool")
	_expect(equip_events.size() == 1 and equip_events[0][0] == "head" and equip_events[0][1] == "",
		"equipment_changed(head, '') emitted on unequip")
	inv.call("unequip", "head")
	_expect(String(inv.call("equipped_in", "head")) == "", "unequip on an empty slot is a no-op (no crash)")

	# Seat a torso item so the round-trip below covers multiple filled slots.
	inv.call("add_item", "tac_vest", 1, "test")
	_expect(bool(inv.call("equip", "tac_vest")), "equip tac_vest into torso")

	# --- 14. loadout round-trips through save / load -----------------------
	var snap2: Dictionary = inv.call("serialize")
	_expect((snap2.get("equipped", {}) as Dictionary).size() == 2, "serialize captures the 2-slot loadout")
	inv.call("reset")
	_expect(inv.call("equipped_items").is_empty(), "reset clears the loadout")
	_expect(String(inv.call("equipped_in", "torso")) == "", "reset empties torso slot")
	inv.call("deserialize", snap2, 2)
	_expect(String(inv.call("equipped_in", "torso")) == "tac_vest", "deserialize restores torso slot")
	_expect(String(inv.call("equipped_in", "legs")) == "combat_boots", "deserialize restores legs slot")
	_expect(String(inv.call("equipped_in", "head")) == "", "head slot stays empty after round-trip")
	_expect(inv.call("equipped_items").size() == 2, "loadout round-trips through save/load")

	_report()


func _entry_ids(inv: Node) -> Array:
	var out: Array = []
	for e in inv.call("entries"):
		out.append(String((e as Dictionary)["id"]))
	return out


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
