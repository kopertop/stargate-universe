class_name PowerConsole
extends Interactable

# Engineering Bay power console. One-shot: flipping the breaker unlocks the
# elevator door north of cr_corridor_2, gating the upper deck (Crew Quarters
# Alpha + Hydroponics) behind early exploration of the lower deck.

@export var restored_prompt: String = "Main power online."

func _ready() -> void:
	super()
	prompt = "Restore main power"
	if GameState.elevator_repaired:
		enabled = false
		prompt = restored_prompt

func _on_interact(_by: Node) -> void:
	enabled = false
	prompt = restored_prompt
	GameState.unlock_elevator()
