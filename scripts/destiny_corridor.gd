extends Node3D

# Phase A placeholder corridor. The gate room is the hero space; this is just a
# tiny dead-end so the exit archway leads somewhere. Future phases will reopen
# quarters / hull-breach / observation off this corridor.

func _ready() -> void:
	GameState.current_scene_path = "res://scenes/destiny_corridor.tscn"
	GameState.discover_room("corridor", "Destiny Main Corridor")
	GameState.set_objective("Dead end — return to the gate room")
