extends SceneTree

# Save editor. Headless SceneTree CLI; instantiates SaveStore directly (a
# `-s` run skips autoloads). Mutates fields in a slot so we can pre-stage a
# save into any scene / room / quest step / player position, then launch the
# game and hit Continue to land exactly there. Defaults to the live player
# root (user://saves/); override with --save-root=<path>.
#
# Usage (user args after `++`):
#   --slot <id> --set <dot.path>=<value>   mutate a field, rewrite + refresh meta
#   --from <a> --to <b>                    clone slot a into slot b
#   --slot <id> --scenario <name>          apply a named preset to a slot
#
# Dot paths resolve into the snapshot dict:
#   scene_path                       top-level scene path
#   player.pos / player.yaw          player transform (pos coerces "x,y,z")
#   systems.<id>.<field>             any registered-system field
# Value coercion: int / float / bool / "x,y,z" -> [x,y,z] / else string.
#
# Scenarios are minimal field bundles applied on top of an existing snapshot.

const SCENARIOS: Dictionary = {
	"at-control-room": {
		"scene_path": "res://scenes/room.tscn",
		"systems.game_state.current_room_id": "control_interface_room",
		"systems.game_state.quest_step": "talk_rush",
	},
	"mid-air-crisis": {
		"scene_path": "res://scenes/room.tscn",
		"systems.game_state.current_room_id": "breached_section_south",
		"systems.game_state.quest_step": "find_scrubber",
		"systems.game_state.air_crisis_started": "true",
	},
}


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var root: String = _arg_value(args, "--save-root=", "user://saves/")
	var store: SaveStore = SaveStore.new(root)

	var code: int = 0
	if _has(args, "--from") and _has(args, "--to"):
		code = _clone(store, _positional(args, "--from"), _positional(args, "--to"))
	elif _has(args, "--scenario"):
		code = _apply_scenario(store, _positional(args, "--slot"), _positional(args, "--scenario"))
	elif _has(args, "--set"):
		code = _set_field(store, _positional(args, "--slot"), _positional(args, "--set"))
	else:
		print("usage: save_edit.gd ++ --slot <id> --set <path>=<val> | --from <a> --to <b> | --slot <id> --scenario <name> [--save-root=<path>]")
		code = 2
	quit(code)


func _set_field(store: SaveStore, slot: String, assignment: String) -> int:
	if slot == "":
		printerr("--set requires --slot <id>")
		return 2
	if not assignment.contains("="):
		printerr("--set expects <dot.path>=<value>")
		return 2
	var eq: int = assignment.find("=")
	var path: String = assignment.substr(0, eq)
	var raw: String = assignment.substr(eq + 1)
	var data: Dictionary = store.read_snapshot(slot)
	if data.is_empty():
		printerr("no readable save in slot '%s'" % slot)
		return 1
	if not _set_dot_path(data, path, _coerce(raw)):
		printerr("could not resolve path '%s'" % path)
		return 1
	return _persist(store, slot, data, path)


func _apply_scenario(store: SaveStore, slot: String, name: String) -> int:
	if slot == "":
		printerr("--scenario requires --slot <id>")
		return 2
	if not SCENARIOS.has(name):
		printerr("unknown scenario '%s' (known: %s)" % [name, ", ".join(SCENARIOS.keys())])
		return 2
	var data: Dictionary = store.read_snapshot(slot)
	if data.is_empty():
		printerr("no readable save in slot '%s' (need a base save to edit)" % slot)
		return 1
	var preset: Dictionary = SCENARIOS[name]
	for path in preset.keys():
		_set_dot_path(data, path, _coerce(String(preset[path])))
	return _persist(store, slot, data, "scenario:" + name)


func _clone(store: SaveStore, from_slot: String, to_slot: String) -> int:
	if from_slot == "" or to_slot == "":
		printerr("--from and --to both required")
		return 2
	var data: Dictionary = store.read_snapshot(from_slot)
	if data.is_empty():
		printerr("no readable save in slot '%s'" % from_slot)
		return 1
	return _persist(store, to_slot, data, "clone<-" + from_slot)


func _persist(store: SaveStore, slot: String, data: Dictionary, what: String) -> int:
	var meta: Dictionary = store.build_meta_from_snapshot(slot, data)
	# Stamp a fresh timestamp so an edited slot sorts as most-recent.
	meta["timestamp"] = int(Time.get_unix_time_from_system())
	data["timestamp"] = meta["timestamp"]
	if not store.rewrite_snapshot(slot, data, meta):
		printerr("write failed for slot '%s'" % slot)
		return 1
	print("%s -> slot '%s' (%s)" % [what, slot, store.primary_path(slot)])
	return 0


# Walk a dot path into nested dicts, creating intermediate dicts as needed,
# and set the leaf. Returns false only if an intermediate is a non-dict.
func _set_dot_path(root: Dictionary, path: String, value: Variant) -> bool:
	var parts: PackedStringArray = path.split(".")
	var node: Dictionary = root
	for i in range(parts.size() - 1):
		var key: String = parts[i]
		if not node.has(key) or not (node[key] is Dictionary):
			node[key] = {}
		node = node[key]
	node[parts[parts.size() - 1]] = value
	return true


# Coerce a raw string into the most specific type it represents.
func _coerce(raw: String) -> Variant:
	if raw == "true":
		return true
	if raw == "false":
		return false
	if raw.is_valid_int():
		return int(raw)
	if raw.is_valid_float():
		return float(raw)
	if raw.contains(","):
		var parts: PackedStringArray = raw.split(",")
		var all_num: bool = true
		for p in parts:
			if not p.strip_edges().is_valid_float():
				all_num = false
				break
		if all_num:
			var out: Array = []
			for p in parts:
				out.append(float(p.strip_edges()))
			return out
	return raw


# ---- arg helpers --------------------------------------------------------

func _has(args: PackedStringArray, flag: String) -> bool:
	return args.has(flag)


func _positional(args: PackedStringArray, flag: String) -> String:
	var idx: int = args.find(flag)
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1]
	return ""


func _arg_value(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback
