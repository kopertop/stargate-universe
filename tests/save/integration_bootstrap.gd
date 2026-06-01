extends Node

# Spawns the save integration + migration runner at /root so it survives the
# scene change that load_and_resume triggers (the scene root would be freed).
# Mirrors tests/save/profile_orchestration_bootstrap.gd.

func _ready() -> void:
	call_deferred("_spawn")


func _spawn() -> void:
	var runner_script: Script = load("res://tests/save/integration_runner.gd") as Script
	if runner_script == null:
		push_error("save integration: could not load integration_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "SaveIntegration"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
