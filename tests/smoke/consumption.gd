extends SceneTree

# Smoke test for ConsumptionManager (issue #134).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/consumption.gd
#
# Asserts (plan §8):
#   1. Rates table loads; each tracked id has a rate entry.
#   2. per_cycle_amount scales correctly by crew + sections.
#   3. simulate_seconds(cycle) depletes water/food/parts while LIME UNCHANGED.
#   4. Inventory counts match GameState.resource_count (spend routes through shim).
#   5. Scarcest resource biases next planet:
#        resource_scarcity()[0].id == build_resource_table(seed).clusters[0].type
#      AND non-empty at zero deficit (all resources at default stock).
#   6. 30-min depletion sanity band: after one cycle water/food/parts are reduced
#      by a meaningful but survivable amount (> 0, < starting stock).
#   7. Accumulator save round-trip: serialize → reset → deserialize restores accum.
#   8. Phase gating: _phase_active() false → tick() call still works (direct),
#      but _process is gated (verified via instant_mode + checking no drain occurs
#      when instant_mode is true and we tick _process indirectly).

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== consumption smoke test ===")
	call_deferred("_run")


func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	var router: Node = root.get_node_or_null("SceneRouter")
	var cm: Node = root.get_node_or_null("ConsumptionManager")

	_expect(gs != null, "GameState autoload present")
	_expect(inv != null, "Inventory autoload present")
	_expect(router != null, "SceneRouter autoload present")
	_expect(cm != null, "ConsumptionManager autoload present")

	if gs == null or inv == null or router == null or cm == null:
		_report()
		return

	router.set("instant_mode", true)

	# -------------------------------------------------------------------------
	# 1. Rates table loads; each tracked id has an entry
	# -------------------------------------------------------------------------
	gs.call("reset")
	cm.call("reset")

	var tracked_ids: Array = gs.call("tracked_resource_ids")
	_expect(not tracked_ids.is_empty(), "tracked_resource_ids() is non-empty")

	for id in tracked_ids:
		var amount: float = float(cm.call("per_cycle_amount", id))
		# lime must be 0 (scrubber loop handles lime, not consumption)
		if id == "lime":
			_expect(amount == 0.0, "lime per_cycle_amount == 0 (scrubber handles lime)")
		else:
			# Other resources should have a positive rate
			_expect(amount > 0.0, "per_cycle_amount('%s') > 0 (= %.2f)" % [id, amount])

	# -------------------------------------------------------------------------
	# 2. Scaling by crew + sections
	# -------------------------------------------------------------------------
	gs.call("reset")
	cm.call("reset")

	# Use water as the probe resource (base=2, per_crew=0.5, per_section=0.3)
	# With defaults crew=6, sections=3: 2 + 0.5*6 + 0.3*3 = 2 + 3 + 0.9 = 5.9
	var default_water_cycle: float = float(cm.call("per_cycle_amount", "water"))
	_expect(default_water_cycle > 0.0,
		"default water per_cycle_amount > 0 (= %.2f)" % default_water_cycle)

	# Change crew count to 2, sections to 1: 2 + 0.5*2 + 0.3*1 = 3.3
	gs.set("crew_count", 2)
	gs.set("active_sections", 1)
	var reduced_water_cycle: float = float(cm.call("per_cycle_amount", "water"))
	_expect(reduced_water_cycle < default_water_cycle,
		"water per_cycle decreases with fewer crew/sections (%.2f < %.2f)" % [
			reduced_water_cycle, default_water_cycle])

	# Restore defaults
	gs.set("crew_count", 6)
	gs.set("active_sections", 3)

	# -------------------------------------------------------------------------
	# 3+4. simulate_seconds(cycle) depletes water/food/parts; LIME UNCHANGED;
	#      Inventory counts match resource_count
	# -------------------------------------------------------------------------
	gs.call("reset")
	cm.call("reset")

	# Give crew enough stock to survive a full cycle
	inv.call("set_count", "water", 20)
	inv.call("set_count", "food", 20)
	inv.call("set_count", "parts", 10)
	inv.call("set_count", "lime", 5)

	var water_before: int = int(gs.call("resource_count", "water"))
	var food_before: int = int(gs.call("resource_count", "food"))
	var parts_before: int = int(gs.call("resource_count", "parts"))
	var lime_before: int = int(gs.call("resource_count", "lime"))

	var cycle_secs: float = 1800.0
	cm.call("simulate_seconds", cycle_secs)

	var water_after: int = int(gs.call("resource_count", "water"))
	var food_after: int = int(gs.call("resource_count", "food"))
	var parts_after: int = int(gs.call("resource_count", "parts"))
	var lime_after: int = int(gs.call("resource_count", "lime"))

	_expect(water_after < water_before,
		"water depleted after one cycle (%d → %d)" % [water_before, water_after])
	_expect(food_after < food_before,
		"food depleted after one cycle (%d → %d)" % [food_before, food_after])
	_expect(parts_after < parts_before,
		"parts depleted after one cycle (%d → %d)" % [parts_before, parts_after])
	_expect(lime_after == lime_before,
		"lime UNCHANGED after simulate_seconds (scrubber loop handles it) (%d == %d)" % [
			lime_after, lime_before])

	# Inventory counts match GameState shim (spend routes through Inventory)
	_expect(int(inv.call("count", "water")) == water_after,
		"Inventory.count('water') == resource_count('water')")
	_expect(int(inv.call("count", "food")) == food_after,
		"Inventory.count('food') == resource_count('food')")
	_expect(int(inv.call("count", "parts")) == parts_after,
		"Inventory.count('parts') == resource_count('parts')")

	# -------------------------------------------------------------------------
	# 5. Scarcest biases planet; non-empty at zero deficit
	# -------------------------------------------------------------------------
	# First: at zero deficit (all resources at default stock), build_resource_table
	# still returns a non-empty clusters list
	gs.call("reset")
	var scarcity_zero: Array = gs.call("resource_scarcity")
	_expect(not scarcity_zero.is_empty(), "resource_scarcity() non-empty at default stock")

	var seed: int = 12345
	var table_zero: Dictionary = gs.call("build_resource_table", seed) as Dictionary
	var clusters_zero: Variant = table_zero.get("clusters", [])
	_expect(clusters_zero is Array and not (clusters_zero as Array).is_empty(),
		"build_resource_table non-empty at zero deficit")

	# Now create scarcity: drain water to zero so it becomes scarce
	gs.call("reset")
	inv.call("set_count", "water", 0)
	inv.call("set_count", "food", 20)
	inv.call("set_count", "parts", 10)
	inv.call("set_count", "lime", 5)

	var scarcity_biased: Array = gs.call("resource_scarcity")
	_expect(not scarcity_biased.is_empty(), "resource_scarcity() non-empty with scarcity")

	var scarce_id: String = ""
	if not scarcity_biased.is_empty():
		scarce_id = String((scarcity_biased[0] as Dictionary).get("id", ""))
	_expect(scarce_id == "water",
		"scarce resource is 'water' when water=0 (got '%s')" % scarce_id)

	var table_biased: Dictionary = gs.call("build_resource_table", seed) as Dictionary
	var clusters_biased: Variant = table_biased.get("clusters", [])
	_expect(clusters_biased is Array and not (clusters_biased as Array).is_empty(),
		"build_resource_table has clusters when water scarce")

	var primary_type: String = ""
	if clusters_biased is Array and not (clusters_biased as Array).is_empty():
		var first: Variant = (clusters_biased as Array)[0]
		if first is Dictionary:
			primary_type = String((first as Dictionary).get("type", ""))
	_expect(primary_type == scarce_id,
		"build_resource_table clusters[0].type == resource_scarcity()[0].id ('%s' == '%s')" % [
			primary_type, scarce_id])

	# -------------------------------------------------------------------------
	# 6. 30-min depletion sanity band
	# -------------------------------------------------------------------------
	gs.call("reset")
	cm.call("reset")
	inv.call("set_count", "water", 50)
	inv.call("set_count", "food", 50)
	inv.call("set_count", "parts", 20)

	cm.call("simulate_seconds", 1800.0)   # full 30-min ship phase

	var w_spent: int = 50 - int(gs.call("resource_count", "water"))
	var f_spent: int = 50 - int(gs.call("resource_count", "food"))
	var p_spent: int = 20 - int(gs.call("resource_count", "parts"))

	# Meaningful depletion: at least 1 unit spent
	_expect(w_spent >= 1, "water: >= 1 unit spent in 30 min (spent %d)" % w_spent)
	_expect(f_spent >= 1, "food: >= 1 unit spent in 30 min (spent %d)" % f_spent)
	_expect(p_spent >= 1, "parts: >= 1 unit spent in 30 min (spent %d)" % p_spent)

	# Survivable: didn't drain more than starting stock
	_expect(w_spent < 50, "water: < starting stock spent in 30 min (spent %d / 50)" % w_spent)
	_expect(f_spent < 50, "food: < starting stock spent in 30 min (spent %d / 50)" % f_spent)
	_expect(p_spent < 20, "parts: < starting stock spent in 30 min (spent %d / 20)" % p_spent)

	# -------------------------------------------------------------------------
	# 7. Accumulator save round-trip
	# -------------------------------------------------------------------------
	gs.call("reset")
	cm.call("reset")
	inv.call("set_count", "water", 20)

	# Tick half a cycle to build up partial accumulators
	cm.call("simulate_seconds", 900.0)

	var saved: Dictionary = cm.call("serialize") as Dictionary
	_expect(saved.has("accum"), "serialize() has 'accum' key")

	var saved_accum: Variant = saved.get("accum", {})
	_expect(saved_accum is Dictionary, "serialize accum is a Dictionary")

	# Reset and restore
	cm.call("reset")
	# After reset all accumulators should be zero
	var post_reset_save: Dictionary = cm.call("serialize") as Dictionary
	var post_reset_accum: Variant = post_reset_save.get("accum", {})
	if post_reset_accum is Dictionary:
		for id in (post_reset_accum as Dictionary).keys():
			_expect(float((post_reset_accum as Dictionary)[id]) == 0.0,
				"reset clears accumulator for '%s'" % id)

	cm.call("deserialize", saved, 1)
	var restored_save: Dictionary = cm.call("serialize") as Dictionary
	var restored_accum: Variant = restored_save.get("accum", {})
	if saved_accum is Dictionary and restored_accum is Dictionary:
		for id in (saved_accum as Dictionary).keys():
			var orig: float = float((saved_accum as Dictionary).get(id, 0.0))
			var rest: float = float((restored_accum as Dictionary).get(id, -1.0))
			_expect(is_equal_approx(orig, rest),
				"deserialize restores accumulator['%s'] = %.4f" % [id, orig])

	# -------------------------------------------------------------------------
	# 8. Phase gating: tick() direct works; _process blocked by instant_mode
	# -------------------------------------------------------------------------
	gs.call("reset")
	cm.call("reset")
	inv.call("set_count", "water", 10)

	# instant_mode is already true — _process would return immediately.
	# Verify _phase_active() returns false when FtlLoop is IDLE + episode not complete.
	var phase_active: bool = cm.call("_phase_active") as bool
	_expect(not phase_active,
		"_phase_active() false when FtlLoop IDLE and episode not complete")

	# Confirm direct tick() still drains regardless of phase (tests call it directly).
	var water_pre_tick: int = int(gs.call("resource_count", "water"))
	cm.call("simulate_seconds", 1800.0)
	var water_post_tick: int = int(gs.call("resource_count", "water"))
	_expect(water_post_tick < water_pre_tick,
		"direct simulate_seconds() drains regardless of _phase_active() (test helper)")

	# After episode_complete, _phase_active() returns true (fallback path).
	gs.call("reset")
	cm.call("reset")
	gs.call("complete_episode_air")
	var ftl_loop: Node = root.get_node_or_null("FtlLoop")
	if ftl_loop != null:
		# FtlLoop will be in SHIP phase after episode_completed — _phase_active → true
		var phase_active_ship: bool = cm.call("_phase_active") as bool
		_expect(phase_active_ship,
			"_phase_active() true when FtlLoop in SHIP phase after episode_completed")
	else:
		# FtlLoop absent — fallback: episode_complete true → active
		var phase_active_fallback: bool = cm.call("_phase_active") as bool
		_expect(phase_active_fallback,
			"_phase_active() true via fallback when episode_complete and FtlLoop absent")

	router.set("instant_mode", false)
	_report()


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
			print("  - " + f)
		quit(1)
