extends SceneTree

# Smoke test for BridgeConsole / Core-Loop config (issue #133).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/bridge_loop_config.gd
#
# Assertions (plan §7):
#   1. Settings defaults present (ship/planet/band/pref fields exist with valid defaults).
#   2. Clamps — over/under for ship_phase_seconds, planet_phase_seconds, band.
#   3. Signals fire on set_*.
#   4. Persist round-trip: set → save → junk in-memory → load_from_disk → restored.
#      Prior user://settings.cfg is SAVED and RESTORED in teardown.
#   5. Gating: is_bridge_discovered() == false when rooms_discovered is empty.
#   6. Gating: is_bridge_discovered() == true after seeding a generated bridge room
#      + appending its id to rooms_discovered.
#   7. #130 contract: after set_ship_phase_seconds(X), GameState.ship_phase_base_seconds()
#      resolves to clampf(X, 60, 7200) via the single override path.
#   8. BridgeConsole._on_interact under instant_mode adds no CanvasLayer children.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== bridge_loop_config smoke test ===")

	var settings: Node = root.get_node_or_null("Settings")
	var gs: Node = root.get_node_or_null("GameState")
	var ps: Node = root.get_node_or_null("ProceduralShip")
	var router: Node = root.get_node_or_null("SceneRouter")

	_expect(settings != null, "Settings autoload present")
	_expect(gs != null, "GameState autoload present")
	_expect(ps != null, "ProceduralShip autoload present")
	_expect(router != null, "SceneRouter autoload present")

	if settings == null or gs == null or ps == null or router == null:
		_report()
		return

	# Save the developer's prior settings.cfg so we can restore it in teardown.
	# We operate on in-memory fields only during the test; save_to_disk is called
	# explicitly only for the round-trip sub-test, and we restore afterward.
	var prior_ship: float = float(settings.get("ship_phase_seconds"))
	var prior_planet: float = float(settings.get("planet_phase_seconds"))
	var prior_band: float = float(settings.get("randomization_band"))
	var prior_pref: int = int(settings.get("jump_destination_pref"))

	# Snapshot the full settings.cfg from disk so teardown can restore it.
	var prior_cfg: ConfigFile = ConfigFile.new()
	var prior_cfg_loaded: bool = prior_cfg.load("user://settings.cfg") == OK

	await _test_defaults(settings)
	await _test_clamps(settings)
	await _test_signals(settings)
	await _test_persist_round_trip(settings)
	await _test_gating_locked(ps, gs)
	await _test_gating_unlocked(ps, gs)
	await _test_130_contract(settings, gs)
	await _test_instant_mode_no_canvas_leak(settings, gs, ps, router)

	# ── teardown: restore developer settings ──────────────────────────────────
	# Restore in-memory to prior values.
	settings.set("ship_phase_seconds", prior_ship)
	settings.set("planet_phase_seconds", prior_planet)
	settings.set("randomization_band", prior_band)
	settings.set("jump_destination_pref", prior_pref)

	if prior_cfg_loaded:
		# Overwrite the file back to exactly what was there before we touched it.
		prior_cfg.save("user://settings.cfg")
	else:
		# No settings.cfg existed before the test — delete the one we created.
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://settings.cfg"))

	# Also push prior loop values back into GameState so dev gameplay state is clean.
	var gs_ship: float = float(gs.get("SHIP_PHASE_BASE")) if prior_ship == 1800.0 else prior_ship
	gs.set("ship_phase_override", gs_ship if prior_ship != 1800.0 else -1.0)
	gs.set("planet_window_override", prior_planet if prior_planet != 1200.0 else -1.0)

	_report()


# ── 1. Defaults ──────────────────────────────────────────────────────────────

func _test_defaults(settings: Node) -> void:
	print("-- defaults --")
	var ship: float = float(settings.get("ship_phase_seconds"))
	var planet: float = float(settings.get("planet_phase_seconds"))
	var band: float = float(settings.get("randomization_band"))
	var pref: int = int(settings.get("jump_destination_pref"))

	_expect(ship >= 60.0 and ship <= 7200.0,
		"ship_phase_seconds default in valid range [60, 7200]: %.1f" % ship)
	_expect(planet >= 60.0 and planet <= 7200.0,
		"planet_phase_seconds default in valid range [60, 7200]: %.1f" % planet)
	_expect(band >= 0.0 and band <= 0.5,
		"randomization_band default in valid range [0, 0.5]: %.3f" % band)
	_expect(pref >= 0, "jump_destination_pref default >= 0: %d" % pref)


# ── 2. Clamps ────────────────────────────────────────────────────────────────

