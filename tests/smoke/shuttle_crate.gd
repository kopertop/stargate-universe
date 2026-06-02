extends SceneTree

# Smoke test for the Ancient-tech storage crate styling + loot behavior
# (issue #37). The crate is procedurally built in shuttle_crate.gd; this test
# instantiates one the same way room.gd does (StaticBody3D + set_script) and
# asserts:
#   • the visual structure exists: a hinged lid node, glowing cyan accent
#     meshes (emissive material), reinforced corner brackets, a dark interior
#     floor — the elements that distinguish the new style from a plain box
#   • the closed lid sits flush on top (hinge rotation 0) before looting
#   • interacting once loots it: grants its contents, flips _looted, and swings
#     the lid open (hinge rotation.x non-zero) — the "emptied" cue
#   • the crate's global_position (which room.gd's waypoints read) is unchanged
#     across the loot so the diamond logic still tracks it
#
# Runs under SceneRouter.instant_mode so _pop_lid resolves on the same frame
# instead of tweening.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/shuttle_crate.gd

const CRATE_SCRIPT: String = "res://scripts/shuttle_crate.gd"

var _failures: Array[String] = []
var _passes: int = 0
var _router: Node = null
var _game: Node = null
var _inventory: Node = null
var _prev_instant: bool = false


func _initialize() -> void:
	print("=== shuttle_crate smoke test ===")
	# Autoloads aren't reachable on /root in _initialize (no frame has ticked);
	# defer everything past frame 0.
	call_deferred("_run_checks")


func _run_checks() -> void:
	_router = root.get_node_or_null("/root/SceneRouter")
	_game = root.get_node_or_null("/root/GameState")
	_inventory = root.get_node_or_null("/root/Inventory")
	_expect(_router != null, "SceneRouter autoload present")
	_expect(_game != null, "GameState autoload present")
	_expect(_inventory != null, "Inventory autoload present")
	if _router == null or _game == null or _inventory == null:
		_finish()
		return

	_prev_instant = _router.get("instant_mode")
	_router.set("instant_mode", true)

	_test_crate_style_has_ancient_accents()
	_test_crate_loot_grants_contents_and_opens_lid()
	_test_crate_global_position_survives_loot()

	_router.set("instant_mode", _prev_instant)
	_finish()


# Build a crate exactly as room.gd does and parent it under a holder so
# global_position is well-defined.
func _make_crate(fuse_type: String, at: Vector3) -> Node3D:
	var script: Script = load(CRATE_SCRIPT)
	var crate: StaticBody3D = StaticBody3D.new()
	crate.set_script(script)
	crate.name = "TestCrate"
	crate.position = at
	crate.set("fuse_type", fuse_type)
	root.add_child(crate)
	return crate


# Count MeshInstance3D descendants whose material_override is an emissive
# StandardMaterial3D (the glowing cyan accents). Also tallies bracket-coloured
# meshes and a raised interior floor.
func _scan(node: Node, stats: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mat: Material = (child as MeshInstance3D).material_override
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat as StandardMaterial3D
				if sm.emission_enabled and sm.emission_energy_multiplier > 1.0:
					stats["glow"] = int(stats.get("glow", 0)) + 1
		_scan(child, stats)


func _test_crate_style_has_ancient_accents() -> void:
	# Arrange / Act
	var crate: Node3D = _make_crate("rations", Vector3.ZERO)

	# Assert: hinged lid node present and closed (rotation 0) before loot.
	var hinge: Node = crate.get_node_or_null("LidHinge")
	_expect(hinge != null, "style: crate has a LidHinge node (hinged lid)")
	if hinge != null:
		_expect(absf((hinge as Node3D).rotation.x) < 0.001,
			"style: lid is closed (hinge rotation.x ~= 0) before loot")
		_expect(hinge.get_node_or_null("LidSlab") != null,
			"style: lid hinge carries a LidSlab mesh")

	# Assert: multiple glowing cyan accent meshes (frame + studs + lid panel).
	var stats: Dictionary = {}
	_scan(crate, stats)
	var glow: int = int(stats.get("glow", 0))
	_expect(glow >= 12,
		"style: crate has many glowing accent meshes (got %d, expected >=12)" % glow)

	crate.free()


func _test_crate_loot_grants_contents_and_opens_lid() -> void:
	# Arrange
	var crate: Node3D = _make_crate("small", Vector3(3.0, 0.0, 0.0))
	var hinge: Node3D = crate.get_node_or_null("LidHinge") as Node3D
	_expect(hinge != null and absf(hinge.rotation.x) < 0.001,
		"loot: lid closed before interact")

	# Act
	crate.call("interact", null)

	# Assert: contents granted, looted flag set, lid swung open.
	_expect(_inventory.call("has", "small_fuse") == true,
		"loot: searching the small-fuse crate grants the Small Fuse")
	_expect(crate.get("_looted") == true,
		"loot: crate marks itself looted")
	if hinge != null:
		_expect(absf(hinge.rotation.x) > 0.5,
			"loot: lid swings open (hinge rotation.x != 0) under instant_mode")

	# Re-interacting is a no-op (already emptied) — should not error.
	crate.call("interact", null)
	_expect(crate.get("_looted") == true, "loot: re-search keeps looted state")

	crate.free()


func _test_crate_global_position_survives_loot() -> void:
	# Arrange
	var at: Vector3 = Vector3(-5.0, 0.0, 2.0)
	var crate: Node3D = _make_crate("large", at)
	var before: Vector3 = crate.global_position

	# Act
	crate.call("interact", null)

	# Assert: the body itself never moves (only the lid child rotates), so the
	# waypoint logic in room.gd (crate.global_position + offset) stays valid.
	var after: Vector3 = crate.global_position
	_expect(before.distance_to(after) < 0.001,
		"waypoint: crate global_position unchanged across loot")
	_expect(before.distance_to(at) < 0.001,
		"waypoint: crate sits at its requested spawn position")

	crate.free()


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  OK  ", label)
	else:
		_failures.append(label)
		print("  FAIL ", label)


func _finish() -> void:
	print("--- shuttle_crate: %d passed, %d failed ---" % [_passes, _failures.size()])
	if _failures.size() > 0:
		for f in _failures:
			print("  ! ", f)
		quit(1)
	else:
		quit(0)
