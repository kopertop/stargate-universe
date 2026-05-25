extends SceneTree

# Smoke test for the quest-tracker + Kino route systems. Exercises:
#   • ShipLayout.path_through_rooms / next_room_toward — BFS over
#     data/room_connections.json (with reverse edges mirrored).
#   • GameState.QUEST_TARGETS lookups via quest_target().
#   • The kino_remote route resolution helper (_active_route_target):
#     custom override wins over quest target; same-room returns "".
#
# Run with:
#   godot --headless --quit-after 200 -s res://tests/smoke/quest_waypoint.gd
#
# Pure-logic test — does NOT instance scenes / Node3D. The diamond's actual
# in-world positioning is exercised by scene_boot via the room.gd path.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== quest waypoint + route smoke test ===")

	# --- ShipLayout BFS -----------------------------------------------------
	var sl_script: Script = load("res://scripts/ship_layout.gd") as Script
	_expect(sl_script != null, "load ShipLayout script")
	if sl_script == null:
		_report()
		return
	var sl: Node = Node.new()
	sl.set_script(sl_script)
	sl.name = "ShipLayout"
	root.add_child(sl)
	# Headless: -s skips _ready, so load explicitly.
	sl.call("_load")
	sl.call("_load_connections")

	# Same room => single-element path.
	var same: PackedStringArray = sl.call("path_through_rooms", "gate_room", "gate_room")
	_expect(same.size() == 1 and same[0] == "gate_room", "same-room path is [gate_room]")

	# Empty input rejected.
	_expect((sl.call("path_through_rooms", "", "gate_room") as PackedStringArray).size() == 0, "empty from_id rejected")
	_expect((sl.call("path_through_rooms", "gate_room", "") as PackedStringArray).size() == 0, "empty to_id rejected")

	# Known mission-critical pair: gate_room → control_interface_room.
	# Path should start at gate_room, end at control_interface_room, and the
	# first hop should land on the corridor connector.
	var p1: PackedStringArray = sl.call("path_through_rooms", "gate_room", "control_interface_room")
	_expect(p1.size() >= 2, "gate→control path non-empty")
	if p1.size() >= 2:
		_expect(p1[0] == "gate_room", "gate→control starts at gate_room")
		_expect(p1[p1.size() - 1] == "control_interface_room", "gate→control ends at control_interface_room")

	var hop1: String = sl.call("next_room_toward", "gate_room", "control_interface_room")
	_expect(hop1 == "stargate_corridor_east_connector", "first hop gate→control is east connector, got %s" % hop1)

	# Cross-deck path (gate_room → hydroponics on deck 1). Should pass through
	# the elevator hub. We don't pin every intermediate, just that the path
	# exists and contains the elevator transition rooms.
	var p2: PackedStringArray = sl.call("path_through_rooms", "gate_room", "hydroponics")
	_expect(p2.size() >= 3, "gate→hydroponics multi-hop path exists")
	var p2_arr: Array = []
	for r in p2:
		p2_arr.append(r)
	_expect(p2_arr.has("elevator_north"), "path includes elevator_north")
	_expect(p2_arr.has("elevator_room_floor_1"), "path includes elevator_room_floor_1")

	# Unreachable room id should return an empty path.
	var p_bad: PackedStringArray = sl.call("path_through_rooms", "gate_room", "no_such_room")
	_expect(p_bad.size() == 0, "unknown destination returns empty path")

	# --- GameState quest target table --------------------------------------
	var gs_script: Script = load("res://scripts/game_state.gd") as Script
	_expect(gs_script != null, "load GameState script")
	if gs_script == null:
		_report()
		return
	var gs: Node = Node.new()
	gs.set_script(gs_script)
	gs.name = "GameState"
	root.add_child(gs)

	# QUEST_FIND_REST targets eli_quarters (room-level — no specific anchor).
	var t_rest: Dictionary = gs.call("quest_target", gs.QUEST_FIND_REST)
	_expect(String(t_rest.get("room", "")) == "eli_quarters", "QUEST_FIND_REST room = eli_quarters")
	_expect(String(t_rest.get("anchor", "")) == "", "QUEST_FIND_REST anchor empty (room-level)")

	# QUEST_FIND_KINO targets eli_quarters / KinoPickup (static lookup; the step
	# is no longer in the prologue chain but the target still resolves).
	var t_kino: Dictionary = gs.call("quest_target", gs.QUEST_FIND_KINO)
	_expect(String(t_kino.get("room", "")) == "eli_quarters", "QUEST_FIND_KINO room = eli_quarters")
	_expect(String(t_kino.get("anchor", "")) == "KinoPickup", "QUEST_FIND_KINO anchor = KinoPickup")

	# QUEST_FIND_RUSH targets control_interface_room / DrRush.
	var t_rush: Dictionary = gs.call("quest_target", gs.QUEST_FIND_RUSH)
	_expect(String(t_rush.get("room", "")) == "control_interface_room", "QUEST_FIND_RUSH room = control_interface_room")
	_expect(String(t_rush.get("anchor", "")) == "DrRush", "QUEST_FIND_RUSH anchor = DrRush")

	# QUEST_REPAIR_SCRUBBER targets hydroponics / CO2Scrubber.
	var t_scrub: Dictionary = gs.call("quest_target", gs.QUEST_REPAIR_SCRUBBER)
	_expect(String(t_scrub.get("room", "")) == "hydroponics", "QUEST_REPAIR_SCRUBBER room = hydroponics")
	_expect(String(t_scrub.get("anchor", "")) == "CO2Scrubber", "QUEST_REPAIR_SCRUBBER anchor = CO2Scrubber")

	# Offworld step has empty room (waypoint hidden).
	var t_mine: Dictionary = gs.call("quest_target", gs.QUEST_MINE_LIME)
	_expect(String(t_mine.get("room", "")) == "", "QUEST_MINE_LIME room = '' (offworld)")

	# set_current_room emits + persists.
	var current_room_signals: Array = []
	gs.connect("current_room_changed", func(rid: String) -> void: current_room_signals.append(rid))
	gs.call("set_current_room", "gate_room")
	_expect(gs.current_room_id == "gate_room", "set_current_room sets current_room_id")
	_expect(current_room_signals.size() == 1 and current_room_signals[0] == "gate_room", "current_room_changed emits room id")
	# Repeated set to same room is a no-op.
	gs.call("set_current_room", "gate_room")
	_expect(current_room_signals.size() == 1, "set_current_room is no-op when room unchanged")

	# --- Route resolution mirror (logic-only — no UI build) ----------------
	# Replicate _active_route_target locally so we test the SAME rule kino_remote
	# uses (custom override beats quest target; same-room collapses to "").
	gs.call("set_current_room", "gate_room")
	# With quest_step = QUEST_TALK_SCOTT (default after reset), target is
	# gate_room (Lt Scott). Player is already in gate_room → no route.
	gs.reset()
	gs.call("set_current_room", "gate_room")
	_expect(_active_route_target(gs, "") == "", "no route when player already in quest-target room")

	# Different target: simulate quest advance to QUEST_FIND_RUSH while still
	# in gate_room → route to control_interface_room.
	gs._set_quest_step(gs.QUEST_FIND_RUSH)
	_expect(_active_route_target(gs, "") == "control_interface_room", "quest route = control_interface_room")

	# Custom override wins even when quest is in another direction.
	_expect(_active_route_target(gs, "hydroponics") == "hydroponics", "custom override beats quest target")

	# Custom override to current room collapses to "" (no route).
	_expect(_active_route_target(gs, "gate_room") == "", "custom override to current room = no route")

	_report()


func _active_route_target(gs: Node, custom: String) -> String:
	# Mirrors kino_remote._active_route_target precedence rules.
	var target: String = custom
	if target == "":
		var quest: Dictionary = gs.call("quest_target")
		target = String(quest.get("room", ""))
	var from_id: String = gs.current_room_id
	if from_id == "" or target == "" or target == from_id:
		return ""
	return target


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d" % _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("failures (%d):" % _failures.size())
		for f in _failures:
			print("  - ", f)
		print("RESULT: FAIL")
		quit(1)
