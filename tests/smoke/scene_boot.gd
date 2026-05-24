extends SceneTree

# Smoke test: load each gameplay scene headlessly, assert critical nodes
# resolve, then exit. Catches broken NodePaths, missing autoloads,
# parse errors, and stale signal connections without needing GDUnit4.
#
# Boots the two author-built scenes (title, gate_room) plus scenes/room.tscn
# once per non-gate row in data/ship_layout.json (priming next_room_id so
# room.gd dispatches to the matching RoomBuilder branch).
#
# Run with:
#   godot --headless --quit-after 200 -s res://tests/smoke/scene_boot.gd

const STATIC_SCENES: Array = [
	{
		"path": "res://scenes/title.tscn",
		"requires": [
			"Background",
			"LeftColumn/MenuList/ContinueButton",
			"LeftColumn/MenuList/NewGameButton",
			"LeftColumn/MenuList/SettingsButton",
			"LeftColumn/MenuList/ExitButton",
			"SettingsOverlay",
		],
	},
	{
		"path": "res://scenes/gate_room.tscn",
		"requires": [
			"Player",
			"View",
			"View/SpringArm/Camera",
			"HUDLayer/HUD",
			"World",
			"FromGate",
			"FromCorridor",
			"AmbientHum",
			"GateActiveLoop",
			"GateShutdown",
		],
	},
]

const ROOM_SCENE: String = "res://scenes/room.tscn"

# Every non-gate row in ship_layout.json should boot via room.tscn and produce
# at least the three shell containers under World/: a Floor StaticBody3D, a
# Walls StaticBody3D (holding all four wall colliders), and a Ceiling
# StaticBody3D. Per-template accents (corridor strips, hydroponics grow-strip,
# etc.) push the count higher but vary, so the floor we assert against is 3.
# The gate-room template is a RoomBuilder no-op (artisan scene), so we skip it.
const PROCEDURAL_ROOM_REQUIRES: Array = [
	"Player",
	"View/SpringArm/Camera",
	"HUDLayer/HUD",
	"World",
	"Markers",
]

# Mission-critical rooms must spawn their named Interactable as a child of the
# room scene root. If these vanish, episode 1 becomes uncompletable — quarters
# can't be marked, kino can't be picked up, the breach can't be sealed.
const ROOM_INTERACTABLE_REQUIRES: Dictionary = {
	"quarters_room_1": ["Bed"],
	"kino_room": ["KinoPickup"],
	"east_corridor": ["HullBreach", "HullSealSwitch"],
	"control_interface_room": ["DrRush"],
}

var _failures: Array[String] = []
var _passes: int = 0
# Autoloads ARE registered by project.godot even when launched with `-s`, but
# they don't run their own `_ready()` chain before _initialize fires here.
# Cache them once via /root/<name>.
var _ship_layout: Node
var _game_state: Node


func _initialize() -> void:
	_ship_layout = root.get_node_or_null("ShipLayout")
	_game_state = root.get_node_or_null("GameState")
	if _ship_layout == null:
		_fail("autoload", "ShipLayout not found at /root/ShipLayout (check project.godot)")
	if _game_state == null:
		_fail("autoload", "GameState not found at /root/GameState (check project.godot)")
	if _ship_layout == null or _game_state == null:
		_report()
		return
	print("=== scene_boot smoke test ===")
	# Suspend to a deferred call: SceneTree-script `_initialize` runs BEFORE
	# the first frame ticks, so any `_ready()` we'd otherwise rely on is queued.
	# Calling `call_deferred` lets us re-enter once frames are flowing.
	call_deferred("_run_checks")


func _run_checks() -> void:
	# Now a frame has ticked: `_ready()` fires synchronously on add_child again,
	# matching gameplay behaviour. Without this hop, room.gd's `_ready` was
	# queued and World stayed empty when the test inspected it.
	for spec in STATIC_SCENES:
		var path: String = spec["path"]
		var requires: Array = spec["requires"]
		_check_scene(path, requires)
	await _check_procedural_rooms()
	_check_connection_reachability()
	_report()


# In `-s` mode, `_ready()` doesn't fire synchronously during add_child — it's
# queued until the first process_frame tick. Await one frame so geometry-
# building `_ready` (room.gd) has actually run before we inspect.
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
	await process_frame
	var missing: Array[String] = []
	for p in required_paths:
		if not inst.has_node(p):
			missing.append(p)
	if missing.size() > 0:
		_fail(path, "missing nodes: " + ", ".join(missing))
	else:
		print("  OK (", required_paths.size(), " nodes resolved)")
		_passes += 1
	root.remove_child(inst)
	inst.free()


# Boot scenes/room.tscn once per non-gate ShipLayout row, asserting World/
# got procedural Floor/Walls/Ceiling.
func _check_procedural_rooms() -> void:
	print("\n=== procedural rooms (room.tscn × ShipLayout rows) ===")
	var rows: Array = _ship_layout.call("all_rooms")
	if rows.is_empty():
		_fail(ROOM_SCENE, "ShipLayout.all_rooms() returned no rows")
		return
	for row in rows:
		var id: String = String(row.get("id", ""))
		if id == "" or id == "gate_room":
			continue
		await _check_procedural_room(id)