func _test_clamps(settings: Node) -> void:
	print("-- clamps --")

	# ship_phase_seconds: clamp to [60, 7200].
	settings.call("set_ship_phase_seconds", -999.0)
	_expect(is_equal_approx(float(settings.get("ship_phase_seconds")), 60.0),
		"ship_phase_seconds clamped to min 60 when -999 given")

	settings.call("set_ship_phase_seconds", 99999.0)
	_expect(is_equal_approx(float(settings.get("ship_phase_seconds")), 7200.0),
		"ship_phase_seconds clamped to max 7200 when 99999 given")

	# planet_phase_seconds: clamp to [60, 7200].
	settings.call("set_planet_phase_seconds", 0.0)
	_expect(is_equal_approx(float(settings.get("planet_phase_seconds")), 60.0),
		"planet_phase_seconds clamped to min 60 when 0 given")

	settings.call("set_planet_phase_seconds", 8000.0)
	_expect(is_equal_approx(float(settings.get("planet_phase_seconds")), 7200.0),
		"planet_phase_seconds clamped to max 7200 when 8000 given")

	# randomization_band: clamp to [0, 0.5].
	settings.call("set_randomization_band", -1.0)
	_expect(is_equal_approx(float(settings.get("randomization_band")), 0.0),
		"randomization_band clamped to min 0 when -1.0 given")

	settings.call("set_randomization_band", 1.0)
	_expect(is_equal_approx(float(settings.get("randomization_band")), 0.5),
		"randomization_band clamped to max 0.5 when 1.0 given")

	# Reset to defaults for subsequent tests.
	settings.set("ship_phase_seconds", 1800.0)
	settings.set("planet_phase_seconds", 1200.0)
	settings.set("randomization_band", 0.20)


# ── 3. Signals ───────────────────────────────────────────────────────────────

func _test_signals(settings: Node) -> void:
	print("-- signals --")

	# NOTE: GDScript lambdas capture locals BY VALUE — a closure that writes a
	# captured bool mutates its own copy, never the outer var. Capture a Dictionary
	# (reference type) so the flag is visible after the signal fires.
	var fired: Dictionary = {"ship": false, "planet": false, "band": false, "pref": false}

	settings.ship_phase_seconds_changed.connect(func(_v: float) -> void: fired["ship"] = true)
	settings.planet_phase_seconds_changed.connect(func(_v: float) -> void: fired["planet"] = true)
	settings.randomization_band_changed.connect(func(_v: float) -> void: fired["band"] = true)
	settings.jump_destination_pref_changed.connect(func(_v: int) -> void: fired["pref"] = true)

	settings.call("set_ship_phase_seconds", 900.0)
	_expect(fired["ship"], "ship_phase_seconds_changed signal fired")

	settings.call("set_planet_phase_seconds", 600.0)
	_expect(fired["planet"], "planet_phase_seconds_changed signal fired")

	settings.call("set_randomization_band", 0.10)
	_expect(fired["band"], "randomization_band_changed signal fired")

	settings.call("set_jump_destination_pref", 1)
	_expect(fired["pref"], "jump_destination_pref_changed signal fired")

	# Disconnect — no need to clean up lambdas individually, they're fire-once.
	# Reset for subsequent tests.
	settings.set("ship_phase_seconds", 1800.0)
	settings.set("planet_phase_seconds", 1200.0)
	settings.set("randomization_band", 0.20)


# ── 4. Persist round-trip ────────────────────────────────────────────────────
# Sets known values → save_to_disk → corrupt in-memory → load_from_disk → verify.
# Uses a SEPARATE temp path so we never stomp user://settings.cfg. We write to
# the real path here (Settings always uses SETTINGS_PATH) but we snapshot it
# first (done in _run) and restore it last (also in _run).

func _test_persist_round_trip(settings: Node) -> void:
	print("-- persist round-trip --")

	# Write known values to disk.
	settings.set("ship_phase_seconds", 3600.0)
	settings.set("planet_phase_seconds", 480.0)
	settings.set("randomization_band", 0.30)
	settings.set("jump_destination_pref", 0)
	settings.call("save_to_disk")

	# Corrupt in-memory values.
	settings.set("ship_phase_seconds", 0.0)
	settings.set("planet_phase_seconds", 0.0)
	settings.set("randomization_band", 0.0)

	# Reload from disk.
	settings.call("load_from_disk")

	_expect(is_equal_approx(float(settings.get("ship_phase_seconds")), 3600.0),
		"ship_phase_seconds restored from disk: %.1f" % float(settings.get("ship_phase_seconds")))
	_expect(is_equal_approx(float(settings.get("planet_phase_seconds")), 480.0),
		"planet_phase_seconds restored from disk: %.1f" % float(settings.get("planet_phase_seconds")))
	_expect(is_equal_approx(float(settings.get("randomization_band")), 0.30),
		"randomization_band restored from disk: %.3f" % float(settings.get("randomization_band")))

	# Reset in-memory to defaults for subsequent tests (disk will be restored in _run teardown).
	settings.set("ship_phase_seconds", 1800.0)
	settings.set("planet_phase_seconds", 1200.0)
	settings.set("randomization_band", 0.20)


# ── 5. Gating locked (no bridge in rooms_discovered) ─────────────────────────

func _test_gating_locked(ps: Node, gs: Node) -> void:
	print("-- gating locked --")

	gs.call("reset")
	# rooms_discovered is empty after reset — no bridge found.
	_expect(ps.call("is_bridge_discovered") == false,
		"is_bridge_discovered() == false when rooms_discovered is empty")


