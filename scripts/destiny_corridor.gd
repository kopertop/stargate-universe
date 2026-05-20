extends Node3D

# Hub corridor between the gate room, Eli's quarters, the hull breach, and the
# (locked) observation deck. Updates objectives on first entry and re-entry.

func _ready() -> void:
	GameState.discover_room("corridor", "Destiny Main Corridor")
	# Tune the objective for whatever the player still needs to do.
	_refresh_objective()
	GameState.kino_changed.connect(_on_kino_changed)
	GameState.episode_completed.connect(_on_episode_completed)

func _refresh_objective() -> void:
	if not GameState.kino_acquired:
		GameState.set_objective("Find a Kino Remote — try the crew quarters")
	elif GameState.breaches_sealed.is_empty():
		GameState.set_objective("Seal the hull breach — air is venting")
	elif not GameState.episode_complete:
		GameState.set_objective("Check the Kino map for any rooms you missed")

func _on_kino_changed(_acquired: bool) -> void:
	_refresh_objective()

func _on_episode_completed() -> void:
	GameState.add_log("All immediate threats handled. The Destiny holds — for now.")
