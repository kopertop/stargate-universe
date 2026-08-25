class_name ShipAlert
extends Node

# Static helpers for applying / clearing multi-level emergency lighting states
# across a scene tree. Called by room.gd / gate_room.gd in _ready after their
# geometry is built, so a scene loaded while a crisis is active comes up
# already tinted instead of flashing on entry.
#
# Three emergency levels, each with a distinct visual language:
#
#   CAUTION  — post-crisis, scrubber damaged. Lights dimmed to 70%, ambient
#             reduced, subtle amber fog tint. Ancient tech pulses faster.
#             Called via: set_caution(scene_root)
#
#   ALERT   — air crisis active, breach unsealed. Red tint on all lights +
#             emissives + ambient. Alert pulse: lights flicker 80-100% at
#             0.5s intervals. The dramatic emergency state.
#             Called via: apply_to_scene(scene_root)
#
#   BLACKOUT — gate collapse / power failure. All lights crushed to ~12%,
#             ambient to 10%, emissive strips to 4%. Flashlight spots from
#             perimeter. Recovery tweens lights back up.
#             Gate room uses its own _collapse_blackout() for this; the
#             generic version here is set_blackout(scene_root).
#
# The red alert runs from the moment the air crisis starts until the venting
# breach is sealed. Once the Shuttle Dock door is shut the lights go back to
# normal even though O2 stays low — the CO2 scrubber repair is a later beat
# (Phase D), tracked separately from the hull breach.

# --- Red Alert palette ----------------------------------------------------
# Dramatic but readable. Not pure red (1,0,0) — softens to a warm-red so
# character silhouettes still read against the walls.
const ALERT_LIGHT_COLOR: Color = Color(1.0, 0.20, 0.15)
const ALERT_AMBIENT_COLOR: Color = Color(0.62, 0.18, 0.14)
# How much the alert tint overrides the original light_color (0 = no
# change, 1 = full override). Slight blend keeps a hint of the original
# accent so room identity reads through.
const ALERT_LIGHT_BLEND: float = 0.92
# Alert pulse: lights flicker between these multipliers at PULSE_INTERVAL.
const ALERT_PULSE_LOW: float = 0.80
const ALERT_PULSE_HIGH: float = 1.0
const ALERT_PULSE_INTERVAL: float = 0.5

# --- Caution palette ------------------------------------------------------
# Post-crisis dim state. Lights dimmed, ambient reduced, warm tint.
const CAUTION_LIGHT_MULTIPLIER: float = 0.70
const CAUTION_AMBIENT_MULTIPLIER: float = 0.65
const CAUTION_FOG_TINT: Color = Color(0.45, 0.35, 0.20)

# --- Blackout palette -----------------------------------------------------
const BLACKOUT_LIGHT_MULTIPLIER: float = 0.12
const BLACKOUT_AMBIENT_MULTIPLIER: float = 0.10
const BLACKOUT_EMISSIVE_MULTIPLIER: float = 0.04

# --- Internal: pulse timer for alert flicker ------------------------------
var _pulse_time: float = 0.0
var _pulse_high: bool = true
static var _active_alert_nodes: Array[Node] = []

# True if the red alert should be active right now.
static func is_alert_active() -> bool:
	if not GameState.air_crisis_started:
		return false
	return GameState.breaches_sealed.is_empty()


# True if caution state should be active (scrubber damaged, post-breach).
static func is_caution_active() -> bool:
	# Caution runs after the breach is sealed but while the CO2 scrubber
	# is still broken. Falls back to: air_crisis started but no breach.
	if not GameState.air_crisis_started:
		return false
	if not GameState.breaches_sealed.is_empty():
		# Breach sealed — caution if scrubber still broken
		return not GameState.scrubber_repaired
	return false


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
	# Tag for pulse tracking
	scene_root.set_meta("alert_state", "alert")


# Apply caution dimming to a scene (post-crisis, scrubber damaged).
static func set_caution(scene_root: Node) -> void:
	if scene_root == null:
		return
	_dim_lights(scene_root, CAUTION_LIGHT_MULTIPLIER)
	_dim_ambient(scene_root, CAUTION_AMBIENT_MULTIPLIER)
	scene_root.set_meta("alert_state", "caution")


# Apply blackout to a scene (power failure / gate collapse).
# Unlike gate_room.gd's _collapse_blackout, this is a fire-and-forget
# static method for generic rooms. Recovery is handled by clear_scene
# or by the room rebuilding on next entry.
static func set_blackout(scene_root: Node) -> void:
	if scene_root == null:
		return
	_dim_lights(scene_root, BLACKOUT_LIGHT_MULTIPLIER)
	_dim_ambient(scene_root, BLACKOUT_AMBIENT_MULTIPLIER)
	# Tag for ancient_glow.gd to detect
	scene_root.set_meta("blackout_active", true)
	scene_root.set_meta("alert_state", "blackout")


