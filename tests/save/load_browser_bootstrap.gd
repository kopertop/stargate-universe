extends Node

# Spawns the load-browser runner at /root so it survives the scene change that
# load_and_resume_checkpoint triggers (the scene root would otherwise be freed).
# Mirrors tests/save/profile_orchestration_bootstrap.gd.

func _ready() -> void:
	call_deferred("_spawn")


func _spawn() -> void:
	var runner_script: Script = load("res://tests/save/load_browser_runner.gd") as Script
	if runner_script == null:
		push_error("load browser: could not load load_browser_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "LoadBrowser"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
