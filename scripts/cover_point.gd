class_name CoverPoint
extends Area3D

## An Area3D placed in levels that marks a cover position. When the player
## enters the area, CombatSystem registers them as "in cover" — reducing
## enemy hit chance (incoming fire is more likely to hit the cover object
## instead of the player).
##
## Properties:
##   cover_height     — LOW (crouch cover) or HIGH (standing cover)
##   cover_direction  — Vector3 facing AWAY from the threat direction.
##                      The cover protects from incoming fire originating
##                      from the opposite direction (i.e. -cover_direction).
##
## Placement: drop a CoverPoint node in the scene, position it where the
## player should stand, rotate it so cover_direction points toward the
## threat. The Area3D collision shape defines the trigger volume.
##
## CoverPoints auto-register with the scene's CoverRegistry on _ready.

enum CoverHeight { LOW, HIGH }

@export var cover_height: CoverHeight = CoverHeight.LOW
@export var cover_direction: Vector3 = Vector3.FORWARD

const _COVER_REGISTRY_SCRIPT: Script = preload("res://scripts/cover_registry.gd")

var _registry: Node = null


func _ready() -> void:
	# Add to cover_point group so the registry can find us via group queries
	# even if the registry hasn't been created yet.
	add_to_group("cover_point")
	# Find or create the CoverRegistry in this scene.
	_registry = _find_or_create_registry()
	if _registry != null:
		_registry.call("register_cover", self)


func _exit_tree() -> void:
	if _registry != null and is_instance_valid(_registry):
		_registry.call("unregister_cover", self)


## Returns true if this cover point protects against a threat coming from
## `threat_position`. The cover_direction must face roughly toward the threat
## (dot product > 0 means the cover is facing the right way).
func protects_from(threat_position: Vector3) -> bool:
	var to_threat: Vector3 = (threat_position - global_position).normalized()
	var facing: Vector3 = cover_direction.normalized()
	# cover_direction faces AWAY from threat, so the threat should be in
	# the -cover_direction hemisphere. If cover_direction points "forward"
	# (away from threat), then to_threat should be roughly -facing.
	return to_threat.dot(-facing) > 0.3


## Returns the cover height as a float for damage-mitigation calculations.
## LOW cover reduces hit chance by 40%, HIGH by 70%.
func cover_factor() -> float:
	if cover_height == CoverHeight.HIGH:
		return 0.3  # 70% protection
	return 0.6  # 40% protection


func _find_or_create_registry() -> Node:
	# Look for an existing CoverRegistry in the scene tree.
	var existing: Array[Node] = get_tree().get_nodes_in_group("cover_registry")
	if not existing.is_empty():
		return existing[0]
	# Also check direct children of the scene root.
	var parent: Node = get_parent()
	while parent != null:
		for child in parent.get_children():
			if child.get_script() == _COVER_REGISTRY_SCRIPT:
				return child
		parent = parent.get_parent()
	# Create one and add it to the scene root.
	var reg: Node = _COVER_REGISTRY_SCRIPT.new()
	reg.name = "CoverRegistry"
	reg.add_to_group("cover_registry")
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(reg)
		return reg
	return null