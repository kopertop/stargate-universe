class_name ResourceNode
extends Interactable

# Mineable resource node used by generated planet runs.

@export var resource_type: String = "lime"
@export var amount: int = 1
@export var source_label: String = "planet"

var depleted: bool = false

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_refresh_prompt()

func _on_interact(_by: Node) -> void:
	if depleted:
		return
	depleted = true
	enabled = false
	GameState.add_resource(resource_type, amount, source_label)
	visible = false
	collision_layer = 0
	_refresh_prompt()

func _refresh_prompt() -> void:
	if depleted:
		prompt = "%s depleted" % resource_type.capitalize()
	else:
		prompt = "Mine %s" % resource_type
