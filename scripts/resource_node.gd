class_name ResourceNode
extends Interactable

# Mineable resource node used by generated planet runs.
#
# Lime deposits also participate in fog-of-war: a deposit is "discovered" once
# the player roams within DISCOVER_RANGE (or mines it), at which point it's
# recorded in GameState (by its stable node name) and shown on the planet
# compass (F3). Discovery survives save/load because the planet seed is fixed,
# so a node name always maps to the same world position.

const DISCOVER_RANGE: float = 30.0
const SCAN_INTERVAL: float = 0.25

@export var resource_type: String = "lime"
@export var amount: int = 1
@export var source_label: String = "planet"

var depleted: bool = false
var _discovered: bool = false
var _scan_t: float = 0.0

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_refresh_prompt()
	# Only lime deposits track discovery; other resources don't feed the compass.
	if resource_type == GameState.AIR_LIME_RESOURCE:
		_discovered = GameState.is_lime_discovered(name)
		set_process(not _discovered)
	else:
		set_process(false)

func _process(delta: float) -> void:
	# Guard against the "no frame ticked" Godot gotcha: global_position can read
	# Vector3.ZERO before the transform has fully propagated, which at ~9m from
	# the gate origin would falsely trigger the 30m discovery threshold.
	if not is_inside_tree():
		return
	_scan_t += delta
	if _scan_t < SCAN_INTERVAL:
		return
	_scan_t = 0.0
	var viewer: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if viewer == null:
		return
	if _planar(viewer.global_position, global_position) <= DISCOVER_RANGE:
		_mark_discovered()

func _on_interact(_by: Node) -> void:
	if depleted:
		return
	_mark_discovered()   # mining a deposit obviously discovers it
	depleted = true
	enabled = false
	GameState.add_resource(resource_type, amount, source_label)
	visible = false
	collision_layer = 0
	_refresh_prompt()

func is_discovered() -> bool:
	return _discovered

func _mark_discovered() -> void:
	if _discovered:
		return
	_discovered = true
	set_process(false)
	if resource_type == GameState.AIR_LIME_RESOURCE:
		GameState.discover_lime(name)

func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _refresh_prompt() -> void:
	if depleted:
		prompt = "%s depleted" % resource_type.capitalize()
	else:
		prompt = "Mine %s" % resource_type
