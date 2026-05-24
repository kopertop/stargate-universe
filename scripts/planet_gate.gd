class_name PlanetGate
extends Area3D

# Stargate portal trigger. The visible ring is built separately; this Area3D
# owns the cross-scene travel rule for either ship->planet or planet->ship.

@export_enum("to_planet", "to_ship") var mode: String = "to_ship"
@export var target_scene: String = "res://scenes/gate_room.tscn"
@export var target_spawn: String = "FromGate"

var _transitioning: bool = false

func _ready() -> void:
	add_to_group("planet_gate")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

func activate(body: Node) -> void:
	await _travel(body)

func _on_body_entered(body: Node) -> void:
	await _travel(body)

func _travel(body: Node) -> void:
	if _transitioning:
		return
	if body == null or not body.is_in_group("player"):
		return
	if mode == "to_planet":
		if not GameState.can_travel_to_lime_planet():
			GameState.add_log("The Stargate is not locked to the lime planet yet.")
			return
		_transitioning = true
		GameState.add_log("You step through the active Stargate to the lime planet.")
		await SceneRouter.change_to(target_scene, target_spawn)
		return
	if mode == "to_ship":
		if GameState.quest_step == GameState.QUEST_MINE_LIME and not GameState.has_resource(
				GameState.AIR_LIME_RESOURCE,
				GameState.AIR_LIME_REQUIRED
			):
			GameState.add_log("The planet gate is active, but leaving without enough lime will not fix the scrubber.")
			return
		_transitioning = true
		GameState.return_from_lime_planet()
		await SceneRouter.change_to(target_scene, target_spawn)
