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

# True if the alert should be active right now. The red alert runs from the
# moment the air crisis starts until the venting breach is sealed. Once the
# Shuttle Dock door is shut the lights go back to normal even though O2 stays
# low — the CO2 scrubber repair is a later beat (Phase D), tracked separately
# from the hull breach.
static func is_alert_active() -> bool:
	if not GameState.air_crisis_started:
		return false
	return GameState.breaches_sealed.is_empty()


# Apply the red-alert tint to every light + emissive material + the
# WorldEnvironment under `scene_root`. Idempotent within a single call:
# materials are tracked in a Dictionary so a shared material referenced by
# multiple meshes (per-accent palette in room_builder.gd) gets tinted once,
# not N times. The pre-tint value is stashed in node/material/env metadata so
# clear_scene can restore it.
static func apply_to_scene(scene_root: Node) -> void:
	if scene_root == null:
		return
	_walk_lights(scene_root)
	var tinted_mats: Dictionary = {}
	_tint_emissives(scene_root, tinted_mats)
	_tint_environment(scene_root)


# Revert a scene previously tinted by apply_to_scene. Reads the originals
# stashed in metadata during apply, so only values we actually changed get
# restored. Safe to call on an untinted scene (no metadata → no-op).
static func clear_scene(scene_root: Node) -> void:
	if scene_root == null:
		return
	_restore_lights(scene_root)
	_restore_emissives(scene_root)
	_restore_environment(scene_root)


static func _walk_lights(node: Node) -> void:
	if node is OmniLight3D or node is SpotLight3D or node is DirectionalLight3D:
		var light: Light3D = node
		if not light.has_meta("alert_orig_color"):
			light.set_meta("alert_orig_color", light.light_color)
		light.light_color = light.light_color.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND)
	for c in node.get_children():
		_walk_lights(c)


static func _restore_lights(node: Node) -> void:
	if node is Light3D and node.has_meta("alert_orig_color"):
		var light: Light3D = node
		light.light_color = light.get_meta("alert_orig_color")
		light.remove_meta("alert_orig_color")
	for c in node.get_children():
		_restore_lights(c)


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
				if not smat.has_meta("alert_orig_emission"):
					smat.set_meta("alert_orig_emission", smat.emission)
					smat.set_meta("alert_orig_albedo", smat.albedo_color)
				smat.emission = smat.emission.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND)
				smat.albedo_color = smat.albedo_color.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND * 0.7)
				tinted[smat] = true
	for c in node.get_children():
		_tint_emissives(c, tinted)


static func _restore_emissives(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mat: Variant = mi.material_override
		if mat is StandardMaterial3D:
			var smat: StandardMaterial3D = mat
			if smat.has_meta("alert_orig_emission"):
				smat.emission = smat.get_meta("alert_orig_emission")
				smat.albedo_color = smat.get_meta("alert_orig_albedo")
				smat.remove_meta("alert_orig_emission")
				smat.remove_meta("alert_orig_albedo")
	for c in node.get_children():
		_restore_emissives(c)


# Find the WorldEnvironment node in the scene and replace its env Resource
# with a red-tinted duplicate. Duplication is critical — the env resource is
# shared (destiny-interior-environment.tres) so mutating it directly would
# bleed the tint into every scene the player visits later.
static func _tint_environment(scene_root: Node) -> void:
	var we: WorldEnvironment = _find_world_environment(scene_root)
	if we == null or we.environment == null:
		return
	if not we.has_meta("alert_orig_env"):
		we.set_meta("alert_orig_env", we.environment)
	var alert_env: Environment = we.environment.duplicate()
	alert_env.ambient_light_color = ALERT_AMBIENT_COLOR
	we.environment = alert_env


static func _restore_environment(scene_root: Node) -> void:
	var we: WorldEnvironment = _find_world_environment(scene_root)
	if we == null or not we.has_meta("alert_orig_env"):
		return
	we.environment = we.get_meta("alert_orig_env")
	we.remove_meta("alert_orig_env")


static func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for c in node.get_children():
		var found: WorldEnvironment = _find_world_environment(c)
		if found != null:
			return found
	return null
