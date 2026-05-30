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
	"kino_remote",
	"kino_orb",
	"rations",
	"lime",
	"small_fuse",
	"large_fuse",
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

	# --- 2. fresh state is empty -------------------------------------------
	_expect(inv.call("entries").is_empty(), "fresh inventory is empty after reset")
	_expect(int(inv.call("count", "small_fuse")) == 0, "small_fuse count starts at 0")

	# --- 3. picking up items surfaces them (THE BUG REGRESSION) ------------
	gs.call("find_small_fuse")
	_expect(int(inv.call("count", "small_fuse")) == 1, "find_small_fuse → count 1")
	_expect(bool(inv.call("has", "small_fuse", 1)), "has(small_fuse) true after pickup")
	_expect(_entry_ids(inv).has("small_fuse"), "small_fuse appears in entries()")

	gs.call("find_large_fuse")
	var ids_after_fuses: Array = _entry_ids(inv)
	_expect(ids_after_fuses.has("small_fuse") and ids_after_fuses.has("large_fuse"),
		"BOTH fuses appear in entries() (the looted-fuse regression)")

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

	# --- 7. derived / migration-free ---------------------------------------
	# Simulate a loaded save: wipe, then set ONLY the GameState fields (no
	# Inventory block exists or is restored). The projection must reflect it.
	gs.reset()
	_expect(inv.call("entries").is_empty(), "reset clears the projection")
	gs.set("small_fuse_found", true)
	gs.set("large_fuse_found", true)
	_expect(bool(inv.call("has", "small_fuse")) and bool(inv.call("has", "large_fuse")),
		"loaded GameState flags surface with no Inventory deserialize (migration-free)")

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
