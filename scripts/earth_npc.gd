class_name EarthNPC
extends Interactable

# EarthNPC — an NPC on the Earth side (SGC or personal location) that uses
# a dialogue tree from data/earth_dialogues.json. When a dialogue choice
# carries an "action" key matching an SGC objective ID, it delivers that
# report via EarthVisit.
#
# Unlike the ship-side Npc class, EarthNPC is simpler: it doesn't need
# auto-greet, ambient bubbles, or 3D model management. It's a pure
# dialogue interactable.
#
# Usage: set npc_id to match an entry in earth_dialogues.json. The dialogue
# tree is loaded from EarthVisit at runtime.

@export var npc_id: String = ""
@export var custom_prompt: String = ""

var _dialogue_tree: Array = []
var _visited: bool = false


func _ready() -> void:
	super()
	# Load the dialogue tree from EarthVisit.
	var ev: Node = _autoload_node("EarthVisit")
	if ev != null and ev.has_method("get_npc_dialogue_tree"):
		_dialogue_tree = ev.call("get_npc_dialogue_tree", npc_id)
	# Set prompt based on NPC display name.
	if custom_prompt != "":
		prompt = custom_prompt
	elif ev != null and ev.has_method("get_npc_display_name"):
		var display_name: String = ev.call("get_npc_display_name", npc_id)
		if display_name != "":
			prompt = "Talk to %s" % display_name
		else:
			prompt = "Talk"


func get_prompt() -> String:
	return prompt


func _on_interact(_by: Node) -> void:
	if _dialogue_tree.is_empty():
		GameState.add_log("There's no one to talk to here.")
		return
	# Mark as visited.
	var ev: Node = _autoload_node("EarthVisit")
	if ev != null and ev.has_method("visit_npc"):
		ev.call("visit_npc", npc_id)
	# Emit the dialogue tree through GameState (same pattern as Npc).
	GameState.dialog_started.emit(self, _dialogue_tree)
	# Narrate the first line so the player sees the NPC's opening.
	if not _visited:
		_visited = true
		var first: Dictionary = _dialogue_tree[0] if not _dialogue_tree.is_empty() else {}
		if not first.is_empty():
			var speaker: String = String(first.get("speaker", ""))
			var text: String = String(first.get("text", ""))
			if speaker != "" and text != "":
				GameState.say(speaker, text)


# Process a dialogue choice action. Called by the dialog screen when a
# choice with an "action" key is selected.
func process_action(action_id: String) -> void:
	var ev: Node = _autoload_node("EarthVisit")
	if ev == null:
		return
	# Check if the action matches an SGC objective.
	var obj_ids: Array = []
	if ev.has_method("get_sgc_objective_ids"):
		obj_ids = ev.call("get_sgc_objective_ids")
	if obj_ids.has(action_id):
		if ev.has_method("deliver_report"):
			ev.call("deliver_report", action_id)
		return
	# Check for personal moment action.
	if action_id == "personal_moment" and ev.has_method("start_personal_moment"):
		ev.call("start_personal_moment")


# Autoload-tolerant lookup.
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)