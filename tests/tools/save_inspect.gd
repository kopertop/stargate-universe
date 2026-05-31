extends SceneTree

# Read-only save inspector. Headless SceneTree CLI; instantiates SaveStore
# directly (a `-s` run skips autoloads, so we cannot touch the SaveManager
# autoload). Defaults to the live player root (user://saves/); override with
# --save-root=<path>.
#
# Usage (user args after `++`):
#   --list                 table of every slot + metadata
#   --dump <slot>          pretty-print the full save.json for a slot
#   --validate <slot|all>  parse + version + required-key check; nonzero exit
#
# See tests/tools/save.sh for the convenience wrapper.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var root: String = _arg_value(args, "--save-root=", "user://saves/")
	var store: SaveStore = SaveStore.new(root)

	var code: int = 0
	if _has(args, "--list"):
		_list(store)
	elif _has(args, "--dump"):
		code = _dump(store, _positional(args, "--dump"))
	elif _has(args, "--validate"):
		code = _validate(store, _positional(args, "--validate"))
	else:
		print("usage: save_inspect.gd ++ --list | --dump <slot> | --validate <slot|all> [--save-root=<path>]")
		code = 2
	quit(code)


func _list(store: SaveStore) -> void:
	var slots: Array[Dictionary] = store.list_slots()
	print("root: %s" % store.saves_root)
	if slots.is_empty():
		print("(no saves)")
		return
	print("%-10s | %-10s | %-9s | %s" % ["slot", "playtime", "ts", "objective / room"])
	print("-".repeat(72))
	for meta in slots:
		var playtime: float = float(meta.get("playtime_seconds", 0.0))
		var obj: String = String(meta.get("objective", ""))
		var room: String = String(meta.get("room_id", ""))
		print("%-10s | %-10s | %-9d | %s [%s]" % [
			String(meta.get("slot_id", "?")),
			_fmt_clock(playtime),
			int(meta.get("timestamp", 0)),
			obj, room,
		])


func _dump(store: SaveStore, slot: String) -> int:
	if slot == "":
		printerr("--dump requires a slot id")
		return 2
	var data: Dictionary = store.read_snapshot(slot)
	if data.is_empty():
		printerr("no readable save in slot '%s'" % slot)
		return 1
	print(JSON.stringify(data, "\t"))
	return 0


func _validate(store: SaveStore, target: String) -> int:
	if target == "":
		printerr("--validate requires a slot id or 'all'")
		return 2
	var slots: Array[String] = []
	if target == "all":
		for id in SaveStore.all_slot_ids():
			if store.has_slot(id):
				slots.append(id)
	else:
		slots.append(target)
	var bad: int = 0
	for slot in slots:
		var problems: Array[String] = _validate_slot(store, slot)
		if problems.is_empty():
			print("OK   %s" % slot)
		else:
			bad += 1
			print("BAD  %s — %s" % [slot, ", ".join(problems)])
	if slots.is_empty():
		print("(no slots to validate)")
	return 1 if bad > 0 else 0


func _validate_slot(store: SaveStore, slot: String) -> Array[String]:
	var problems: Array[String] = []
	if not store.has_slot(slot):
		problems.append("no save on disk")
		return problems
	var data: Dictionary = store.read_snapshot(slot)
	if data.is_empty():
		problems.append("snapshot unreadable / not a JSON object")
		return problems
	for key in SaveStore.REQUIRED_SNAPSHOT_KEYS:
		if not data.has(key):
			problems.append("missing key '%s'" % key)
	var version: int = int(data.get("version", 0))
	if version <= 0:
		problems.append("invalid version %d" % version)
	return problems


# ---- helpers ------------------------------------------------------------

func _has(args: PackedStringArray, flag: String) -> bool:
	return args.has(flag)


# Returns the token following `flag` (e.g. --dump manual_1 -> "manual_1").
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


func _fmt_clock(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
