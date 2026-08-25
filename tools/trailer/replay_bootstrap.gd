extends Node

# Spawns the replay runner as a child of /root so it survives the
# change_scene_to_file() calls it makes while replaying the captured playthrough.
# Mirrors tools/trailer/bootstrap.gd.

func _ready() -> void:
	call_deferred("_spawn_runner")


func _spawn_runner() -> void:
	var runner_script: Script = load("res://tools/trailer/replay_runner.gd") as Script
	if runner_script == null:
		push_error("trailer/replay_bootstrap: could not load replay_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "TrailerReplayRunner"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
