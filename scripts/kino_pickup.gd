class_name KinoPickup
extends Interactable

# One-shot pickup that grants the Kino Remote. After acquisition the prop hides
# and the interactable disables itself.

@export var prop_to_hide: NodePath

func _ready() -> void:
	super()
	prompt = "Pick up the Kino Remote"
	if GameState.kino_acquired:
		_hide_prop()
		enabled = false

func _on_interact(_by: Node) -> void:
	GameState.acquire_kino()
	_hide_prop()
	enabled = false
	GameState.check_episode_complete()

func _hide_prop() -> void:
	if prop_to_hide.is_empty():
		return
	var n: Node = get_node_or_null(prop_to_hide)
	if n != null and n is Node3D:
		(n as Node3D).visible = false
