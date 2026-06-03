extends Node

# Bootstrap for the gameplay-trailer runner.
#
# Why this exists: the trailer drives real cross-scene transitions via
# SceneRouter, which calls get_tree().change_scene_to_file() and frees the
# current_scene. A runner attached to the scene root would be freed on the first
# transition, so we spawn it as a direct child of /root (sibling to the
# autoloads) where it persists across scene changes. Same pattern as
# tests/playthrough/bootstrap.gd.

func _ready() -> void:
	# Defer one frame so autoloads (GameState, SceneRouter, ...) are fully ready
	# before the runner starts driving them.
	call_deferred("_spawn_runner")


func _spawn_runner() -> void:
	var runner_script: Script = load("res://tools/trailer/trailer_runner.gd") as Script
	if runner_script == null:
		push_error("trailer/bootstrap: could not load trailer_runner.gd")
		get_tree().quit(2)
		return
	var runner: Node = Node.new()
	runner.name = "TrailerRunner"
	runner.set_script(runner_script)
	get_tree().root.add_child(runner)
