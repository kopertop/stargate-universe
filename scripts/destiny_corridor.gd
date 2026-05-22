extends Node3D

# Main corridor between the gate room and the control room. The hero detail
# (floor strip, edge glow, access panels, door trim, cable bundles) is built
# by the parametric corridor_decor.gd attached to the $Decor child — this
# script just owns scene-level GameState wiring.

func _ready() -> void:
	GameState.current_scene_path = "res://scenes/destiny_corridor.tscn"
	GameState.discover_room("corridor", "Destiny Main Corridor")
	GameState.set_objective("Make your way to the control room")
