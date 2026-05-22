extends Node3D

# Eli's quarters. Bed sleeps to full HP/oxygen; Kino sphere on desk grants the remote.

func _ready() -> void:
	GameState.discover_room("quarters", "Eli's Quarters")
	if not GameState.kino_acquired:
		GameState.set_objective("Pick up the Kino Remote on your bed")
	elif not GameState.quarters_found:
		GameState.set_objective("Sleep in the bed to register these as your quarters")
