extends Node

# Autoload. Listens for GameState.episode_completed and shows a one-time
# end-of-episode card. Pauses gameplay; "Return to Title" resets state.

var _layer: CanvasLayer
var _root: Control
var _shown: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.episode_completed.connect(_on_episode_completed)

func _on_episode_completed() -> void:
	if _shown:
		return
	_shown = true
	call_deferred("_build_and_show")

func _build_and_show() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	_root.add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_root.add_child(center)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.custom_minimum_size = Vector2(640, 0)
	stack.add_theme_constant_override("separation", 16)
	center.add_child(stack)

	var title: Label = Label.new()
	title.text = "EPISODE 1 — \"AIR\""
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	stack.add_child(title)

	var sub: Label = Label.new()
	sub.text = "— Complete —"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
	stack.add_child(sub)

	var summary: Label = Label.new()
	summary.text = ("You sealed Compartment 14B. The Destiny holds.\n"
		+ "You found your quarters. You can rest.\n"
		+ "You have a Kino Remote. The ship's secrets are no longer one-way.\n\n"
		+ "More of the Destiny is dark. More of it is wrong.\n"
		+ "But, for now: you can breathe.")
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 14)
	summary.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95, 0.9))
	summary.add_theme_constant_override("line_spacing", 4)
	stack.add_child(summary)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	stack.add_child(spacer)

	var btn: Button = Button.new()
	btn.text = "Return to Title"
	btn.custom_minimum_size = Vector2(240, 48)
	btn.add_theme_font_size_override("font_size", 16)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(_on_return_to_title)
	stack.add_child(btn)
	btn.grab_focus()

	# Fade BG in slowly, pause game.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	var tw: Tween = create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(bg, "color:a", 0.82, 1.2)

func _on_return_to_title() -> void:
	get_tree().paused = false
	if _layer != null:
		_layer.queue_free()
		_layer = null
	_shown = false
	GameState.reset()
	SceneRouter.change_to("res://scenes/title.tscn")
