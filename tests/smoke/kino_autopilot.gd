extends SceneTree

# Headless verification of the Kino-drone auto-search patrol logic added to
# scripts/kino_drone.gd. Exercises 1 / 2 / 3 drone variations plus dedicated
# tests for the avoid-radius coordination, the discovery sweep, and the random
# fallback when no undiscovered lime remains.
#
# Runs via call_deferred("_run") + `await process_frame` between fixture
# spawns so node tree-entry (which is deferred in `-s` SceneTree mode until a
# frame ticks) completes before the autopilot reads `global_position`. Same
# pattern as tests/shots/cutscene_shot.gd.

# Loaded at runtime — NOT preloaded — because kino_drone.gd references
# autoload globals (`SceneRouter.instant_mode`) which aren't visible at the
# top-level compile pass of a SceneTree-extending main-loop script. preload
# would fail with "Compile Error: Identifier not found: SceneRouter" and
# `.new()` would then error with "Nonexistent function 'new' in base 'GDScript'"
# because the script never loaded. load() defers the dependency compile until
# after _initialize, by which point autoloads are in the tree.
var KinoDroneScript: Script = null

const AUTO_AVOID_RADIUS: float = 50.0     # mirrors KinoDrone constant
const AUTO_DETECT_RANGE: float = 24.0     # mirrors KinoDrone constant

# Inline mock for a lime deposit. Real ResourceNode has heavy `_ready` side
# effects (Interactable collision setup, GameState autoload reads); a small
# Node3D that quacks like a lime deposit is enough for the autopilot logic.
class FakeLime extends Node3D:
	var _discovered: bool = false
	var depleted: bool = false

	func is_discovered() -> bool:
		return _discovered

	func _mark_discovered(_announce: bool = false) -> void:
		_discovered = true


var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== kino autopilot patrol tests ===")
	# Runtime load (not preload) — see KinoDroneScript declaration comment.
	KinoDroneScript = load("res://scripts/kino_drone.gd")
	if KinoDroneScript == null:
		print("SHOT_ERROR could not load KinoDrone script")
		quit(1)
		return
	# Skip KinoDrone's heavy build helpers (collision shape, body mesh,
	# camera rig, overlay HUD) — `_ready` short-circuits when
	# SceneRouter.instant_mode is true. Without this, the build helpers
	# run on every spawned drone and (with multiple drones) leak state /
	# add child nodes that break subsequent KinoDroneScript.new() calls.
	# Use the runtime path — autoload identifiers aren't visible at parse
	# time inside `-s` SceneTree scripts (compile error: "Identifier not
	# found: SceneRouter"), so go through the node tree instead.
	var router: Node = root.get_node_or_null("SceneRouter")
	if router != null:
		router.set("instant_mode", true)
	# Wait one frame so autoload tree-entry settles before fixture spawns.
	await process_frame

	await _test_single_drone()
	await _test_two_drones_split_lime()
	await _test_three_drones_split_lime()
	await _test_avoid_radius()
	await _test_discovery_sweep()
	await _test_random_fallback_no_lime()
	await _test_random_fallback_all_discovered()

	_report()


# ─── helpers ─────────────────────────────────────────────────────────────

func _spawn_lime(pos: Vector3, name_suffix: String) -> Node3D:
	var lime: Node3D = FakeLime.new()
	lime.name = "TestLime_" + name_suffix
	lime.position = pos
	lime.add_to_group("lime_node")
	# Auto-search now scans the shared "discoverable" group (lime + POIs alike).
	lime.add_to_group("discoverable")
	root.add_child(lime)
	return lime


func _spawn_drone(pos: Vector3, name_suffix: String) -> Node:
	var d: Node = KinoDroneScript.new()
	d.name = "TestDrone_" + name_suffix
	d.set("launch_in_ship", false)
	(d as Node3D).position = pos
	root.add_child(d)
	return d


func _start_and_get_target(drone: Node) -> Vector3:
	drone.call("start_autopilot")
	var t: Variant = drone.get("_autopilot_target")
	if t is Vector3:
		return t
	return Vector3.INF


# Planar distance (Y zeroed) — autopilot decisions are XZ-only on a flat plane.
func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# Did the drone target this lime (by XZ proximity)?
func _targeted(target: Vector3, lime_pos: Vector3) -> bool:
	return _planar(target, lime_pos) < 8.0


