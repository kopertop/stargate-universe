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
	{
		"path": "res://scenes/planet.tscn",
		"requires": [
			"Player",
			"View/SpringArm/Camera",
			"HUDLayer/HUD",
			"World",
			"FromShipGate",
			"World/PlanetGround",
			"World/PlanetReturnStargate",
			"World/PlanetReturnGate",
			"World/LimeNode1",
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
	"eli_quarters": ["KinoPickup"],
	"engineering_bay": ["PowerConsole"],
	"breached_section_south": ["ShuttleDoorPanel", "ShuttleCrate1", "ShuttleCrate2", "ShuttleCrate3"],
	"control_interface_room": ["DrRush"],
	"south_corridor": ["CO2Scrubber"],
}

var _failures: Array[String] = []
var _passes: int = 0
# Autoloads ARE registered by project.godot even when launched with `-s`, but
# they don't run their own `_ready()` chain before _initialize fires here.
# Cache them once via /root/<name>.
var _ship_layout: Node
var _game_state: Node
var _inventory: Node


func _initialize() -> void:
	_ship_layout = root.get_node_or_null("ShipLayout")
	_game_state = root.get_node_or_null("GameState")
	_inventory = root.get_node_or_null("Inventory")
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
	await _check_kino_dispenser()
	await _check_gate_room_phase_e_crew()
	await _check_post_scout_gate()
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
		if path == "res://scenes/gate_room.tscn":
			_check_gate_room_spawn(inst)
			_check_gate_room_tableau(inst)
			_check_scott_repeat_dialogue(inst)
	root.remove_child(inst)
	inst.free()


func _check_gate_room_spawn(inst: Node) -> void:
	var player := inst.get_node_or_null("Player") as Node3D
	if player == null:
		_fail("res://scenes/gate_room.tscn", "Player is not a Node3D")
		return
	var forward: Vector3 = -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		_fail("res://scenes/gate_room.tscn", "Player forward vector is zero")
		return
	var dot: float = forward.normalized().dot(Vector3(0.0, 0.0, -1.0))
	if dot > 0.8:
		print("  OK (FromGate default spawn faces away from gate)")
		_passes += 1
	else:
		_fail("res://scenes/gate_room.tscn",
			"FromGate default spawn faces the wrong way (dot=%.2f)" % dot)


func _check_gate_room_tableau(inst: Node) -> void:
	var young := inst.get_node_or_null("World/ColonelYoung") as Node3D
	var james := inst.get_node_or_null("World/LtJames") as Node3D
	var park := inst.get_node_or_null("World/DrPark") as Node3D
	if young == null:
		_fail("res://scenes/gate_room.tscn", "Colonel Young tableau node missing")
		return
	if james == null:
		_fail("res://scenes/gate_room.tscn", "Lt James tableau node missing")
		return
	if park != null:
		_fail("res://scenes/gate_room.tscn", "Dr Park should not be in the gate-room medic tableau")
		return
	if young.is_in_group("interactable"):
		_fail("res://scenes/gate_room.tscn", "Colonel Young should not be interactable while unconscious")
		return
	if not james.is_in_group("interactable"):
		_fail("res://scenes/gate_room.tscn", "Lt James should be the talkable medic")
		return
	if String(james.get("met_flag")) != "":
		_fail("res://scenes/gate_room.tscn", "Lt James should not write undefined quest flags")
		return
	if young.get_node_or_null("FaceOverride") == null:
		_fail("res://scenes/gate_room.tscn", "Colonel Young X_X face override missing")
		return
	var to_young: Vector3 = young.global_position - james.global_position
	to_young.y = 0.0
	var forward: Vector3 = -james.global_transform.basis.z
	forward.y = 0.0
	if to_young.length() < 0.01 or forward.length() < 0.01:
		_fail("res://scenes/gate_room.tscn", "Lt James facing check has zero vector")
		return
	var dot: float = forward.normalized().dot(to_young.normalized())
	if dot <= 0.8:
		_fail("res://scenes/gate_room.tscn",
			"Lt James should face Colonel Young (dot=%.2f)" % dot)
		return
	print("  OK (medic tableau: Young unconscious, Lt James only talkable and facing him)")
	_passes += 1


func _check_scott_repeat_dialogue(inst: Node) -> void:
	var scott := inst.get_node_or_null("World/LtScott")
	if scott == null:
		_fail("res://scenes/gate_room.tscn", "Lt Scott node missing")
		return
	var was_met: bool = _game_state.get("met_scott") == true
	_game_state.set("met_scott", true)
	var tree: Array = scott.call("_active_dialogue_tree")
	_game_state.set("met_scott", was_met)
	if tree.is_empty():
		_fail("res://scenes/gate_room.tscn", "Lt Scott repeat dialogue tree missing")
		return
	var line: String = String((tree[0] as Dictionary).get("text", ""))
	if line != "Hurry up Eli, find Rush!":
		_fail("res://scenes/gate_room.tscn",
			"Lt Scott repeat line wrong: %s" % line)
		return
	print("  OK (Lt Scott repeat dialogue respects met_scott state)")
	_passes += 1


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
	# Clean slate per room so leftover state from a prior room's mission
	# wiring (e.g. hydroponics flips air_crisis_started) doesn't change what
	# this room builds — control_interface_room omits Rush during the crisis.
	_game_state.call("reset")
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
			if _game_state.get("quarters_found") == true:
				print("  OK (Bed.interact → quarters_found=true)")
				_passes += 1
			else:
				_fail("%s [quarters_room_1]" % ROOM_SCENE,
					"Bed.interact() did not set GameState.quarters_found")
		"eli_quarters":
			var kino: Node = inst.get_node("KinoPickup")
			kino.call("interact", null)
			# KinoPickup.interact awaits Eli's naming monologue before flipping
			# the flag. Headless short-circuits the waits but the await still
			# yields one frame; poll briefly so we see the flip after resume.
			var waited: int = 0
			while not bool(_inventory.call("has", "kino_remote")) and waited < 30:
				await process_frame
				waited += 1
			if bool(_inventory.call("has", "kino_remote")):
				print("  OK (KinoPickup.interact → kino remote in inventory)")
				_passes += 1
			else:
				_fail("%s [eli_quarters]" % ROOM_SCENE,
					"KinoPickup.interact() did not add the kino remote to Inventory")
		"engineering_bay":
			var console: Node = inst.get_node("PowerConsole")
			console.call("interact", null)
			if _game_state.get("elevator_repaired") == true:
				print("  OK (PowerConsole.interact → elevator_repaired=true)")
				_passes += 1
			else:
				_fail("%s [engineering_bay]" % ROOM_SCENE,
					"PowerConsole.interact() did not set GameState.elevator_repaired")
		"breached_section_south":
			# Loot the small-fuse crate, then repair the door panel → breach sealed.
			inst.get_node("ShuttleCrate2").call("interact", null)
			if not bool(_inventory.call("has", "small_fuse")):
				_fail("%s [breached_section_south]" % ROOM_SCENE,
					"ShuttleCrate2.interact() did not grant the Small Fuse")
			inst.get_node("ShuttleDoorPanel").call("interact", null)
			var sealed: Array = _game_state.get("breaches_sealed")
			if sealed.size() > 0:
				print("  OK (crate→small fuse, panel→breaches_sealed=", sealed, ")")
				_passes += 1
			else:
				_fail("%s [breached_section_south]" % ROOM_SCENE,
					"ShuttleDoorPanel.interact() did not record a sealed breach after the fuse")
		"south_corridor":
			# The reveal scene is Dr Rush's WoW dialog (player-driven), so drive
			# the GameState completion directly here — the panel only redirects
			# to Rush before diagnosis. This asserts the folded scene outcome:
			# diagnosed + FTL drop + gate auto-dialed.
			_game_state.set("met_scott", true)
			_game_state.set("met_rush", true)
			_game_state.set("eli_quarters_visited", true)
			_inventory.call("set_count", "kino_remote", 1)
			_game_state.call("advance_air_quest")
			_game_state.call("start_air_crisis")
			_game_state.call("diagnose_life_support")
			_game_state.call("seal_breach", "breach_a")
			_game_state.call("complete_scrubber_scene")
			var diag_ok: bool = _game_state.get("scrubber_diagnosed") == true
			var ftl_ok: bool = _game_state.get("ftl_drop_triggered") == true
			var dial_ok: bool = _game_state.get("lime_planet_dialed") == true
			if diag_ok and ftl_ok and dial_ok:
				print("  OK (complete_scrubber_scene → diagnosed + FTL drop + gate dialed)")
				_passes += 1
			else:
				_fail("%s [south_corridor]" % ROOM_SCENE,
					"complete_scrubber_scene flags not set (diag=%s ftl=%s dial=%s)" % [diag_ok, ftl_ok, dial_ok])


# BFS the connection graph (data/room_connections.json) from gate_room and
# assert every mission-critical destination is reachable. Catches data-level
# regressions like the one where east_corridor → north_corridor was misdeclared
# as "-z" instead of "+x", silently making the Kino room unreachable.
func _check_connection_reachability() -> void:
	print("\n=== connection graph reachability ===")
	const MUST_REACH: Array[String] = [
		"east_corridor",                # corridor watch (Sgt Greer)
		"breached_section_south",       # jammed door + seal switch (air-crisis objective)
		"sealed_section_north",         # locked trap section (blocked-door beat)
		"control_interface_room",       # Dr Rush
		"eli_quarters",                 # kino pickup (Eli's room)
		"engineering_bay",              # power console — gates upper deck
		"quarters_room_1",              # Crew Quarters Alpha (upper deck)
		"south_corridor",               # CO2 scrubber (Phase D)
		"hydroponics",                  # upper-deck room, elevator-gated
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


# Phase E: once Eli has reported to the gate (Brody's "no MALP" beat), the
# quarters grows a Kino dispenser. Boot eli_quarters with reported_to_gate set
# and assert the dispenser spawns + grants an orb on interact.
func _check_kino_dispenser() -> void:
	print("\n=== Phase E: Kino dispenser (eli_quarters) ===")
	_game_state.call("reset")
	_game_state.set("reported_to_gate", true)
	_game_state.set("next_room_id", "eli_quarters")
	var packed := load(ROOM_SCENE) as PackedScene
	if packed == null:
		_fail(ROOM_SCENE, "load() returned null for dispenser check")
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame
	var disp: Node = inst.get_node_or_null("KinoDispenser")
	if disp == null:
		_fail("%s [eli_quarters]" % ROOM_SCENE, "KinoDispenser did not spawn with reported_to_gate=true")
	else:
		var before: int = int(_inventory.call("count", "kino_orb"))
		disp.call("interact", null)
		var after: int = int(_inventory.call("count", "kino_orb"))
		if after == before + 1:
			print("  OK (KinoDispenser.interact → kino_orb %d→%d)" % [before, after])
			_passes += 1
		else:
			_fail("%s [eli_quarters]" % ROOM_SCENE,
				"KinoDispenser.interact() did not grant an orb (%d→%d)" % [before, after])
	root.remove_child(inst)
	await process_frame
	inst.free()
	_game_state.call("reset")


# Phase E: Brody + Rush + Park cluster at the gate console during the scout
# window. Boot gate_room with quest_step in that window and assert all three
# uniquely-named tableau NPCs spawn. instant_mode guards the arrival cinematic.
func _check_gate_room_phase_e_crew() -> void:
	print("\n=== Phase E: gate-room scout crew (Brody/Rush/Park) ===")
	var router: Node = root.get_node_or_null("SceneRouter")
	var prev_instant: bool = router != null and router.get("instant_mode") == true
	if router != null:
		router.set("instant_mode", true)
	_game_state.call("reset")
	# FETCH_KINO sits inside the scout window but trips neither arrival cinematic
	# (those gate on GO_TO_GATE / SCOUT_KINO), so the crew spawns cleanly.
	_game_state.set("quest_step", "fetch_kino")  # GameState.QUEST_FETCH_KINO
	var packed := load("res://scenes/gate_room.tscn") as PackedScene
	if packed == null:
		_fail("res://scenes/gate_room.tscn", "load() returned null for Phase E crew check")
		if router != null:
			router.set("instant_mode", prev_instant)
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame
	var missing: Array[String] = []
	for n in ["World/GateBrody", "World/GateRush", "World/GatePark"]:
		if inst.get_node_or_null(n) == null:
			missing.append(n)
	if missing.size() > 0:
		_fail("res://scenes/gate_room.tscn", "Phase E crew missing: " + ", ".join(missing))
	else:
		print("  OK (GateBrody/GateRush/GatePark spawned for scout window)")
		_passes += 1
	root.remove_child(inst)
	await process_frame
	inst.free()
	_game_state.call("reset")
	if router != null:
		router.set("instant_mode", prev_instant)


# Phase E return: at MINE_LIME (after the Kino scout) Lt Scott is supportive
# rather than nagging "find Rush", and the gate crew stays present so Rush can
# brief the away party. instant_mode guards the briefing cinematic.
func _check_post_scout_gate() -> void:
	print("\n=== Phase E: post-scout gate (supportive Scott + crew) ===")
	var router: Node = root.get_node_or_null("SceneRouter")
	var prev_instant: bool = router != null and router.get("instant_mode") == true
	if router != null:
		router.set("instant_mode", true)
	_game_state.call("reset")
	_game_state.set("quest_step", "mine_lime")
	_game_state.set("kino_scout_done", true)
	_game_state.set("away_party_briefed", true)  # suppress the one-shot dialog
	var packed := load("res://scenes/gate_room.tscn") as PackedScene
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame
	var scott := inst.get_node_or_null("World/LtScott")
	var rush := inst.get_node_or_null("World/GateRush")
	var ok: bool = true
	if scott == null:
		_fail("res://scenes/gate_room.tscn", "LtScott missing at MINE_LIME")
		ok = false
	else:
		var tree: Array = scott.get("repeat_dialogue_tree")
		var line: String = String((tree[0] as Dictionary).get("text", "")) if tree.size() > 0 else ""
		if line.find("find Rush") != -1 or line == "":
			_fail("res://scenes/gate_room.tscn", "Lt Scott still nags 'find Rush' at MINE_LIME: '%s'" % line)
			ok = false
	if rush == null:
		_fail("res://scenes/gate_room.tscn", "Gate crew (GateRush) absent at MINE_LIME — no one to brief the away party")
		ok = false
	if ok:
		print("  OK (Scott supportive + gate crew present for the away-party briefing)")
		_passes += 1
	root.remove_child(inst)
	await process_frame
	inst.free()
	_game_state.call("reset")
	if router != null:
		router.set("instant_mode", prev_instant)


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
