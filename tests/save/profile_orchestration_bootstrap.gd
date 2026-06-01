extends Node

# Spawns the profile-orchestration runner at /root so it survives the scene
# change that load_and_resume triggers (the scene root would be freed).
# Mirrors tests/save/slot_resume_bootstrap.gd.

func _ready() -> void:
	call_deferred("_spawn")


func _spawn() -> void:
	var runner_script: Script = load("res://tests/save/profile_orchestration_runner.gd") as Script
	if runner_script == null:
		push_error("profile orchestration: could not load profile_orchestration_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "ProfileOrchestration"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
