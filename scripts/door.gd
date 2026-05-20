class_name Door
extends Interactable

# Doorway interactable. Two flavors:
#   - target_scene set → press E transitions to that scene at the named spawn point.
#   - target_scene blank → press E toggles open/closed (visual only for now).
# Doors are NOT physical barriers in the MVP — the wall geometry around them
# leaves an opening. The Door scene is an invisible probe the player aims at.

@export var target_scene: String = ""
@export var target_spawn: String = ""
@export var locked: bool = false
@export var lock_message: String = "LOCKED — power is offline."
@export var open_prompt: String = "Open"
@export var transition_prompt: String = "Enter"
@export var requires_kino: bool = false
@export var requires_kino_message: String = "I need the Kino Remote first."

var _is_open: bool = false

func _ready() -> void:
	super()
	_refresh_prompt()

func _refresh_prompt() -> void:
	if locked:
		prompt = lock_message
	elif requires_kino and not GameState.kino_acquired:
		prompt = requires_kino_message
	elif target_scene != "":
		prompt = transition_prompt
	elif _is_open:
		prompt = "Close"
	else:
		prompt = open_prompt

func _on_interact(by: Node) -> void:
	if locked:
		return
	if requires_kino and not GameState.kino_acquired:
		return
	if target_scene != "":
		_transition(by)
	else:
		_toggle()

func _toggle() -> void:
	_is_open = not _is_open
	_refresh_prompt()

func _transition(by: Node) -> void:
	if by is CharacterBody3D and by.has_method("set_input_locked"):
		by.set_input_locked(true)
	SceneRouter.change_to(target_scene, target_spawn)

func unlock() -> void:
	locked = false
	_refresh_prompt()
