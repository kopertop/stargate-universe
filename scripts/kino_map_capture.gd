extends Node

# @no-save: dev/test utility that snapshots Kino map PNGs from CLI args.
# Never invoked during normal gameplay; no persistent state.
#
# Visual smoke capture for the Kino Remote map. Gated on a `--cli-arg
# kino_map_capture` flag; otherwise the autoload self-frees. Reads
# `scenario=NAME` and `out=PATH` user args, scripts a deterministic
# GameState (which rooms are discovered, which doors traversed, current
# room, locked state), opens the Kino map, and saves the rendered frame
# as a PNG so we can diff the result against the concept art.

const FRAMES_BEFORE_CAPTURE: int = 12

# Each scenario is a self-contained setup function that mutates GameState
# in-place before the map is opened. Add a new scenario by adding a method
# and an entry here.
var _scenarios: Dictionary = {
	"fog":     "_setup_fog",
	"partial": "_setup_partial",
	"locked":  "_setup_locked",
	"full":    "_setup_full",
}

var _scenario_name: String = ""
var _out_path: String = ""
var _frames: int = 0
var _captured: bool = false


func _ready() -> void:
	if not _capture_requested():
		queue_free()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("scenario="):
			_scenario_name = arg.substr(9)
		elif arg.begins_with("out="):
			_out_path = arg.substr(4)
	if _scenario_name == "":
		_scenario_name = "full"
	if _out_path == "":
		_out_path = "user://kino_map_%s.png" % _scenario_name
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	# Reset clears every flag — start from a known state every time so
	# scenarios don't bleed into each other.
	GameState.reset()
	GameState.current_scene_path = "res://scenes/room.tscn"
	if not _scenarios.has(_scenario_name):
		push_error("[kino_map_capture] unknown scenario '%s'" % _scenario_name)
		get_tree().quit(1)
		return
	call(_scenarios[_scenario_name])
	# Decipher every discovered room so the map labels render in readable English,
	# not the Ancient glyph font — this capture compares ship LAYOUT against the
	# concept art, so glyph names would only obscure the comparison. (In real play
	# a room stays glyph'd on the map until the on-foot player walks in.)
	for rid: String in GameState.rooms_discovered:
		GameState.decipher_room(rid)
	# KinoRemote autoload owns the UI tree. Force-open even if the kino_remote
	# item is absent from Inventory (the capture is allowed to peek).
	Inventory.set_count("kino_remote", 1)
	if KinoRemote.has_method("_init_ui"):
		KinoRemote.call("_init_ui")
	if KinoRemote.has_method("_open_remote"):
		KinoRemote.call("_open_remote")
	# Re-trigger a refresh after current_room_id is set so the player
	# marker lands in the right room.
	if KinoRemote.has_method("_refresh"):
		KinoRemote.call("_refresh")


func _process(_delta: float) -> void:
	if _captured or _scenario_name == "":
		return
	_frames += 1
	if _frames < FRAMES_BEFORE_CAPTURE:
		return
	_captured = true
	_capture_and_quit()


func _capture_and_quit() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(_out_path)
	var abs_path: String = ProjectSettings.globalize_path(_out_path)
	print("[kino_map_capture] scenario=%s saved=%s err=%s abs=%s" % [
		_scenario_name, _out_path, err, abs_path,
	])
	get_tree().quit(0 if err == OK else 2)


# ---- Scenarios -----------------------------------------------------------

# Just stepped off the gate. Only one room known. The map should show
# gate_room alone with three unopened door pips (E / N / S walls).
func _setup_fog() -> void:
	GameState.discover_room("gate_room", "Gate Room")
	GameState.current_room_id = "gate_room"


# Two corridors explored beyond the gate. One door traversed (gate_room →
# east_connector). Mix of unopened + dimmed pips.
func _setup_partial() -> void:
	GameState.discover_room("gate_room", "Gate Room")
	GameState.discover_room("stargate_corridor_east_connector", "East Connector")
	GameState.discover_room("east_corridor", "East Corridor")
	GameState.mark_door_traversed("gate_room", "stargate_corridor_east_connector")
	GameState.mark_door_traversed("stargate_corridor_east_connector", "east_corridor")
	GameState.current_room_id = "east_corridor"


# Locked-door scenario: player has reached cr_corridor_2 (where the
# elevator door north sits). Elevator stays locked → pip renders amber.
func _setup_locked() -> void:
	GameState.discover_room("gate_room", "Gate Room")
	GameState.discover_room("stargate_corridor_east_connector", "East Connector")
	GameState.discover_room("east_corridor", "East Corridor")
	GameState.discover_room("north_corridor", "North Corridor")
	GameState.discover_room("control_approach_north", "Control Approach")
	GameState.discover_room("control_interface_room", "Control Interface Room")
	GameState.discover_room("cr_corridor_2", "Corridor")
	GameState.discover_room("elevator_north", "Elevator North")
	GameState.mark_door_traversed("gate_room", "stargate_corridor_east_connector")
	GameState.mark_door_traversed("stargate_corridor_east_connector", "east_corridor")
	GameState.mark_door_traversed("east_corridor", "north_corridor")
	GameState.mark_door_traversed("north_corridor", "control_approach_north")
	GameState.mark_door_traversed("control_approach_north", "control_interface_room")
	GameState.mark_door_traversed("control_interface_room", "cr_corridor_2")
	# Elevator door is locked (elevator_repaired = false). Sets the amber pip.
	GameState.elevator_repaired = false
	GameState.current_room_id = "cr_corridor_2"


# Maximum exploration: most floor-0 rooms discovered + both floors visible.
# Best diff against the concept image since it shows the full ship.
func _setup_full() -> void:
	for room_id in [
		"gate_room",
		"stargate_corridor_east_connector",
		"stargate_corridor_north_connector",
		"stargate_corridor_south_connector",
		"east_corridor",
		"north_corridor",
		"south_corridor",
		"control_approach_north",
		"control_interface_room",
		"cr_corridor_2",
		"engineering_bay",
		"eli_quarters",
		"elevator_north",
		"elevator_room_floor_1",
		"hydroponics",
		"quarters_room_1",
	]:
		var row: Dictionary = ProceduralShip.room(room_id)
		var display: String = String(row.get("name", room_id))
		GameState.discover_room(room_id, display)
	# Traverse roughly the prologue → air-crisis path so half the pips
	# render as dimmed-outlines.
	var traversed_pairs: Array = [
		["gate_room", "stargate_corridor_east_connector"],
		["stargate_corridor_east_connector", "east_corridor"],
		["east_corridor", "north_corridor"],
		["north_corridor", "control_approach_north"],
		["control_approach_north", "control_interface_room"],
		["control_interface_room", "cr_corridor_2"],
		["cr_corridor_2", "eli_quarters"],
	]
	for pair in traversed_pairs:
		GameState.mark_door_traversed(pair[0], pair[1])
	GameState.elevator_repaired = false  # Keep the locked pip visible.
	GameState.current_room_id = "eli_quarters"
	# Publish a status reading so POWER / O2 / HULL render non-OFFLINE for
	# this scenario (proves the live wiring works).
	GameState.set_power_percent(74.0)
	GameState.set_hull_percent(96.0)


func _capture_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.contains("kino_map_capture"):
			return true
	return false
