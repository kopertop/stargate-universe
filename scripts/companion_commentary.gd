class_name CompanionCommentary
extends RefCounted

# Companion commentary system for planetary away missions.
#
# Loads data/squad_commentary.json and provides context-aware dialogue lines
# for squad members (Greer, Dr Park). Lines are keyed by trigger + context.
# The system is a pure data helper — it returns lines and GameState.say()
# handles the actual narrative_added emission (same pattern as cold_open_lines).
#
# Headless-safe: loads from file on first call, falls back to empty dict.
# No scene dependencies. Used by planet.gd and companion.gd.

const COMMENTARY_PATH: String = "res://data/squad_commentary.json"

var _lines: Array = []
var _loaded: bool = false

func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(COMMENTARY_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var arr: Variant = (parsed as Dictionary).get("commentary", [])
	if arr is Array:
		_lines = arr

# Return the first commentary line matching the given trigger + optional
# context/command/objective filters. Returns empty Dictionary if none match.
func get_line(trigger: String, opts: Dictionary = {}) -> Dictionary:
	_ensure_loaded()
	for entry in _lines:
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		if String(e.get("trigger", "")) != trigger:
			continue
		if opts.has("command") and String(e.get("command", "")) != String(opts["command"]):
			continue
		if opts.has("context") and String(e.get("context", "")) != String(opts["context"]):
			continue
		if opts.has("objective") and String(e.get("objective", "")) != String(opts["objective"]):
			continue
		return e
	return {}

# Return ALL lines matching the trigger (e.g. "idle" has multiple).
func get_lines(trigger: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in _lines:
		if not (entry is Dictionary):
			continue
		if String((entry as Dictionary).get("trigger", "")) == trigger:
			out.append(entry)
	return out

# Emit a single line through GameState.say(). Returns true if a line was found.
func emit_line(trigger: String, opts: Dictionary = {}) -> bool:
	_ensure_loaded()
	var line: Dictionary = get_line(trigger, opts)
	if line.is_empty():
		return false
	var gs: Node = _game_state()
	if gs == null:
		return false
	var speaker: String = String(line.get("speaker", ""))
	var text: String = String(line.get("text", ""))
	if speaker == "" or text == "":
		return false
	gs.call("say", speaker, text)
	return true

# Emit a random idle line (commentary lines with trigger "idle").
func emit_idle() -> bool:
	_ensure_loaded()
	var idle_lines: Array = get_lines("idle")
	if idle_lines.is_empty():
		return false
	var gs: Node = _game_state()
	if gs == null:
		return false
	var idx: int = randi_range(0, idle_lines.size() - 1)
	var line: Dictionary = idle_lines[idx]
	var speaker: String = String(line.get("speaker", ""))
	var text: String = String(line.get("text", ""))
	if speaker == "" or text == "":
		return false
	gs.call("say", speaker, text)
	return true

static func _game_state() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("GameState")