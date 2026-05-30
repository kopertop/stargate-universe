class_name ShuttleDoorPanel
extends Interactable

# Wall panel to the left of the jammed shuttle door. Dead until the player
# fits a Small Fuse looted from the dock crates; once seated it forces the
# jammed door shut and seals the venting (seal_breach).
#
# Emits door_sealed so room.gd can grind the jammed-door prop closed.

signal door_sealed

const BREACH_ID: String = "breach_a"

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	prompt = "Examine door panel"

func _on_interact(_by: Node) -> void:
	if GameState.breaches_sealed.has(BREACH_ID):
		GameState.add_log("The shuttle door is sealed. Pressure's holding.")
		return
	if not GameState.small_fuse_found:
		# First look at the panel teaches the player what's wrong + redirects
		# the objective/waypoint to the crates.
		GameState.add_log("The panel's fuse slot is blown — it needs a Small Fuse. Maybe one of these crates has one.")
		GameState.examine_door_panel()
		return
	GameState.add_log("Small Fuse seated. The jammed door grinds shut — the venting stops.")
	GameState.seal_breach(BREACH_ID)
	# The fuse is spent fitting it into the panel — tell the inventory so it
	# drops from the pack (Inventory.count derives this from breach_a sealed).
	GameState.item_changed.emit("small_fuse", false)
	door_sealed.emit()
