extends Node

# Spawns the resume probe at /root so it survives the scene change that
# load_and_resume triggers (the scene root would be freed). Mirrors
# tests/playthrough/bootstrap.gd.

func _ready() -> void:
	call_deferred("_spawn")


func _spawn() -> void:
	var runner_script: Script = load("res://tests/resume/probe_runner.gd") as Script
	if runner_script == null:
		push_error("resume probe: could not load probe_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "ResumeProbe"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
