extends SceneTree

# Smoke test: load each gameplay scene headlessly, assert critical nodes
# resolve, then exit. Catches broken NodePaths, missing autoloads,
# parse errors, and stale signal connections without needing GDUnit4.
#
# Run with:
#   godot --headless --quit-after 200 -s res://tests/smoke/scene_boot.gd

const SCENES: Array = [
	{
		"path": "res://scenes/title.tscn",
		"requires": ["Background", "Frame/Stack/StartButton", "Frame/Stack/QuitButton"],
	},
	{
		"path": "res://scenes/gate_room.tscn",
		"requires": ["Player", "View", "View/SpringArm/Camera", "HUDLayer/HUD"],
	},
	{
		"path": "res://scenes/destiny_corridor.tscn",
		"requires": ["Player", "View/SpringArm/Camera", "QuartersDoor", "BreachDoor", "GateRoomDoor", "ObservationDoor", "FromGateRoom", "FromQuarters", "FromBreach"],
	},
	{
		"path": "res://scenes/eli_quarters.tscn",
		"requires": ["Player", "View/SpringArm/Camera", "Bed", "KinoPickup", "CorridorDoor", "FromCorridor"],
	},
	{
		"path": "res://scenes/hull_breach.tscn",
		"requires": ["Player", "View/SpringArm/Camera", "SealSwitch", "CorridorDoor", "AlarmLight", "VentParticles"],
	},
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== scene_boot smoke test ===")
	for spec in SCENES:
		var path: String = spec["path"]
		var requires: Array = spec["requires"]
		_check_scene(path, requires)
	_report()


# Synchronous — _ready() fires during add_child(), so static node graphs
# (and anything spawned in _ready) are available immediately on return.
func _check_scene(path: String, required_paths: Array) -> void:
	print("\n[scene] ", path)
	var packed := load(path) as PackedScene
	if packed == null:
		_fail(path, "load() returned null")
		return
	var inst := packed.instantiate()
	if inst == null:
		_fail(path, "instantiate() returned null")
		return
	root.add_child(inst)
	var missing: Array[String] = []
	for p in required_paths:
		if not inst.has_node(p):
			missing.append(p)
	if missing.size() > 0:
		_fail(path, "missing nodes: " + ", ".join(missing))
	else:
		print("  OK (", required_paths.size(), " nodes resolved)")
		_passes += 1
	# Synchronous free — using queue_free leaves the instance alive until
	# end-of-frame, but our main loop never runs (we're in _initialize),
	# so frees pile up and per-frame _process callbacks (AmbientHum audio,
	# physics, kenney_room generators) keep ticking when the loop finally
	# starts after _report() — preventing the quit() from being honored.
	# free() tears the subtree down immediately.
	root.remove_child(inst)
	inst.free()


func _fail(scene: String, reason: String) -> void:
	print("  FAIL: ", reason)
	_failures.append("%s — %s" % [scene, reason])


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes, " / ", SCENES.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