# ── 6. Gating unlocked (generated bridge room seeded) ─────────────────────────

func _test_gating_unlocked(ps: Node, gs: Node) -> void:
	print("-- gating unlocked --")

	gs.call("reset")
	ps.call("reset")
	await process_frame

	# Seed a generated bridge room using a plain Dictionary — no const read.
	# This mirrors how ProceduralShip._generate_floor inserts rooms.
	var fake_bridge_id: String = "f2_bridge_test"
	var fake_bridge_row: Dictionary = {
		"id": fake_bridge_id,
		"type": "bridge",
		"floor": 2,
		"startX": 0,
		"endX": 400,
		"startY": 0,
		"endY": 400,
		"display_name": "Bridge",
		"key_room": true,
	}
	# Directly insert into the ProceduralShip _rooms dict (same path as generation).
	var rooms_dict: Dictionary = ps.get("_rooms") as Dictionary
	rooms_dict[fake_bridge_id] = fake_bridge_row
	ps.set("_rooms", rooms_dict)

	# Record discovery (as room.gd → GameState.discover_room would).
	gs.call("discover_room", fake_bridge_id, "Bridge")

	_expect(ps.call("is_bridge_discovered") == true,
		"is_bridge_discovered() == true after seeding generated bridge room + discovery")

	# Clean up seeded room.
	rooms_dict.erase(fake_bridge_id)
	ps.set("_rooms", rooms_dict)
	gs.call("reset")
	ps.call("reset")
	await process_frame


# ── 7. #130 contract: set_ship_phase_seconds writes through to GameState ──────
# After Settings.set_ship_phase_seconds(X), GameState.ship_phase_base_seconds()
# must return clampf(X, 60, 7200). This is the single-source path #130 reads.

func _test_130_contract(settings: Node, gs: Node) -> void:
	print("-- #130 contract --")

	# NOTE: #130 (FtlLoop) reads GameState.ship_phase_base_seconds() which returns
	# ship_phase_override when >= 0, else falls back to SHIP_PHASE_BASE.
	# Settings.set_ship_phase_seconds pushes to GameState.ship_phase_override.

	var test_val: float = 2700.0
	settings.call("set_ship_phase_seconds", test_val)

	var resolved: float = float(gs.call("ship_phase_base_seconds"))
	_expect(is_equal_approx(resolved, clampf(test_val, 60.0, 7200.0)),
		"#130 path: after set_ship_phase_seconds(%.0f), ship_phase_base_seconds()=%.0f" % [
			test_val, resolved])

	# Verify over-max clamp propagates too.
	settings.call("set_ship_phase_seconds", 9999.0)
	var resolved_max: float = float(gs.call("ship_phase_base_seconds"))
	_expect(is_equal_approx(resolved_max, 7200.0),
		"#130 path clamp: over-max set resolves to 7200, got %.0f" % resolved_max)

	# band in [0, 0.5].
	settings.call("set_randomization_band", 0.35)
	_expect(float(settings.get("randomization_band")) >= 0.0
		and float(settings.get("randomization_band")) <= 0.5,
		"randomization_band in [0, 0.5] after set_randomization_band(0.35)")

	# Reset.
	settings.set("ship_phase_seconds", 1800.0)
	gs.set("ship_phase_override", -1.0)
	settings.set("randomization_band", 0.20)


# ── 8. BridgeConsole instant_mode: _on_interact adds no CanvasLayer ───────────

func _test_instant_mode_no_canvas_leak(
		settings: Node, gs: Node, ps: Node, router: Node) -> void:
	print("-- instant_mode no canvas leak --")

	router.set("instant_mode", true)

	# Seed a discovered bridge so the gating check passes.
	gs.call("reset")
	ps.call("reset")
	await process_frame

	var fake_id: String = "f2_bridge_gate_test"
	var fake_row: Dictionary = {
		"id": fake_id, "type": "bridge", "floor": 2,
		"startX": 0, "endX": 400, "startY": 0, "endY": 400,
		"display_name": "Bridge", "key_room": true,
	}
	var rmap: Dictionary = ps.get("_rooms") as Dictionary
	rmap[fake_id] = fake_row
	ps.set("_rooms", rmap)
	gs.call("discover_room", fake_id, "Bridge")

	# Instantiate a BridgeConsole and call _on_interact.
	var BridgeConsoleScript: Script = load("res://scripts/bridge_console.gd")
	var console: StaticBody3D = StaticBody3D.new()
	console.set_script(BridgeConsoleScript)
	root.add_child(console)

	var child_count_before: int = root.get_child_count()
	console.call("_on_interact", null)
	var child_count_after: int = root.get_child_count()

	_expect(child_count_after == child_count_before,
		"instant_mode: _on_interact adds no CanvasLayer child to /root")

	console.queue_free()

	# Restore.
	rmap.erase(fake_id)
	ps.set("_rooms", rmap)
	gs.call("reset")
	ps.call("reset")
	router.set("instant_mode", false)
	await process_frame


# ── helpers ───────────────────────────────────────────────────────────────────

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
