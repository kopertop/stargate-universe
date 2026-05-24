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
@onready var _dialog_panel: NinePatchRect = $DialogPanel
@onready var _dialog_name: Label = $DialogPanel/Nameplate/Name
@onready var _dialog_line: Label = $DialogPanel/Line

var _player: Node = null
# Active dialog auto-hide tween. Held so a follow-up line can cancel the old
# fade — otherwise rapid talking would leave the panel half-faded.
var _dialog_tween: Tween = null

func _ready() -> void:
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.health_changed.connect(_on_health_changed)
	GameState.oxygen_changed.connect(_on_oxygen_changed)
	GameState.kino_changed.connect(_on_kino_changed)
	GameState.log_added.connect(_on_log_added)
	GameState.dialogue_shown.connect(_on_dialogue_shown)
	GameState.dialog_started.connect(_on_dialog_started)
	_on_objective_changed(GameState.current_objective)
	_on_health_changed(GameState.health)
	_on_oxygen_changed(GameState.oxygen)
	_on_kino_changed(GameState.kino_acquired)
	_interact_label.text = ""
	_dialog_panel.visible = false
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

func _on_dialogue_shown(character_name: String, line: String) -> void:
	_dialog_name.text = character_name
	_dialog_line.text = line
	_dialog_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_dialog_panel.visible = true
	# Cancel a still-running fade from the previous line so the new one shows
	# at full opacity even if the player triggered them in quick succession.
	if _dialog_tween != null and _dialog_tween.is_running():
		_dialog_tween.kill()
	_dialog_tween = create_tween()
	_dialog_tween.tween_interval(6.5)
	_dialog_tween.tween_property(_dialog_panel, "modulate:a", 0.0, 0.8)
	_dialog_tween.tween_callback(Callable(self, "_hide_dialog_panel"))

func _hide_dialog_panel() -> void:
	_dialog_panel.visible = false

# Choice-tree dialog: instance the full-screen DialogScreen as our child so it
# inherits the HUD's CanvasLayer (above the world, below pause overlays). The
# screen pauses the tree itself and frees itself on close; we just hand it the
# target NPC + tree and forget about it.
func _on_dialog_started(npc: Node3D, tree: Array) -> void:
	if tree.is_empty() or npc == null:
		return
	var scene: PackedScene = load("res://objects/dialog_screen.tscn")
	if scene == null:
		return
	var screen: Control = scene.instantiate()
	add_child(screen)
	# DialogScreen.start() shares world_3d + frames the portrait camera.
	screen.call("start", npc, tree)

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
