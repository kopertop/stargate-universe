extends SceneTree

# Phase A flow smoke test. Exercises GameState's mutators, room discovery,
# the F5 / F9 save round-trip, and verifies the autoload registry is intact.
# The Phase A loop is: arrive in gate room → read consoles → step through the
# exit archway → return. No kino, no breach, no quarters in this slice.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/e1_flow.gd

const EXPECTED_AUTOLOADS: Array[String] = [
	"Audio", "TestCapture", "GameState", "SceneRouter", "KinoRemote", "EpisodeWrap",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== phase-a flow smoke test ===")

	_verify_autoload_registry()

	var gs_script: Script = load("res://scripts/game_state.gd") as Script
	_expect(gs_script != null, "load GameState script")
	if gs_script == null:
		_report()
		return

	var gs: Node = Node.new()
	gs.set_script(gs_script)
	gs.name = "GameState"
	root.add_child(gs)

	gs.reset()
	_expect(gs.health == gs.MAX_HEALTH, "reset: health == MAX_HEALTH")
	_expect(gs.oxygen == gs.MAX_OXYGEN, "reset: oxygen == MAX_OXYGEN")
	_expect(gs.rooms_discovered.is_empty(), "reset: rooms cleared")
	_expect(gs.log_entries.is_empty(), "reset: log cleared")
	_expect(gs.episode_complete == false, "reset: episode not complete")

	gs.damage(35.0)
	_expect(gs.health == 65.0, "damage(35) drops health to 65")
	gs.heal_full()
	_expect(gs.health == gs.MAX_HEALTH, "heal_full restores to MAX_HEALTH")

	gs.consume_oxygen(20.0)
	_expect(gs.oxygen == 80.0, "consume_oxygen(20) drops to 80")
	gs.restore_oxygen(100.0)
	_expect(gs.oxygen == gs.MAX_OXYGEN, "restore_oxygen full caps at MAX")

	gs.discover_room("gate_room", "Gate Room")
	gs.discover_room("gate_room", "Gate Room")
	_expect(gs.rooms_discovered.size() == 1, "discover_room is idempotent")
	gs.discover_room("corridor", "Destiny Main Corridor")
	_expect(gs.rooms_discovered.size() == 2, "second room discovered")

	# F5 quicksave path (no scene path set → save is refused, not silent failure).
	gs.current_scene_path = ""
	gs.save_game("", Vector3.ZERO, 0.0)
	# save_game with empty scene still writes — semantic check is current_scene_path
	# gating only inside _quicksave (the F5 handler). Direct save_game writes whatever.
	_expect(gs.has_save(), "save_game writes file regardless")
	gs.wipe_save()
	_expect(not gs.has_save(), "wipe_save removes file")

	# Round-trip a save with meaningful payload, then reset + reload via the
	# JSON parser path (load_and_resume schedules a scene change, so we call
	# the parser pieces directly here for the smoke test).
	gs.discover_room("gate_room", "Gate Room")
	gs.set_objective("Find a way off this ship")
	gs.add_log("Quicksave round-trip line")
	gs.save_game("res://scenes/gate_room.tscn", Vector3(1.5, 1.05, 10.0), 0.5)
	_expect(gs.has_save(), "save_game writes payload")

	# Reset state and replay the read leg of load_and_resume's logic.
	gs.reset()
	_expect(gs.rooms_discovered.is_empty(), "post-reset: rooms cleared")
	var file: FileAccess = FileAccess.open(gs.SAVE_PATH, FileAccess.READ)
	_expect(file != null, "save file readable")
	if file != null:
		var raw: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(raw)
		_expect(parsed is Dictionary, "save parses to dictionary")
		if parsed is Dictionary:
			var data: Dictionary = parsed
			_expect(String(data.get("scene", "")) == "res://scenes/gate_room.tscn", "saved scene preserved")
			var pos: Array = data.get("pos", [])
			_expect(pos.size() == 3 and float(pos[0]) == 1.5, "saved position preserved")
			_expect(float(data.get("yaw", 0.0)) == 0.5, "saved yaw preserved")
			var log_arr: Array = data.get("log_entries", [])
			_expect(log_arr.size() >= 1, "saved log entries preserved")

	gs.wipe_save()
	_expect(not gs.has_save(), "post-test wipe cleared file")

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