func _check_procedural_room(room_id: String) -> void:
	print("\n[room] ", room_id)
	var packed := load(ROOM_SCENE) as PackedScene
	if packed == null:
		_fail(ROOM_SCENE, "load() returned null")
		return
	_game_state.set("next_room_id", room_id)
	var inst := packed.instantiate()
	if inst == null:
		_fail(ROOM_SCENE, "instantiate() returned null for room_id=%s" % room_id)
		return
	root.add_child(inst)
	await process_frame
	var missing: Array[String] = []
	for p in PROCEDURAL_ROOM_REQUIRES:
		if not inst.has_node(p):
			missing.append(p)
	if missing.size() > 0:
		_fail("%s [%s]" % [ROOM_SCENE, room_id], "missing nodes: " + ", ".join(missing))
	else:
		var world: Node = inst.get_node("World")
		var world_kids: int = world.get_child_count()
		var has_shell: bool = (world.has_node("Floor")
			and world.has_node("Walls")
			and world.has_node("Ceiling"))
		if not has_shell:
			_fail("%s [%s]" % [ROOM_SCENE, room_id],
				"World missing one of Floor/Walls/Ceiling (kids=%d)" % world_kids)
		else:
			print("  OK (", PROCEDURAL_ROOM_REQUIRES.size(),
				" nodes, World has ", world_kids, " geometry children)")
			_passes += 1
		if ROOM_INTERACTABLE_REQUIRES.has(room_id):
			var want: Array = ROOM_INTERACTABLE_REQUIRES[room_id]
			var miss_int: Array[String] = []
			for n in want:
				if not inst.has_node(n):
					miss_int.append(n)
			if miss_int.size() > 0:
				_fail("%s [%s]" % [ROOM_SCENE, room_id],
					"missing mission interactable(s): " + ", ".join(miss_int))
			else:
				print("  OK (mission interactables: ", ", ".join(want), ")")
				_passes += 1
				_check_mission_wiring(inst, room_id)
	root.remove_child(inst)
	await process_frame
	inst.free()


# Drives each room's mission Interactable directly and asserts the matching
# GameState flag flipped. Catches wiring gaps (wrong script attached,
# missing `super()`, signal disconnected) that e1_flow.gd's direct-state
# tests can't see.
func _check_mission_wiring(inst: Node, room_id: String) -> void:
	_game_state.call("reset")
	match room_id:
		"quarters_room_1":
			var bed: Node = inst.get_node("Bed")
			bed.call("interact", null)
			if bool(_game_state.get("quarters_found")):
				print("  OK (Bed.interact → quarters_found=true)")
				_passes += 1
			else:
				_fail("%s [quarters_room_1]" % ROOM_SCENE,
					"Bed.interact() did not set GameState.quarters_found")
		"kino_room":
			var kino: Node = inst.get_node("KinoPickup")
			kino.call("interact", null)
			# KinoPickup.interact awaits Eli's naming monologue before flipping
			# the flag. Headless short-circuits the waits but the await still
			# yields one frame; poll briefly so we see the flip after resume.
			var waited: int = 0
			while not bool(_game_state.get("kino_acquired")) and waited < 30:
				await process_frame
				waited += 1
			if bool(_game_state.get("kino_acquired")):
				print("  OK (KinoPickup.interact → kino_acquired=true)")
				_passes += 1
			else:
				_fail("%s [kino_room]" % ROOM_SCENE,
					"KinoPickup.interact() did not set GameState.kino_acquired")
		"east_corridor":
			var switch: Node = inst.get_node("HullSealSwitch")
			switch.call("interact", null)
			var sealed: Array = _game_state.get("breaches_sealed")
			if sealed.size() > 0:
				print("  OK (HullSealSwitch.interact → breaches_sealed=", sealed, ")")
				_passes += 1
			else:
				_fail("%s [east_corridor]" % ROOM_SCENE,
					"HullSealSwitch.interact() did not record a sealed breach")


# BFS the connection graph (data/room_connections.json) from gate_room and
# assert every mission-critical destination is reachable. Catches data-level
# regressions like the one where east_corridor → north_corridor was misdeclared
# as "-z" instead of "+x", silently making the Kino room unreachable.
func _check_connection_reachability() -> void:
	print("\n=== connection graph reachability ===")
	const MUST_REACH: Array[String] = [
		"east_corridor",                # hull breach lives here
		"control_interface_room",       # Dr Rush
		"kino_room",                    # kino pickup
		"quarters_room_1",              # Eli's bunk
	]
	var connections: Dictionary = _load_connections()
	if connections.is_empty():
		_fail("connections", "data/room_connections.json missing or unparseable")
		return
	# Build an undirected adjacency map — room.gd auto-stamps reverse edges, so
	# traversal must mirror that to model in-game reachability.
	var graph: Dictionary = {}
	for from_id: String in connections.keys():
		for edge: Dictionary in connections[from_id] as Array:
			var to_id: String = String(edge.get("to", ""))
			if to_id == "":
				continue
			graph.get_or_add(from_id, []).append(to_id)
			graph.get_or_add(to_id, []).append(from_id)
	# BFS from gate_room.
	var seen: Dictionary = {"gate_room": true}
	var queue: Array[String] = ["gate_room"]
	while not queue.is_empty():
		var node: String = queue.pop_front()
		for neighbour: String in graph.get(node, []) as Array:
			if not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)
	for target: String in MUST_REACH:
		if seen.has(target):
			print("  OK  ", target, " reachable from gate_room")
			_passes += 1
		else:
			_fail("connections", "%s unreachable from gate_room (broken adjacency)" % target)


func _load_connections() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://data/room_connections.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _fail(scene: String, reason: String) -> void:
	print("  FAIL: ", reason)
	_failures.append("%s — %s" % [scene, reason])


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
