class_name MedBay
extends Node

signal recovery_started(character_id: String)
signal recovery_finished(character_id: String)

@export var recovery_duration: float = 5.0
var _recovering: Dictionary = {}

var tj_lines: Array[String] = [
	"Can you move your fingers?",
	"We'll get it in a sling.",
	"Are you okay?"
]

func start_recovery(character_id: String) -> void:
	if _recovering.has(character_id): return
	_recovering[character_id] = { "time_remaining": recovery_duration, "line_index": 0 }
	recovery_started.emit(character_id)

func process_recovery(character_id: String, delta: float) -> void:
	if not _recovering.has(character_id): return
	var data: Dictionary = _recovering[character_id]
	data["time_remaining"] = data["time_remaining"] - delta
	if data["time_remaining"] <= 0.0:
		_recovering.erase(character_id)
		recovery_finished.emit(character_id)

func get_tj_line(character_id: String) -> String:
	if not _recovering.has(character_id): return ""
	var data: Dictionary = _recovering[character_id]
	var idx: int = data["line_index"]
	if idx >= tj_lines.size(): return ""
	data["line_index"] = idx + 1
	return tj_lines[idx]

func is_recovering(character_id: String) -> bool:
	return _recovering.has(character_id)