extends Node

# @no-save: transient retry state only — retry count, timer, and is_retrying
# flag are ephemeral and reset on progress or scene reload. Settings are read
# from Accessibility/AccessibilitySettings. No durable state to persist.
# Auto-fail retry system for Stargate Universe. Provides automatic retry
# options when the player fails a critical task (dies, fails a puzzle, runs
# out of time). Configurable:
#   • auto_retry_enabled — master toggle
#   • auto_retry_max — max retries before giving up (lets the player continue
#     manually or reload)
#   • auto_retry_restart — if true, restart from last checkpoint; if false,
#     do a full episode restart
#
# The system listens to GameState failure signals and auto-triggers a retry
# after a short countdown. The retry count resets when the player makes
# progress (completes a quest step, enters a new room, etc.).

signal retry_started(attempt: int)
signal retry_count_exhausted()
signal retry_count_reset()

var _settings: Node = null
var _retry_count: int = 0
var _retry_timer: float = 0.0
var _is_retrying: bool = false
const RETRY_DELAY: float = 2.0  # seconds before auto-retry fires


func _ready() -> void:
	_settings = get_node_or_null("/root/Accessibility/AccessibilitySettings")
	if _settings == null:
		_settings = get_node_or_null("/root/AccessibilitySettings")
	# Connect to GameState failure signals if they exist.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		if gs.has_signal("player_died"):
			gs.player_died.connect(_on_failure)
		if gs.has_signal("puzzle_failed"):
			gs.puzzle_failed.connect(_on_failure)
		if gs.has_signal("quest_step_completed"):
			gs.quest_step_completed.connect(_on_progress)
	set_process(true)


func _process(delta: float) -> void:
	if not _is_retrying:
		return
	_retry_timer += delta
	if _retry_timer >= RETRY_DELAY:
		_is_retrying = false
		_retry_timer = 0.0
		_do_retry()


# Called when a failure condition is detected.
func _on_failure(_context: Variant = null) -> void:
	if _settings == null or not _settings.auto_retry_enabled:
		return
	if _retry_count >= _settings.auto_retry_max:
		retry_count_exhausted.emit()
		return
	_retry_count += 1
	_is_retrying = true
	_retry_timer = 0.0
	retry_started.emit(_retry_count)


# Called when the player makes progress — resets the retry counter.
func _on_progress(_step_id: String = "") -> void:
	if _retry_count > 0:
		_retry_count = 0
		retry_count_reset.emit()


# Get the current retry count (for HUD display).
func get_retry_count() -> int:
	return _retry_count


func get_max_retries() -> int:
	if _settings == null:
		return 0
	return _settings.auto_retry_max


# Cancel a pending retry (player manually recovered or chose to continue).
func cancel_retry() -> void:
	_is_retrying = false
	_retry_timer = 0.0


func _do_retry() -> void:
	if _settings == null:
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	if _settings.auto_retry_restart:
		# Restart from last checkpoint — load the most recent save.
		if sm.has_method("load_latest"):
			sm.call("load_latest")
		elif sm.has_method("load"):
			sm.call("load")
	else:
		# Full episode restart — reload the current scene.
		var sr: Node = get_node_or_null("/root/SceneRouter")
		var scene_path: String = String(gs.get("current_scene_path")) if gs != null else ""
		if sr != null and scene_path != "":
			sr.call("change_to", scene_path, "Retry")