# Free every spawned test node and wait a frame so the EXIT_TREE
# notifications fully process before the next test re-uses the tree.
# Synchronous free() (rather than queue_free()) is critical — queued frees
# would leave prior drones in the patrolling_kino group during the next
# test, contaminating avoid-radius decisions.
func _cleanup() -> void:
	for n in root.get_children():
		if n.name.begins_with("TestDrone_") or n.name.begins_with("TestLime_"):
			root.remove_child(n)
			n.free()
	await process_frame


# ─── test cases ──────────────────────────────────────────────────────────

func _test_single_drone() -> void:
	print("\n--- 1 drone, 3 lime spread ---")
	await _cleanup()
	var lime_a: Node3D = _spawn_lime(Vector3(80, 0, 0), "1A")
	var _lime_b: Node3D = _spawn_lime(Vector3(0, 0, 120), "1B")
	var _lime_c: Node3D = _spawn_lime(Vector3(-150, 0, -150), "1C")
	var drone: Node = _spawn_drone(Vector3.ZERO, "1solo")
	# Frame tick → all add_child operations finalise tree-entry, global_position
	# now reads the values we set on .position.
	await process_frame
	var target: Vector3 = _start_and_get_target(drone)
	_expect(target != Vector3.INF, "single drone: target is a Vector3")
	_expect(drone.is_in_group("patrolling_kino"), "single drone joins patrolling_kino group")
	_expect(drone.get("_autopilot") == true, "single drone flips _autopilot=true")
	# Lime A is closest to the drone — should be the chosen target.
	_expect(_targeted(target, lime_a.global_position),
		"single drone targets the NEAREST undiscovered lime (lime_a)")


func _test_two_drones_split_lime() -> void:
	print("\n--- 2 drones, 2 lime far apart ---")
	await _cleanup()
	var lime_a: Node3D = _spawn_lime(Vector3(100, 0, 0), "2A")
	var lime_b: Node3D = _spawn_lime(Vector3(-100, 0, 0), "2B")
	var d1: Node = _spawn_drone(Vector3(50, 0, 0), "2first")
	var d2: Node = _spawn_drone(Vector3(-50, 0, 0), "2second")
	await process_frame
	var t1: Vector3 = _start_and_get_target(d1)
	var t2: Vector3 = _start_and_get_target(d2)
	_expect(_targeted(t1, lime_a.global_position),
		"drone 1 (near lime_a) targets lime_a")
	_expect(_targeted(t2, lime_b.global_position),
		"drone 2 picks the OTHER lime (lime_b) — coordinated split")
	_expect(_planar(t1, t2) >= AUTO_AVOID_RADIUS,
		"two drones' targets are at least AUTO_AVOID_RADIUS apart")


func _test_three_drones_split_lime() -> void:
	print("\n--- 3 drones, 3 lime equilateral ---")
	await _cleanup()
	var lime_a: Node3D = _spawn_lime(Vector3(0, 0, 80), "3A")
	var lime_b: Node3D = _spawn_lime(Vector3(70, 0, -40), "3B")
	var lime_c: Node3D = _spawn_lime(Vector3(-70, 0, -40), "3C")
	var d1: Node = _spawn_drone(Vector3(0, 0, 60), "3first")
	var d2: Node = _spawn_drone(Vector3(50, 0, -30), "3second")
	var d3: Node = _spawn_drone(Vector3(-50, 0, -30), "3third")
	await process_frame
	var t1: Vector3 = _start_and_get_target(d1)
	var t2: Vector3 = _start_and_get_target(d2)
	var t3: Vector3 = _start_and_get_target(d3)
	_expect(_targeted(t1, lime_a.global_position), "drone 1 targets lime_a")
	_expect(_targeted(t2, lime_b.global_position), "drone 2 targets lime_b")
	_expect(_targeted(t3, lime_c.global_position), "drone 3 targets lime_c")
	_expect(_planar(t1, t2) >= AUTO_AVOID_RADIUS, "t1↔t2 ≥ AUTO_AVOID_RADIUS")
	_expect(_planar(t1, t3) >= AUTO_AVOID_RADIUS, "t1↔t3 ≥ AUTO_AVOID_RADIUS")
	_expect(_planar(t2, t3) >= AUTO_AVOID_RADIUS, "t2↔t3 ≥ AUTO_AVOID_RADIUS")
	_expect(d1.is_in_group("patrolling_kino"), "drone 1 in patrolling_kino")
	_expect(d2.is_in_group("patrolling_kino"), "drone 2 in patrolling_kino")
	_expect(d3.is_in_group("patrolling_kino"), "drone 3 in patrolling_kino")


