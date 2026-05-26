class_name ShipAlert
extends Object

# Static helpers for applying / clearing the "red alert" visual state across a
# scene tree. Called by room.gd / gate_room.gd in _ready after their
# geometry is built, so a scene loaded while air_crisis_started=true comes
# up already tinted instead of flashing yellow-to-red on entry.

# Red alert palette — dramatic but readable. Not pure red (1,0,0) — softens
# to a warm-red so character silhouettes still read against the walls.
const ALERT_LIGHT_COLOR: Color = Color(1.0, 0.20, 0.15)
const ALERT_AMBIENT_COLOR: Color = Color(0.62, 0.18, 0.14)
# How much the alert tint overrides the original light_color (0 = no
# change, 1 = full override). Slight blend keeps a hint of the original
# accent so room identity reads through.
const ALERT_LIGHT_BLEND: float = 0.92

# True if the alert should be active right now.
static func is_alert_active() -> bool:
	if not GameState.air_crisis_started:
		return false
	if GameState.scrubber_repaired:
		return false
	return true


# Apply the red-alert tint to every light + emissive material + the
# WorldEnvironment under `scene_root`. Idempotent within a single call:
# materials are tracked in a Dictionary so a shared material referenced by
# multiple meshes (per-accent palette in room_builder.gd) gets tinted once,
# not N times.
static func apply_to_scene(scene_root: Node) -> void:
	if scene_root == null:
		return
	_walk_lights(scene_root)
	var tinted_mats: Dictionary = {}
	_tint_emissives(scene_root, tinted_mats)
	_tint_environment(scene_root)


static func _walk_lights(node: Node) -> void:
	if node is OmniLight3D or node is SpotLight3D or node is DirectionalLight3D:
		var light: Light3D = node
		light.light_color = light.light_color.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND)
	for c in node.get_children():
		_walk_lights(c)


# Walk every MeshInstance3D's material_override and re-paint its emission
# color toward alert red. Wall sconces, console screens, hydroponics grow
# lights, corridor strips — all use emissive StandardMaterial3D and all
# dominate the room's perceived colour far more than the OmniLight3D pools
# do. Tinting only the lights leaves the room looking warm-amber.
#
# `tinted` is the per-scene dedup map: shared materials get tinted once.
# RoomBuilder creates fresh material instances every scene build so the
# tint doesn't bleed across rooms — when the player returns to a non-alert
# state (scrubber repaired) the next room build comes up pristine.
static func _tint_emissives(node: Node, tinted: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mat: Variant = mi.material_override
		if mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat
			if smat.emission_enabled and not tinted.has(smat):
				smat.emission = smat.emission.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND)
				smat.albedo_color = smat.albedo_color.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND * 0.7)
				tinted[smat] = true
	for c in node.get_children():
		_tint_emissives(c, tinted)


# Find the WorldEnvironment node in the scene and replace its env Resource
# with a red-tinted duplicate. Duplication is critical — the env resource is
# shared (destiny-interior-environment.tres) so mutating it directly would
# bleed the tint into every scene the player visits later.
static func _tint_environment(scene_root: Node) -> void:
	var we: WorldEnvironment = _find_world_environment(scene_root)
	if we == null or we.environment == null:
		return
	var alert_env: Environment = we.environment.duplicate()
	alert_env.ambient_light_color = ALERT_AMBIENT_COLOR
	we.environment = alert_env


static func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for c in node.get_children():
		var found: WorldEnvironment = _find_world_environment(c)
		if found != null:
			return found
	return null
