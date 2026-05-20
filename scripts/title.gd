extends Control

# Boot title screen for Stargate Universe — Episode 1: "Air".
# Cinematic Icarus departure flavor text under the logo, then Start / Quit.

@onready var _start_btn: Button = $Frame/Stack/StartButton
@onready var _quit_btn: Button = $Frame/Stack/QuitButton

func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
	_quit_btn.pressed.connect(_on_quit_pressed)
	_start_btn.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_start_pressed() -> void:
	GameState.reset()
	SceneRouter.change_to("res://scenes/gate_room.tscn", "FromGate")

func _on_quit_pressed() -> void:
	get_tree().quit()
