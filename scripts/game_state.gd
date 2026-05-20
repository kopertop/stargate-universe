extends Node

# Global persistent game state. Cross-scene singleton.
# Survives scene_router transitions; reset() returns to clean E1 start.

signal health_changed(value: float)
signal oxygen_changed(value: float)
signal objective_changed(text: String)
signal room_discovered(room_id: String)
signal kino_changed(acquired: bool)
signal episode_completed()
signal log_added(line: String)

const MAX_HEALTH: float = 100.0
const MAX_OXYGEN: float = 100.0

var health: float = MAX_HEALTH
var oxygen: float = MAX_OXYGEN
var kino_acquired: bool = false
var quarters_found: bool = false
var rooms_discovered: Array[String] = []
var breaches_sealed: Array[String] = []
var current_objective: String = "Step through the gate"
var episode_complete: bool = false
var log_entries: Array[String] = []

func reset() -> void:
	health = MAX_HEALTH
	oxygen = MAX_OXYGEN
	kino_acquired = false
	quarters_found = false
	rooms_discovered.clear()
	breaches_sealed.clear()
	current_objective = "Step through the gate"
	episode_complete = false
	log_entries.clear()
	health_changed.emit(health)
	oxygen_changed.emit(oxygen)
	objective_changed.emit(current_objective)
	kino_changed.emit(kino_acquired)

func damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, MAX_HEALTH)
	health_changed.emit(health)

func heal_full() -> void:
	health = MAX_HEALTH
	health_changed.emit(health)

func consume_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen - amount, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)
	# Below 25% oxygen, health starts ticking down too.
	if oxygen < 25.0:
		damage(amount * 0.5)

func restore_oxygen(amount: float) -> void:
	oxygen = clampf(oxygen + amount, 0.0, MAX_OXYGEN)
	oxygen_changed.emit(oxygen)

func discover_room(room_id: String, display_name: String = "") -> void:
	if rooms_discovered.has(room_id):
		return
	rooms_discovered.append(room_id)
	room_discovered.emit(room_id)
	if display_name != "":
		add_log("Discovered: " + display_name)

func acquire_kino() -> void:
	if kino_acquired:
		return
	kino_acquired = true
	kino_changed.emit(true)
	add_log("Acquired the Kino Remote.")
	set_objective("Use the Kino Remote (Tab) to view the ship map")

func mark_quarters_found() -> void:
	quarters_found = true
	add_log("Found Eli's quarters.")

func seal_breach(breach_id: String) -> void:
	if breaches_sealed.has(breach_id):
		return
	breaches_sealed.append(breach_id)
	restore_oxygen(MAX_OXYGEN)
	add_log("Hull breach sealed: " + breach_id)

func set_objective(text: String) -> void:
	current_objective = text
	objective_changed.emit(text)

func add_log(line: String) -> void:
	log_entries.append(line)
	log_added.emit(line)

# Episode 1 completion: Kino acquired, quarters found, at least one breach sealed.
func check_episode_complete() -> void:
	if episode_complete:
		return
	if kino_acquired and quarters_found and breaches_sealed.size() > 0:
		episode_complete = true
		set_objective("Episode 1: Air — Complete")
		episode_completed.emit()
