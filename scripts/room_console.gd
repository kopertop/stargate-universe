class_name RoomConsole
extends Interactable

# Per-room systems console (merged-deck flow). Every non-corridor room gets
# one — E opens the room's BuildPanel: damage/shield readout + the module
# catalog for choosing what to build in this room (hydroponics, quarters,
# research lab, machine shop, ...). Deck.gd spawns and positions these; the
# console mesh comes from RoomBuilder.attach_console_mesh so all Ancient
# terminals share one silhouette.
#
# Collision convention matches control_console.gd: layer 1|4 — body blocks
# the player capsule, interact ray still hits.

const BuildPanelScript: Script = preload("res://scripts/build_panel.gd")

const COLLIDER_SIZE: Vector3 = Vector3(1.7, 1.1, 1.1)
const COLLIDER_Y: float = 0.55

@export var room_id: String = ""


func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_ensure_collider()
	var display: String = String(ShipLayout.room(room_id).get("name", room_id))
	prompt = "Use room console — %s" % display
	add_to_group("room_console")


func _ensure_collider() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			return
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = COLLIDER_SIZE
	cs.shape = box
	cs.position = Vector3(0.0, COLLIDER_Y, 0.0)
	add_child(cs)


func _on_interact(_by: Node) -> void:
	GameState.add_log("Console: room systems interface online.")
	var panel: CanvasLayer = BuildPanelScript.new()
	panel.set("room_id", room_id)
	get_tree().root.add_child(panel)
