extends Node

# Bootstrap for the E1 playthrough integration test.
#
# Why this exists: the playthrough drives real cross-scene transitions via
# SceneRouter, which calls get_tree().change_scene_to_file(). That frees the
# current_scene and everything in it. If the test runner script were attached
# to the scene root, it would be freed on the first transition.
#
# Fix: this bootstrap spawns the runner as a direct child of /root (sibling
# to the autoloads) so the runner persists across scene changes.

func _ready() -> void:
	# Defer one frame: ensures autoloads (GameState, SceneRouter, etc.) are
	# fully ready before the runner starts driving them.
	call_deferred("_spawn_runner")


func _spawn_runner() -> void:
	var runner_script: Script = load("res://scripts/playthrough_runner.gd") as Script
	if runner_script == null:
		push_error("playthrough/bootstrap: could not load playthrough_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "PlaythroughRunner"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
