class_name CommStonePedestal
extends Interactable

# Ancient communication stone pedestal. When the player interacts, the
# CommStones autoload fires the body-swap sequence. Place on a StaticBody3D
# in the observation deck (or wherever the stones are found in the scene).
#
# The first interact sets GameState.comm_stones_found = true and advances
# the quest step. Subsequent interacts trigger the body-swap via
# CommStones.activate_stone().
#
# On the Earth side, a CommStonePedestal with is_return_pedestal = true
# calls CommStones.return_to_destiny() instead.

@export var stone_id: String = "stone_01"
@export var is_return_pedestal: bool = false
@export var first_use_prompt: String = "Examine the Ancient stones"
@export var activate_prompt: String = "Place your hand on the stone"
@export var return_prompt: String = "Use the stone to return to Destiny"

var _first_examination: bool = false


func _ready() -> void:
	super()
	prompt = first_use_prompt


func get_prompt() -> String:
	if is_return_pedestal:
		return return_prompt
	if not _first_examination:
		return first_use_prompt
	return activate_prompt


func _on_interact(_by: Node) -> void:
	if is_return_pedestal:
		_do_return()
		return
	if not _first_examination:
		_do_first_examination()
		return
	_do_stone_activation()


func _do_first_examination() -> void:
	_first_examination = true
	prompt = activate_prompt
	GameState.comm_stones_found = true
	GameState.add_log("Ancient communication stones. They hum with a faint blue light.")
	GameState.narrate("The stones sit on a stone pedestal, glowing faintly.")
	GameState.narrate("You've seen devices like this in the SGC archives — communication stones.")
	GameState.narrate("They allow consciousness to cross the void between two points in space.")
	GameState.advance_air_quest()


func _do_stone_activation() -> void:
	var cs: Node = _autoload_node("CommStones")
	if cs == null:
		GameState.add_log("The stones are dark. Nothing happens.")
		return
	if cs.has_method("is_on_earth") and cs.call("is_on_earth"):
		GameState.add_log("You're already linked through the stones.")
		return
	GameState.stones_activated = true
	# activate_stone is async (await cinematic); call without await so
	# the interact returns immediately and the cinematic plays out.
	cs.call("activate_stone", stone_id)
	# Listen for the body_swap_complete signal to sync GameState.
	if cs.has_signal("body_swap_complete") and not cs.body_swap_complete.is_connected(_on_body_swap_complete):
		cs.body_swap_complete.connect(_on_body_swap_complete)
	if cs.has_signal("return_complete") and not cs.return_complete.is_connected(_on_return_complete):
		cs.return_complete.connect(_on_return_complete)


func _do_return() -> void:
	var cs: Node = _autoload_node("CommStones")
	if cs == null:
		return
	if cs.has_method("return_to_destiny"):
		cs.call("return_to_destiny")


func _on_body_swap_complete(earth_body_id: String) -> void:
	# Sync GameState so quest predicates fire.
	GameState.stones_activated = true
	GameState.add_log("Consciousness transferred to Earth body: %s" % earth_body_id)


func _on_return_complete() -> void:
	GameState.returned_from_earth = true
	GameState.all_sgc_objectives_done = true
	GameState.add_log("Returned to Destiny. The communication link is severed.")
	# Drive the quest chain forward.
	GameState.advance_air_quest()


# Autoload-tolerant lookup (same pattern as GameState._autoload_node).
# Uses Engine.get_main_loop() so it works even when this node isn't in
# the scene tree (e.g. headless test instantiation).
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)