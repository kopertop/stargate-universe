extends Node

# Ancient Tech Puzzle Framework for Stargate Universe
# Core puzzle management system for Ancient technology challenges.
# Handles puzzle creation, validation, progress tracking, and state management.

signal puzzle_started(puzzle_id: String)
signal puzzle_solved(puzzle_id: String, success: bool)
signal puzzle_failed(puzzle_id: String, reason: String)
signal puzzle_reset(puzzle_id: String)

# Puzzle states
enum PuzzleState {
	INACTIVE,
	STARTED,
	IN_PROGRESS,
	SOLVED,
	FAILED
}

# Puzzle data structure
class PuzzleData:
	var id: String
	var title: String
	var description: String
	var type: String  # "sequence", "pattern", "lock", "code", "alignment"
	var required_flags: Array[String]  # GameState flags to check first
	var objective: String
	var maximum_attempts: int = 3
	var time_limit: float = 0.0  # 0 = no limit (seconds)
	var initial_time: float = 0.0
	var current_attempts: int = 0
	var current_state: PuzzleState = PuzzleState.INACTIVE
	var timer: float = 0.0
	var is_timer_running: bool = false
	var metadata: Dictionary = {}

	func _init(puzzle_id: String, title: String, description: String, type: String) -> void:
		self.id = puzzle_id
		self.title = title
		self.description = description
		self.type = type


var _puzzles: Dictionary = {}  # Dictionary of PuzzleData

# Load puzzles from data file
func _ready() -> void:
	_load_puzzles_from_data()


# Load all puzzles from data/puzzles.json
func _load_puzzles_from_data() -> void:
	var file_path := "res://data/puzzles.json"
	if not FileAccess.file_exists(file_path):
		# Create default puzzles if no data file exists
		_create_default_puzzles()
		return

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		_create_default_puzzles()
		return

	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var err: int = json.parse(text)
	if err != OK or not json.data is Dictionary:
		push_error("Failed to parse puzzles.json: " + json.get_error_message())
		_create_default_puzzles()
		return

	var data: Dictionary = json.data
	for puzzle_id in data:
		var puzzle_data = _parse_puzzle_data(puzzle_id, data[puzzle_id])
		if puzzle_data != null:
			_puzzles[puzzle_id] = puzzle_data


# Create default puzzle set if no data file exists
func _create_default_puzzles() -> void:
	print("Creating default puzzles")

	# Default power grid puzzle
	var power_puzzle = PuzzleData.new(
		"ancient_power_grid",
		"Ancient Power Grid",
		"Reroute power through the Ancient conduits to restore gate operation.",
		"lock"
	)
	power_puzzle.required_flags = ["gate_power_rerouted", "gate_power_active"]
	power_puzzle.objective = "Reroute power from the auxiliary generator to the gate system."
	power_puzzle.maximum_attempts = 5
	_puzzles["ancient_power_grid"] = power_puzzle

	# Default puzzle type
	print("Default puzzles created")


# Parse a puzzle entry from JSON data
func _parse_puzzle_data(puzzle_id: String, data: Dictionary) -> PuzzleData:
	var puzzle := PuzzleData.new(
		String(data.get("id", puzzle_id)),
		String(data.get("title", puzzle_id)),
		String(data.get("description", "No description")),
		String(data.get("type", "sequence"))
	)

	puzzle.required_flags = _parse_string_array(data.get("required_flags", []))
	puzzle.objective = String(data.get("objective", ""))
	puzzle.maximum_attempts = int(data.get("maximum_attempts", 3))
	puzzle.time_limit = float(data.get("time_limit", 0.0))
	puzzle.initial_time = float(data.get("time_limit", 0.0))

	if data.has("metadata"):
		puzzle.metadata = _parse_dict(data.get("metadata", {}))

	return puzzle


# Parse string array from JSON
func _parse_string_array(data: Variant) -> Array[String]:
	if data is Array:
		var result: Array[String] = []
		for item in data:
			result.append(String(item))
		return result
	return []


# Parse dictionary from JSON
func _parse_dict(data: Variant) -> Dictionary:
	if data is Dictionary:
		return data
	return {}


# Get puzzle by ID
func get_puzzle(puzzle_id: String) -> PuzzleData:
	return _puzzles.get(puzzle_id)


# Check if puzzle exists
func has_puzzle(puzzle_id: String) -> bool:
	return _puzzles.has(puzzle_id)


# Start a puzzle
func start_puzzle(puzzle_id: String) -> bool:
	if not _puzzles.has(puzzle_id):
		push_error("Puzzle not found: " + puzzle_id)
		return false

	var puzzle := _puzzles[puzzle_id]

	# Check required flags first
	if not _check_required_flags(puzzle):
		puzzle.current_state = PuzzleState.FAILED
		puzzle_failed.emit(puzzle_id, "Required prerequisites not met")
		return false

	# Check if already solved
	if puzzle.current_state == PuzzleState.SOLVED:
		print("Puzzle already solved: " + puzzle_id)
		return true

	# Initialize puzzle state
	puzzle.current_state = PuzzleState.STARTED
	if puzzle.time_limit > 0:
		puzzle.timer = puzzle.initial_time
		puzzle.is_timer_running = true

	puzzle_started.emit(puzzle_id)
	return true


# Check if player has met required flags for puzzle
func _check_required_flags(puzzle: PuzzleData) -> bool:
	if puzzle.required_flags.is_empty():
		return true

	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return false

	for flag in puzzle.required_flags:
		var val: Variant = gs.get(String(flag))
		if val != null and bool(val):
			continue
		return false

	return true


