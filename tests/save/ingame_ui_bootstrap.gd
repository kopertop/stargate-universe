extends Node

# Spawns the in-game-UI runner at /root so it survives any scene change the
# title / save flow may trigger. Mirrors load_browser_bootstrap.gd.

func _ready() -> void:
	call_deferred("_spawn")


func _spawn() -> void:
	var runner_script: Script = load("res://tests/save/ingame_ui_runner.gd") as Script
	if runner_script == null:
		push_error("ingame_ui: could not load ingame_ui_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "IngameUI"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
