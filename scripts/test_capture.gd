extends Node

# Auto-screenshot helper for AI-driven iteration.
# Enabled when the project is launched with `--cli-arg capture` (or any positional arg
# containing "capture"). Waits a few frames after the scene loads, saves a PNG to
# user://capture_NN.png (resolves to ~/Library/Application Support/Godot/app_userdata/...
# on macOS), and quits.

const OUT_PATH: String = "user://capture.png"
const FRAMES_TO_WAIT: int = 60

var _frames: int = 0
var _done: bool = false

func _ready() -> void:
	if not _capture_requested():
		queue_free()
		return
	print("[test_capture] active, waiting %d frames" % FRAMES_TO_WAIT)

func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < FRAMES_TO_WAIT:
		return
	_done = true
	_dump_scene()
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(OUT_PATH)
	print("[test_capture] saved=%s err=%s abs=%s" % [OUT_PATH, err, ProjectSettings.globalize_path(OUT_PATH)])
	get_tree().quit()

func _dump_scene() -> void:
	var root: Window = get_tree().root
	for w in root.get_children():
		_dump_node(w, 0)

func _dump_node(n: Node, depth: int) -> void:
	var prefix: String = "  ".repeat(depth)
	var info: String = "%s%s [%s]" % [prefix, n.name, n.get_class()]
	if n is Node3D:
		info += " pos=" + str((n as Node3D).global_position)
		info += " visible=" + str((n as Node3D).visible)
	print(info)
	if depth < 3:
		for c in n.get_children():
			_dump_node(c, depth + 1)

func _capture_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.contains("capture"):
			return true
	return false
