extends Control

# SGU HUD. Listens to GameState signals + the active scene's player to render:
#   • Current objective (top-left)
#   • Health + oxygen bars (bottom-left)
#   • Interact prompt (bottom-center, only when target in range)
#   • Kino Remote reminder (bottom-right, only after acquisition)
#   • Recent log feed (top-right, last 3 entries)

@onready var _objective_label: Label = $Objective
@onready var _health_bar: ProgressBar = $Status/Health/Bar
@onready var _oxygen_bar: ProgressBar = $Status/Oxygen/Bar
@onready var _interact_label: Label = $InteractPrompt
@onready var _kino_hint: Label = $KinoHint
@onready var _log_box: VBoxContainer = $Log

var _player: Node = null

func _ready() -> void:
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.kino_changed.connect(_on_kino_changed)
	GameState.log_added.connect(_on_log_added)
	_on_objective_changed(GameState.current_objective)
	_on_health_changed(GameState.health)
	_on_oxygen_changed(GameState.oxygen)
	_on_kino_changed(GameState.kino_acquired)
	_interact_label.text = ""
	# Defer player lookup so the scene tree is settled.
	call_deferred("_bind_player")

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("interact_target_changed"):
		_player.interact_target_changed.connect(_on_interact_target_changed)

func _on_interact_target_changed(target: Node) -> void:
	if target == null:
		_interact_label.text = ""
		return
	var prompt: String = "Interact"
	if target.has_method("get_prompt"):
		prompt = target.get_prompt()
	elif "prompt" in target:
		prompt = String(target.prompt)
	_interact_label.text = "[E]  %s" % prompt

func _on_objective_changed(text: String) -> void:
	_objective_label.text = text

func _on_health_changed(v: float) -> void:
	_health_bar.value = v
	# Pulse red when critical (handled by modulate via theme override would be nicer; keep simple).

func _on_oxygen_changed(v: float) -> void:
	_oxygen_bar.value = v

func _on_kino_changed(acquired: bool) -> void:
	_kino_hint.visible = acquired
	_kino_hint.text = "[Tab]  Kino Remote"

func _on_log_added(line: String) -> void:
	var lbl: Label = Label.new()
	lbl.text = "• " + line
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	lbl.add_theme_font_size_override("font_size", 14)
	_log_box.add_child(lbl)
	# Keep only the last 3. remove_child() first so the count drops synchronously —
	# queue_free() alone defers deletion to end-of-frame and would spin this loop.
	while _log_box.get_child_count() > 3:
		var oldest: Node = _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()
	# Auto-fade & remove after a moment.
	var t: Tween = create_tween()
	t.tween_interval(6.0)
	t.tween_property(lbl, "modulate:a", 0.0, 1.0)
	t.tween_callback(Callable(lbl, "queue_free"))
