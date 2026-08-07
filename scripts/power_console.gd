class_name PowerConsole
extends Interactable

# Engineering Bay power console. One-shot: flipping the breaker restores the
# main power grid and unlocks the elevator door north of cr_corridor_2,
# gating the upper deck (Crew Quarters Alpha + Hydroponics) behind early
# exploration of the lower deck.
#
# Power integration: calls PowerGrid.repair_generator() to bring all rooms
# back to POWERED (clears conduit + section damage, resets generator output).

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
	AudioZones.play_console_boot()
	# Restore the power grid — repair generator output + clear all damage.
	var pg: Node = _autoload("PowerGrid")
	if pg != null and pg.has_method("repair_generator"):
		pg.call("repair_generator")
	GameState.unlock_elevator()

func _autoload(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)
