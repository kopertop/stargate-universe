class_name Bed
extends Interactable

# Sleep interactable. Restores full health, plays a short fade, and (if first time)
# marks the player as having found their quarters.

@export var first_time_log: String = "These will be my quarters, then. The bed is cold."
@export var sleep_message: String = "Rested. You feel a little less ready to fall over."

func _ready() -> void:
	super()
	prompt = "Sleep"

func _on_interact(_by: Node) -> void:
	if not GameState.quarters_found:
		GameState.add_log(first_time_log)
		GameState.mark_quarters_found()
	GameState.heal_full()
	GameState.restore_oxygen(GameState.MAX_OXYGEN)
	GameState.add_log(sleep_message)
	GameState.check_episode_complete()
