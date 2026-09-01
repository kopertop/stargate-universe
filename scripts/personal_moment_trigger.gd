class_name PersonalMomentTrigger
extends Interactable

# PersonalMomentTrigger — an interactable on the Earth side that starts
# the personal moment scene (Eli visits his mom). Place in the Earth
# scene near a door or phone.
#
# When the player interacts, it calls EarthVisit.start_personal_moment().
# After the moment is complete, the prompt changes and the trigger
# becomes inactive.

@export var trigger_label: String = "Visit Eli's mother"

var _used: bool = false


func _ready() -> void:
	super()
	prompt = trigger_label


func get_prompt() -> String:
	if _used:
		return "You've already visited."
	var ev: Node = _autoload_node("EarthVisit")
	if ev != null and ev.has_method("is_personal_moment_done"):
		if ev.call("is_personal_moment_done"):
			return "You've already visited."
	return trigger_label


func _on_interact(_by: Node) -> void:
	if _used:
		GameState.add_log("You've already visited Maryann.")
		return
	var ev: Node = _autoload_node("EarthVisit")
	if ev == null:
		GameState.add_log("Nothing happens.")
		return
	if ev.has_method("is_personal_moment_done") and ev.call("is_personal_moment_done"):
		_used = true
		GameState.add_log("You've already visited Maryann.")
		return
	if ev.has_method("start_personal_moment"):
		ev.call("start_personal_moment")
		_used = true


# Autoload-tolerant lookup.
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)