func _test_avoid_radius() -> void:
	print("\n--- avoid-radius blocks too-close pick ---")
	await _cleanup()
	# Two lime within AUTO_AVOID_RADIUS of each other — only one is legal per
	# drone. Second drone must fall back to the random walker.
	var lime_a: Node3D = _spawn_lime(Vector3(100, 0, 0), "avA")
	var lime_b: Node3D = _spawn_lime(Vector3(120, 0, 10), "avB")
	var d1: Node = _spawn_drone(Vector3(0, 0, 0), "avFirst")
	var d2: Node = _spawn_drone(Vector3(20, 0, 0), "avSecond")
	await process_frame
	_expect(_planar(lime_a.global_position, lime_b.global_position) < AUTO_AVOID_RADIUS,
		"sanity: the two lime are within AUTO_AVOID_RADIUS of each other")
	var t1: Vector3 = _start_and_get_target(d1)
	var t2: Vector3 = _start_and_get_target(d2)
	var d1_on_lime: bool = _targeted(t1, lime_a.global_position) or _targeted(t1, lime_b.global_position)
	_expect(d1_on_lime, "drone 1 targets one of the two lime")
	var d2_on_lime_a: bool = _targeted(t2, lime_a.global_position)
	var d2_on_lime_b: bool = _targeted(t2, lime_b.global_position)
	_expect(not d2_on_lime_a and not d2_on_lime_b,
		"drone 2 abandons both lime (both within AUTO_AVOID_RADIUS of drone 1's pick)")
	_expect(_planar(t1, t2) >= AUTO_AVOID_RADIUS,
		"drone 2's fallback target stays AUTO_AVOID_RADIUS away from drone 1")


func _test_discovery_sweep() -> void:
	print("\n--- discovery sweep marks nearby lime ---")
	await _cleanup()
	var near: Node3D = _spawn_lime(Vector3(7, 0, 7), "sweepNear")     # planar ≈ 9.9 m
	var far: Node3D = _spawn_lime(Vector3(40, 0, 45), "sweepFar")     # planar ≈ 60 m
	var drone: Node = _spawn_drone(Vector3.ZERO, "sweep")
	await process_frame
	drone.call("start_autopilot")
	_expect(near.is_discovered() == false, "near lime starts undiscovered")
	_expect(far.is_discovered() == false, "far lime starts undiscovered")
	drone.call("_detect_nearby_discoverables")
	_expect(near.is_discovered() == true, "near lime flips to discovered after sweep")
	_expect(far.is_discovered() == false, "far lime is OUT of range and stays undiscovered")


func _test_random_fallback_no_lime() -> void:
	print("\n--- fallback: no lime → random target ---")
	await _cleanup()
	var drone: Node = _spawn_drone(Vector3.ZERO, "fallbackNone")
	await process_frame
	var target: Vector3 = _start_and_get_target(drone)
	_expect(target != Vector3.INF, "fallback: target is a Vector3 with no lime present")
	_expect(_planar(target, Vector3.ZERO) > 10.0,
		"fallback: target is at least 10 m from the drone's start position")


func _test_random_fallback_all_discovered() -> void:
	print("\n--- fallback: all lime discovered → random target ---")
	await _cleanup()
	var lime_a: Node3D = _spawn_lime(Vector3(60, 0, 0), "doneA")
	var lime_b: Node3D = _spawn_lime(Vector3(-60, 0, 0), "doneB")
	lime_a.call("_mark_discovered")
	lime_b.call("_mark_discovered")
	var drone: Node = _spawn_drone(Vector3.ZERO, "fallbackDone")
	await process_frame
	var target: Vector3 = _start_and_get_target(drone)
	_expect(not _targeted(target, lime_a.global_position),
		"fallback (all discovered): target is NOT lime_a")
	_expect(not _targeted(target, lime_b.global_position),
		"fallback (all discovered): target is NOT lime_b")


# ─── reporting (matches e1_flow.gd style) ────────────────────────────────

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