# Clear blackout tag (lets ancient_glow resume pulsing).
static func clear_blackout(scene_root: Node) -> void:
	if scene_root == null:
		return
	scene_root.remove_meta("blackout_active")
	scene_root.set_meta("alert_state", "normal")


# Revert a scene previously tinted by apply_to_scene. Reads the originals
# stashed in metadata during apply, so only values we actually changed get
# restored. Safe to call on an untinted scene (no metadata → no-op).
static func clear_scene(scene_root: Node) -> void:
	if scene_root == null:
		return
	_restore_lights(scene_root)
	_restore_emissives(scene_root)
	_restore_environment(scene_root)
	scene_root.remove_meta("alert_state")


# --- Alert pulse -----------------------------------------------------------
# Call from a room's _process to drive the alert flicker. Only flickers
# lights in scenes tagged with alert_state == "alert".
static func process_alert_pulse(scene_root: Node, delta: float) -> void:
	if scene_root == null:
		return
	if not scene_root.has_meta("alert_state"):
		return
	var state: String = scene_root.get_meta("alert_state")
	if state != "alert":
		return
	var pulse_timer: float = scene_root.get_meta("pulse_timer", 0.0) + delta
	if pulse_timer < ALERT_PULSE_INTERVAL:
		scene_root.set_meta("pulse_timer", pulse_timer)
		return
	scene_root.set_meta("pulse_timer", 0.0)
	_toggle_alert_pulse(scene_root)


static func _toggle_alert_pulse(scene_root: Node) -> void:
	var high: bool = scene_root.get_meta("pulse_high", true)
	var target_mult: float = ALERT_PULSE_HIGH if high else ALERT_PULSE_LOW
	scene_root.set_meta("pulse_high", not high)
	_apply_pulse_level(scene_root, target_mult)


static func _apply_pulse_level(scene_root: Node, multiplier: float) -> void:
	for ln: Node in scene_root.find_children("*", "Light3D", true, false):
		var light: Light3D = ln as Light3D
		if light == null or not light.has_meta("alert_orig_energy"):
			continue
		var orig: float = light.get_meta("alert_orig_energy")
		light.light_energy = orig * multiplier


# --- Light walking (alert tint) --------------------------------------------
static func _walk_lights(node: Node) -> void:
	if node is OmniLight3D or node is SpotLight3D or node is DirectionalLight3D:
		var light: Light3D = node
		if not light.has_meta("alert_orig_color"):
			light.set_meta("alert_orig_color", light.light_color)
		if not light.has_meta("alert_orig_energy"):
			light.set_meta("alert_orig_energy", light.light_energy)
		light.light_color = light.light_color.lerp(ALERT_LIGHT_COLOR, ALERT_LIGHT_BLEND)
	for c in node.get_children():
		_walk_lights(c)


static func _restore_lights(node: Node) -> void:
	if node is Light3D and node.has_meta("alert_orig_color"):
		var light: Light3D = node
		light.light_color = light.get_meta("alert_orig_color")
		light.remove_meta("alert_orig_color")
	if node is Light3D and node.has_meta("alert_orig_energy"):
		var light2: Light3D = node
		light2.light_energy = light2.get_meta("alert_orig_energy")
		light2.remove_meta("alert_orig_energy")
	for c in node.get_children():
		_restore_lights(c)


# --- Caution / Blackout dimming helpers -----------------------------------
# Dim all Light3D nodes to `multiplier` of their original energy. Stashes
# the original in metadata so it can be restored by clear_scene.
static func _dim_lights(scene_root: Node, multiplier: float) -> void:
	for ln: Node in scene_root.find_children("*", "Light3D", true, false):
		var light: Light3D = ln as Light3D
		if light == null:
			continue
		if not light.has_meta("alert_orig_energy"):
			light.set_meta("alert_orig_energy", light.light_energy)
		light.light_energy = light.get_meta("alert_orig_energy") * multiplier


# Dim the WorldEnvironment ambient energy to `multiplier`. Duplicates the
# env resource so the shared .tres file isn't mutated.
static func _dim_ambient(scene_root: Node, multiplier: float) -> void:
	var we: WorldEnvironment = _find_world_environment(scene_root)
	if we == null or we.environment == null:
		return
	if not we.has_meta("alert_orig_env"):
		we.set_meta("alert_orig_env", we.environment)
	var dim_env: Environment = we.environment.duplicate()
	var base_energy: float = 1.2
	if we.get_meta("alert_orig_env") is Environment:
		base_energy = (we.get_meta("alert_orig_env") as Environment).ambient_light_energy
	dim_env.ambient_light_energy = base_energy * multiplier
	we.environment = dim_env


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
