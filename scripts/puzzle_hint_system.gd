extends Node

# @no-save: transient runtime state only — hint data is loaded from JSON,
# and the puzzle context / timer / hint-shown flag are all set at runtime
# by the scene and reset on puzzle entry/exit. No durable state to persist.
# Puzzle hint system for Stargate Universe. Provides context-aware hints
# for puzzles and interactables. Hints appear after a configurable delay
# (default 30s) if the player hasn't made progress on the current puzzle.
#
# Data-driven: puzzle hints are defined in data/puzzle_hints.json, keyed by
# a puzzle_id string. Each entry has:
#   {
#     "puzzle_id": "gate_room_power",
#     "brief": "The power conduits need to be rerouted.",
#     "detailed": "Check the power console in the gate room. The conduits
#                  are labeled — try matching them to the gate symbols.",
#     "full_solution": "Press the buttons in this order: 3, 1, 4, 2.",
#     "progress_flags": ["gate_power_rerouted"]  # GameState flags that
#                                                # mark progress
#   }
#
# The system monitors the current puzzle context (set by the scene/puzzle
# when the player enters it) and auto-displays a hint after the delay if
# no progress flags have been set.

signal hint_shown(puzzle_id: String, text: String)
signal hint_dismissed()

const HINTS_PATH: String = "res://data/puzzle_hints.json"

var _hints_data: Dictionary = {}
var _current_puzzle: String = ""
var _timer: float = 0.0
var _hint_shown: bool = false
var _settings: Node = null


func _ready() -> void:
	_settings = get_node_or_null("/root/Accessibility/AccessibilitySettings")
	if _settings == null:
		_settings = get_node_or_null("/root/AccessibilitySettings")
	_load_hints_data()
	set_process(true)


func _process(delta: float) -> void:
	if _settings == null or not _settings.hints_enabled:
		return
	if _current_puzzle == "" or _hint_shown:
		return
	# Check if progress flags have been set — if so, puzzle is in progress,
	# don't auto-show a hint.
	if _has_progress():
		_timer = 0.0
		return
	_timer += delta
	if _timer >= _settings.hint_delay_seconds:
		show_hint()


# Set the current puzzle context. Called when the player enters a puzzle area.
func set_puzzle(puzzle_id: String) -> void:
	_current_puzzle = puzzle_id
	_timer = 0.0
	_hint_shown = false


# Clear the current puzzle context. Called when the player leaves or
# completes a puzzle.
func clear_puzzle() -> void:
	_current_puzzle = ""
	_timer = 0.0
	_hint_shown = false


# Manually show a hint for the current puzzle (player pressed the hint button).
func show_hint() -> void:
	if _current_puzzle == "":
		return
	var hint_text := get_hint_text()
	if hint_text == "":
		return
	_hint_shown = true
	hint_shown.emit(_current_puzzle, hint_text)


# Dismiss the current hint (player acknowledged it).
func dismiss_hint() -> void:
	_hint_shown = false
	hint_dismissed.emit()


# Get the hint text for the current puzzle based on the detail level setting.
func get_hint_text() -> String:
	if _current_puzzle == "" or not _hints_data.has(_current_puzzle):
		return ""
	return _hint_text_for_entry(_hints_data[_current_puzzle])


# Get hint text for a specific puzzle ID (for manual lookup).
func get_hint_for(puzzle_id: String) -> String:
	if not _hints_data.has(puzzle_id):
		return ""
	return _hint_text_for_entry(_hints_data[puzzle_id])


# Internal: resolve hint text from an entry dictionary based on detail level.
func _hint_text_for_entry(entry: Dictionary) -> String:
	if _settings == null:
		return String(entry.get("brief", ""))
	var brief: String = String(entry.get("brief", ""))
	var detailed: String = String(entry.get("detailed", brief))
	var full: String = String(entry.get("full_solution", detailed))
	match _settings.hint_detail:
		HINT_BRIEF:
			return brief
		HINT_DETAILED:
			return detailed
		HINT_FULL_SOLUTION:
			return full
		_:
			return brief


# Check if the current puzzle has progress flags that are set in GameState.
func _has_progress() -> bool:
	if _current_puzzle == "" or not _hints_data.has(_current_puzzle):
		return false
	var entry: Dictionary = _hints_data[_current_puzzle]
	var flags: Array = entry.get("progress_flags", [])
	if flags.is_empty():
		return false
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	for flag in flags:
		var val: Variant = gs.get(String(flag))
		if val != null and bool(val):
			return true
	return false


func _load_hints_data() -> void:
	if not FileAccess.file_exists(HINTS_PATH):
		# No data file — create an empty one so the system is ready.
		_hints_data = {}
		return
	var file := FileAccess.open(HINTS_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		return
	var data: Variant = json.data
	if data is Array:
		for entry in data:
			var pid: String = String(entry.get("puzzle_id", ""))
			if pid != "":
				_hints_data[pid] = entry
	elif data is Dictionary:
		_hints_data = data


# Lazy reference to the HintDetail enum indices — avoids a hard class_name
# dependency on AccessibilitySettings (which may not be loaded in bare tests).
# Use plain ints instead of a const dict (Godot 4 doesn't support dict consts
# in all contexts).
const HINT_BRIEF: int = 0
const HINT_DETAILED: int = 1
const HINT_FULL_SOLUTION: int = 2