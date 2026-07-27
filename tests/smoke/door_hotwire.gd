extends SceneTree

# Smoke: tablet/hotbar wield + Gate Room soft-lock hotwire + Kino upgrade +
# control-room soft-lock clear.
#
# Run:
#   godot --headless --quit-after 600 -s res://tests/smoke/door_hotwire.gd
#   tests/run.sh door-hotwire

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== door_hotwire smoke ===")
	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(gs != null and inv != null, "GameState + Inventory autoloads")
	if gs == null or inv == null:
		_report()
		return

	gs.call("reset")

	# --- starter tools -------------------------------------------------------
	_expect(bool(inv.call("has", "tablet")), "starter: tablet granted")
	_expect(not bool(inv.call("has", "sidearm")), "starter: no sidearm yet")
	_expect(not bool(inv.call("has", "kino_remote")), "starter: no kino yet")
	_expect(String(inv.call("hotbar_item", 0)) == "tablet", "hotbar 0 = tablet")
	_expect(String(inv.call("hotbar_item", 1)) == "", "hotbar 1 empty")
	_expect(String(inv.call("active_wield_id")) == "tablet", "active wield = tablet")
	_expect(bool(gs.call("is_soft_locked", "gate_room", "stargate_corridor_east_connector")),
		"east exit soft-locked on reset")

	# --- tablet icon path ----------------------------------------------------
	var def: Dictionary = inv.call("definition", "tablet")
	var icon: String = String(def.get("icon", ""))
	_expect(icon.ends_with("tablet.png"), "tablet icon is iPad asset, not kino remote")

	# --- wield select (empty slot stays empty; tablet remains active) --------
	inv.call("select_wield", 1)
	_expect(String(inv.call("active_wield_id")) == "", "select_wield(1) empty slot")
	inv.call("select_wield", 0)
	_expect(String(inv.call("active_wield_id")) == "tablet", "select_wield(0) → tablet")

	# --- hotwire mini-game auto-solve path -----------------------------------
	var mg: Node = root.get_node_or_null("HotwireMinigame")
	_expect(mg != null, "HotwireMinigame autoload present")
	if mg != null:
		mg.set("auto_solve", true)
		var ok: bool = bool(await mg.call("play", false))
		_expect(ok, "hotwire mini-game auto_solve succeeds")
		mg.set("auto_solve", false)

	# --- clear soft lock (hotwire success path) ------------------------------
	gs.call("clear_soft_lock", "gate_room", "stargate_corridor_east_connector")
	_expect(not bool(gs.call("is_soft_locked", "gate_room", "stargate_corridor_east_connector")),
		"clear_soft_lock removes east exit")

	# Re-seed for upgrade / clear-all checks.
	gs.call("add_soft_lock", "gate_room", "stargate_corridor_east_connector")
	gs.call("add_soft_lock", "gate_room", "dummy_spur")
	_expect(bool(gs.call("is_soft_locked", "gate_room", "dummy_spur")), "add_soft_lock works")

	# --- tablet → kino_remote upgrade ----------------------------------------
	gs.call("acquire_kino")
	_expect(bool(inv.call("has", "kino_remote")), "acquire_kino grants remote")
	_expect(not bool(inv.call("has", "tablet")), "acquire_kino removes tablet")
	_expect(String(inv.call("hotbar_item", 0)) == "kino_remote", "hotbar 0 upgraded to kino")
	_expect(bool(inv.call("is_interface_tool", "kino_remote")), "kino is interface tool")

	# --- control-room clear-all ----------------------------------------------
	gs.call("clear_all_soft_locks")
	_expect(not bool(gs.call("is_soft_locked", "gate_room", "stargate_corridor_east_connector")),
		"clear_all clears east exit")
	_expect(not bool(gs.call("is_soft_locked", "gate_room", "dummy_spur")),
		"clear_all clears extras")

	# --- New Game must keep starter tools after Inventory.reset ordering ------
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null and sm.has_method("start_new_game"):
		# Simulate the wipe loop: GameState seeds, Inventory.reset clobbers,
		# then start_new_game's post-seed must restore.
		gs.call("reset")
		inv.call("reset")
		_expect(not bool(inv.call("has", "tablet")), "precondition: Inventory.reset wiped tablet")
		sm.call("start_new_game", "hotwire_smoke")
		_expect(bool(inv.call("has", "tablet")), "start_new_game re-seeds tablet after Inventory wipe")
		_expect(not bool(inv.call("has", "sidearm")), "start_new_game does not grant sidearm")
		_expect(String(inv.call("hotbar_item", 0)) == "tablet", "start_new_game restores hotbar 0")

	_report()


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _report() -> void:
	print("=== door_hotwire: %d pass, %d fail ===" % [_passes, _failures.size()])
	for f in _failures:
		print("  • ", f)
	quit(1 if not _failures.is_empty() else 0)
