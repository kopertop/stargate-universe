class_name Bed
extends Interactable

# Sleep interactable. Restores full health, plays a short fade, and (if first time)
# marks the player as having found their quarters.

@export var first_time_log: String = "These will be my quarters, then. The bed is cold."
@export var sleep_message: String = "Rested. You feel a little less ready to fall over."

func _ready() -> void:
	super()
	prompt = "Lay down and rest"

func _on_interact(_by: Node) -> void:
	if not GameState.quarters_found:
		# mark_quarters_found logs the first-time message itself; passing
		# `first_time_log` here lets each bed instance show its own flavour
		# (Eli's quarters vs Crew Quarters Alpha) without a duplicate log.
		GameState.mark_quarters_found(first_time_log)
	if GameState.air_crisis_started and not GameState.scrubber_repaired:
		GameState.add_log("No chance of sleeping with CO2 alarms rising.")
		return
	GameState.heal_full()
	if GameState.can_start_air_crisis():
		GameState.add_log("You sleep hard enough to miss the jump timer.")
		GameState.start_air_crisis()
		return
	GameState.restore_oxygen(GameState.MAX_OXYGEN)
	GameState.add_log(sleep_message)
	GameState.advance_air_quest()
