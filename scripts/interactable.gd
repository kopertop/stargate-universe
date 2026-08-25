class_name Interactable
extends StaticBody3D

# Base for any in-world object the player can use via the interact key.
# Place on a StaticBody3D with collision_layer = 4 (Interactable layer).

signal interacted(by: Node)

@export var prompt: String = "Interact"
@export var enabled: bool = true

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 4

func get_prompt() -> String:
	return prompt

func interact(by: Node) -> void:
	if not enabled:
		return
	interacted.emit(by)
	_on_interact(by)

func _on_interact(_by: Node) -> void:
	pass

func set_enabled(value: bool) -> void:
	enabled = value