# Validate player input for current puzzle
func validate_puzzle_input(puzzle_id: String, input: Variant) -> bool:
	var puzzle := get_puzzle(puzzle_id)
	if puzzle == null or puzzle.current_state != PuzzleState.STARTED and puzzle.current_state != PuzzleState.IN_PROGRESS:
		return false

	# Check time limit
	if puzzle.time_limit > 0 and puzzle.is_timer_running:
		if puzzle.timer <= 0:
			puzzle.current_state = PuzzleState.FAILED
			puzzle_failed.emit(puzzle_id, "Time limit exceeded")
			return false

	# Check attempt limit
	if puzzle.current_attempts >= puzzle.maximum_attempts:
		puzzle.current_state = PuzzleState.FAILED
		puzzle_failed.emit(puzzle_id, "Maximum attempts exceeded")
		return false

	# Increment attempt counter
	puzzle.current_attempts += 1

	# Validate based on puzzle type
	match puzzle.type:
		"sequence":
			return _validate_sequence_input(puzzle, input)
		"pattern":
			return _validate_pattern_input(puzzle, input)
		"lock":
			return _validate_lock_input(puzzle, input)
		"code":
			return _validate_code_input(puzzle, input)
		"alignment":
			return _validate_alignment_input(puzzle, input)
		_:
			push_error("Unknown puzzle type: " + puzzle.type)
			return false

	# Success case handled in validation functions
	return false


# Validate sequence puzzle input
func _validate_sequence_input(puzzle: PuzzleData, input: Variant) -> bool:
	print("Sequence puzzle validation: " + input as String)
	# TODO: Implement sequence puzzle validation
	# For now, accept any input as success
	puzzle.current_state = PuzzleState.IN_PROGRESS
	return true


# Validate pattern puzzle input
func _validate_pattern_input(puzzle: PuzzleData, input: Variant) -> bool:
	print("Pattern puzzle validation: " + input as String)
	# TODO: Implement pattern puzzle validation
	return true


# Validate lock puzzle input
func _validate_lock_input(puzzle: PuzzleData, input: Variant) -> bool:
	print("Lock puzzle validation: " + input as String)
	# TODO: Implement lock puzzle validation
	return true


# Validate code puzzle input
func _validate_code_input(puzzle: PuzzleData, input: Variant) -> bool:
	print("Code puzzle validation: " + input as String)
	# TODO: Implement code puzzle validation
	return true


# Validate alignment puzzle input
func _validate_alignment_input(puzzle: PuzzleData, input: Variant) -> bool:
	print("Alignment puzzle validation: " + input as String)
	# TODO: Implement alignment puzzle validation
	return true


# Mark puzzle as successfully solved
func mark_puzzle_solved(puzzle_id: String) -> void:
	var puzzle := get_puzzle(puzzle_id)
	if puzzle == null:
		return

	puzzle.current_state = PuzzleState.SOLVED
	puzzle.is_timer_running = false
	puzzle_solved.emit(puzzle_id, true)


# Mark puzzle as failed
func mark_puzzle_failed(puzzle_id: String, reason: String = "") -> void:
	var puzzle := get_puzzle(puzzle_id)
	if puzzle == null:
		return

	puzzle.current_state = PuzzleState.FAILED
	puzzle.is_timer_running = false
	puzzle_failed.emit(puzzle_id, reason)


# Reset puzzle to initial state
func reset_puzzle(puzzle_id: String) -> void:
	var puzzle := get_puzzle(puzzle_id)
	if puzzle == null:
		return

	puzzle.current_state = PuzzleState.INACTIVE
	puzzle.current_attempts = 0
	puzzle.timer = 0.0
	puzzle.is_timer_running = false
	puzzle_reset.emit(puzzle_id)


# Process the main loop for timer and state management
func _process(delta: float) -> void:
	for puzzle_id in _puzzles:
		var puzzle := _puzzles[puzzle_id]

		if puzzle.current_state == PuzzleState.STARTED and puzzle.is_timer_running and puzzle.time_limit > 0:
			puzzle.timer -= delta
			if puzzle.timer <= 0:
				mark_puzzle_failed(puzzle_id, "Time limit exceeded")


# Get all puzzles
func get_all_puzzles() -> Array[PuzzleData]:
	return _puzzles.values()


# Get puzzles by state
func get_puzzles_by_state(state: PuzzleState) -> Array[PuzzleData]:
	var result: Array[PuzzleData] = []
	for puzzle in _puzzles.values():
		if puzzle.current_state == state:
			result.append(puzzle)
	return result


# Save puzzle state to JSON file (for saving/loading)
func save_puzzle_state(puzzle_id: String, state_data: Dictionary) -> void:
	var file_path := "res://data/puzzle_states.json"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return

	var save_data: Dictionary = {}
	if FileAccess.file_exists(file_path):
		var existing_file := FileAccess.open(file_path, FileAccess.READ)
		if existing_file != null:
			var existing_text := existing_file.get_as_text()
			existing_file.close()
			var existing_json := JSON.new()
			var existing_err := existing_json.parse(existing_text)
			if existing_err == OK and existing_json.data is Dictionary:
				save_data = existing_json.data
		else:
			file.close()
			return

	# Update or add puzzle state
	save_data[puzzle_id] = state_data

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()


# Load puzzle state from JSON file
func load_puzzle_state(puzzle_id: String) -> Dictionary:
	var file_path := "res://data/puzzle_states.json"
	if not FileAccess.file_exists(file_path):
		return {}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK or not json.data is Dictionary:
		return {}

	var data := json.data
	if data.has(puzzle_id):
		return data[puzzle_id]

	return {}


# Clear all puzzle states
func clear_all_states() -> void:
	for puzzle_id in _puzzles:
		reset_puzzle(puzzle_id)

	if FileAccess.file_exists("res://data/puzzle_states.json"):
		DirAccess.remove_absolute("res://data/puzzle_states.json")