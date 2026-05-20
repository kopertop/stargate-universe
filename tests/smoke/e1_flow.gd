extends SceneTree

# E1 vertical slice flow test. Drives GameState through the win condition
# and asserts the episode_completed signal fires, every state mutator works.
#
# Note: -s flag bypasses normal SceneTree startup, so [autoload] entries from
# project.godot are NOT instantiated. We manually load the GameState script
# (the only autoload that holds win-condition state) and verify project.godot
# itself declares the expected autoload set.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/e1_flow.gd

const EXPECTED_AUTOLOADS: Array[String] = [
	"Audio", "TestCapture", "GameState", "SceneRouter", "KinoRemote", "EpisodeWrap",
]

var _signal_fired: bool = false
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== e1_flow smoke test ===")

	# 1. Verify project.godot declares every autoload we depend on.
	_verify_autoload_registry()

	# 2. Manually instantiate GameState (autoloads are bypassed in -s mode).
	var gs_script: Script = load("res://scripts/game_state.gd") as Script
	_expect(gs_script != null, "load GameState script")
	if gs_script == null:
		_report()
		return

	var gs: Node = Node.new()
	gs.set_script(gs_script)
	gs.name = "GameState"
	root.add_child(gs)

	gs.episode_completed.connect(_on_episode_complete)

	# Reset to clean E1 start.
	gs.reset()
	_expect(gs.health == gs.MAX_HEALTH, "reset: health == MAX_HEALTH")
	_expect(gs.oxygen == gs.MAX_OXYGEN, "reset: oxygen == MAX_OXYGEN")
	_expect(gs.kino_acquired == false, "reset: kino not acquired")
	_expect(gs.quarters_found == false, "reset: quarters not found")
	_expect(gs.breaches_sealed.size() == 0, "reset: no breaches sealed")
	_expect(gs.episode_complete == false, "reset: episode not complete")

	# Damage + heal cycle.
	gs.damage(35.0)
	_expect(gs.health == 65.0, "damage(35) drops health to 65")
	gs.heal_full()
	_expect(gs.health == gs.MAX_HEALTH, "heal_full restores to MAX_HEALTH")

	# Oxygen drain + restore.
	gs.consume_oxygen(20.0)
	_expect(gs.oxygen == 80.0, "consume_oxygen(20) drops to 80")
	gs.restore_oxygen(100.0)
	_expect(gs.oxygen == gs.MAX_OXYGEN, "restore_oxygen full caps at MAX")

	# Room discovery is idempotent.
	gs.discover_room("gate_room", "Gate Room")
	gs.discover_room("gate_room", "Gate Room")
	_expect(gs.rooms_discovered.size() == 1, "discover_room is idempotent")

	# Win condition: must require ALL THREE (kino, quarters, breach).
	gs.acquire_kino()
	gs.check_episode_complete()
	_expect(gs.episode_complete == false, "kino alone does NOT complete episode")

	gs.mark_quarters_found()
	gs.check_episode_complete()
	_expect(gs.episode_complete == false, "kino + quarters does NOT complete episode")

	gs.seal_breach("compartment_14b")
	gs.check_episode_complete()
	_expect(gs.episode_complete == true, "kino + quarters + breach completes episode")
	_expect(_signal_fired == true, "episode_completed signal fires")

	# Idempotency: re-completing must not re-emit.
	_signal_fired = false
	gs.check_episode_complete()
	_expect(_signal_fired == false, "episode_completed does not double-fire")

	# Seal a second breach restores oxygen (the in-scene healing guarantee).
	gs.consume_oxygen(50.0)
	gs.seal_breach("compartment_99x")
	_expect(gs.oxygen == gs.MAX_OXYGEN, "seal_breach restores oxygen")

	# Cleanup.
	root.remove_child(gs)
	gs.free()

	_report()


func _verify_autoload_registry() -> void:
	var file := FileAccess.open("res://project.godot", FileAccess.READ)
	if file == null:
		_expect(false, "open project.godot")
		return
	var contents := file.get_as_text()
	file.close()
	for name in EXPECTED_AUTOLOADS:
		var pattern := "%s=\"*res://" % name
		_expect(contents.find(pattern) != -1, "autoload registered: " + name)


func _on_episode_complete() -> void:
	_signal_fired = true


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
