class_name SGCReportConsole
extends Interactable

# SGC Report Console — an interactable on the Earth side that lets the
# player deliver one of the four SGC report objectives. Place one per
# objective in the SGC briefing room scene.
#
# When the player interacts, it:
#   1. Checks CommStones is in the on_earth phase.
#   2. Calls EarthVisit.deliver_report(objective_id).
#   3. Narrates the report delivery via GameState.
#
# The prompt changes to "Report delivered" after the objective is complete.

@export var objective_id: String = ""
@export var console_label: String = "SGC Report Terminal"

var _delivered: bool = false


func _ready() -> void:
	super()
	prompt = "Deliver report: %s" % console_label


func get_prompt() -> String:
	if _delivered:
		return "%s — delivered" % console_label
	var cs: Node = _autoload_node("CommStones")
	if cs != null and cs.has_method("is_sgc_objective_done"):
		if cs.call("is_sgc_objective_done", objective_id):
			return "%s — delivered" % console_label
	return "Deliver report: %s" % console_label


func _on_interact(_by: Node) -> void:
	if objective_id == "":
		GameState.add_log("This terminal is not configured.")
		return
	var cs: Node = _autoload_node("CommStones")
	if cs == null:
		GameState.add_log("The terminal is dark. No connection.")
		return
	# Only works when on Earth.
	if cs.has_method("is_on_earth") and not cs.call("is_on_earth"):
		GameState.add_log("The terminal is inactive. You're not on Earth.")
		return
	# Check if already delivered.
	if cs.has_method("is_sgc_objective_done") and cs.call("is_sgc_objective_done", objective_id):
		GameState.add_log("This report has already been delivered.")
		return
	# Deliver via EarthVisit.
	var ev: Node = _autoload_node("EarthVisit")
	if ev != null and ev.has_method("deliver_report"):
		ev.call("deliver_report", objective_id)
		_delivered = true
	elif cs.has_method("complete_sgc_objective"):
		# Fallback: deliver directly through CommStones.
		cs.call("complete_sgc_objective", objective_id)
		_delivered = true


# Autoload-tolerant lookup (same pattern as CommStonePedestal).
func _autoload_node(name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(name)