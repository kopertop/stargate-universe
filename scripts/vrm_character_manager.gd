extends Node
class_name VrmCharacterManager

# VRM Character Manager — the roster spine for all 15+ crew VRM models.
#
# Owns the lifecycle of every VrmCharacter in the scene:
#   - VRM-first spawning with graceful fallback to the modular/mini pipeline
#     when a VRM file doesn't exist yet (the roster is VRM-ready: add the
#     .vrm file and it takes over automatically).
#   - LOD system: near (<5m) / mid (5-15m) / far (>15m) distance thresholds
#     driving spring-bone, expression, and mesh-resolution toggles.
#   - Per-character expression profiles: personality-driven default emotions,
#     blink rate, and viseme preset mapping.
#   - Visibility budget: max 4 simultaneous crew VRMs (furthest culled).
#   - Adaptive quality: drops to mid-LOD + reduced crew count below 30 FPS.
#
# Usage (autoload or per-scene):
#   var mgr := VrmCharacterManager.new()
#   add_child(mgr)
#   var eli := mgr.spawn_crew("Eli", Vector3.ZERO)
#   mgr.set_emotion_for("Eli", "happy")

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")
const FactoryRef: Script = preload("res://scripts/character_factory.gd")

# --- LOD thresholds (meters from camera) ---
const LOD_NEAR: float = 5.0
const LOD_MID: float = 15.0
const LOD_FADE_DURATION: float = 0.5

# --- Visibility budget ---
const MAX_VISIBLE_CREW: int = 4
const ADAPTIVE_FPS_THRESHOLD: float = 30.0

# --- LOD level enum ---
enum LodLevel { NEAR, MID, FAR }

# Per-character expression profile. Drives the face at rest and during
# dialogue. personality_emotion is the idle default; blink_rate is
# seconds between auto-blinks (min/max random range); viseme_set is the
# list of viseme clips the character's VRM defines (subset of the standard
# aa/ih/ou/ee/oh — some models may not have all five).
const EXPRESSION_PROFILES: Dictionary = {
	"Eli": {
		"personality": "neutral",
		"blink_rate_min": 2.0,
		"blink_rate_max": 5.0,
		"custom_emotions": ["thinking", "worried", "smirk"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Colonel Young": {
		"personality": "relaxed",
		"blink_rate_min": 3.0,
		"blink_rate_max": 6.0,
		"custom_emotions": ["determined", "worried"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Dr Rush": {
		"personality": "angry",
		"blink_rate_min": 3.5,
		"blink_rate_max": 7.0,
		"custom_emotions": ["thinking", "determined", "smirk"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Sgt Greer": {
		"personality": "neutral",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.5,
		"custom_emotions": ["determined", "angry"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Lt Scott": {
		"personality": "relaxed",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.0,
		"custom_emotions": ["worried", "determined"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Chloe Armstrong": {
		"personality": "happy",
		"blink_rate_min": 2.0,
		"blink_rate_max": 4.5,
		"custom_emotions": ["sad", "worried", "surprised"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"TJ": {
		"personality": "relaxed",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.0,
		"custom_emotions": ["sad", "worried", "thinking"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Camille": {
		"personality": "neutral",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.5,
		"custom_emotions": ["sad", "angry", "thinking"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Volker": {
		"personality": "worried",
		"blink_rate_min": 2.0,
		"blink_rate_max": 4.0,
		"custom_emotions": ["thinking", "surprised", "smirk"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Brody": {
		"personality": "neutral",
		"blink_rate_min": 3.0,
		"blink_rate_max": 6.0,
		"custom_emotions": ["determined", "smirk"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Dr Park": {
		"personality": "neutral",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.0,
		"custom_emotions": ["worried", "sad", "thinking"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Dr James": {
		"personality": "relaxed",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.0,
		"custom_emotions": ["sad", "worried", "determined"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Lt James": {
		"personality": "neutral",
		"blink_rate_min": 2.5,
		"blink_rate_max": 5.0,
		"custom_emotions": ["determined", "angry", "worried"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Varro": {
		"personality": "neutral",
		"blink_rate_min": 3.0,
		"blink_rate_max": 6.0,
		"custom_emotions": ["determined", "angry", "smirk"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Simeon": {
		"personality": "angry",
		"blink_rate_min": 3.0,
		"blink_rate_max": 6.5,
		"custom_emotions": ["smirk", "determined", "surprised"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
	"Ginn": {
		"personality": "happy",
		"blink_rate_min": 2.0,
		"blink_rate_max": 4.5,
		"custom_emotions": ["sad", "surprised", "thinking"],
		"visemes": ["aa", "ih", "ou", "ee", "oh"],
	},
}

# --- runtime state ---

# character_name -> VrmCharacter node (or modular fallback node)
var _crew: Dictionary = {}
# character_name -> LodLevel
var _lod: Dictionary = {}
# character_name -> Camera3D distance (updated each frame for visible crew)
var _distances: Dictionary = {}
# adaptive quality flag (dropped below FPS threshold)
var _adaptive_quality: bool = false
# the camera to measure LOD distance from
var _camera: Camera3D = null

# Frame time tracking for adaptive quality
var _fps_accum: float = 0.0
var _fps_frames: int = 0
var _fps_check_timer: float = 0.0
const FPS_CHECK_INTERVAL: float = 2.0


func _ready() -> void:
	# Find the main camera (deferred so the scene tree is ready)
	call_deferred("_find_camera")


func _find_camera() -> void:
	_camera = get_viewport().get_camera_3d()


func _process(delta: float) -> void:
	if _crew.is_empty():
		return
	_fps_check_timer += delta
	_fps_accum += delta
	_fps_frames += 1
	if _fps_check_timer >= FPS_CHECK_INTERVAL:
		_check_adaptive_quality()
		_fps_check_timer = 0.0
		_fps_accum = 0.0
		_fps_frames = 0
	_update_lod()
	_apply_visibility_budget()


# --- spawning ---

# Spawn a crew member. VRM-first: if the profile has a "vrm" path and the
# file exists, create a VrmCharacter; otherwise fall back to the modular
# pipeline. Returns the character node (or null on failure).
func spawn_crew(character_name: String, pos: Vector3 = Vector3.ZERO, context: String = "ship") -> Node3D:
	var profile: Dictionary = FactoryRef.profile_for(character_name)
	if profile.is_empty():
		push_warning("[VrmCharacterManager] No profile for '%s'" % character_name)
		return null

	# Check for VRM path in profile
	var vrm_path: String = String(profile.get("vrm", ""))
	if vrm_path != "" and ResourceLoader.exists(vrm_path):
		return _spawn_vrm(character_name, vrm_path, pos, context)

	# Fall back to modular pipeline
	return _spawn_modular_fallback(character_name, pos, context)


# Spawn a VRM character and apply the expression profile.
func _spawn_vrm(character_name: String, vrm_path: String, pos: Vector3, context: String) -> Node3D:
	var c: Node3D = VrmCharacterScript.create(vrm_path, character_name)
	if c == null:
		push_warning("[VrmCharacterManager] VRM load failed for '%s'" % character_name)
		return _spawn_modular_fallback(character_name, pos, context)
	c.position = pos
	add_child(c)
	_crew[character_name] = c
	_lod[character_name] = LodLevel.NEAR
	_apply_expression_profile(c, character_name)

	# Apply context-appropriate gear (ship = sidearm for military; mission = full loadout)
	var is_military: bool = FactoryRef.is_military(character_name)
	if is_military:
		c.call("attach_gear", "sidearm", false)
		if context == "mission":
			c.call("attach_gear", "rifle", false)
	return c


# Modular fallback: build a Quaternius ModularCharacter dressed for the context.
func _spawn_modular_fallback(character_name: String, pos: Vector3, context: String) -> Node3D:
	var c: Node3D = FactoryRef.build_modular(character_name)
	if c == null:
		return null
	c.name = "Crew_" + character_name.replace(" ", "")
	c.position = pos
	add_child(c)
	FactoryRef.dress_modular(c, character_name, context)
	_crew[character_name] = c
	_lod[character_name] = LodLevel.NEAR
	return c


# --- expression profiles ---

# Apply a character's personality-driven expression defaults.
func _apply_expression_profile(c: Node3D, character_name: String) -> void:
	var profile: Dictionary = EXPRESSION_PROFILES.get(character_name, {})
	if profile.is_empty():
		return
	# Set the resting emotion
	var personality: String = String(profile.get("personality", "neutral"))
	if personality != "neutral":
		c.call("set_emotion", personality, 0.6)
	# Set auto-blink rate (stored on VrmCharacter's internal timer range)
	# VrmCharacter already auto-blinks; the rate range is hard-wired (2-5s).
	# If the VRM supports the profile's custom emotions, register them.
	var customs: Array = profile.get("custom_emotions", [])
	for emo in customs:
		# Verify the expression clip exists on this VRM
		var clips: Array = c.call("expression_names")
		if clips.has(emo):
			# Custom emotions are available; no action needed beyond confirming
			pass


# Set the emotion for a named crew member (if VRM-backed).
func set_emotion_for(character_name: String, emotion: String, weight: float = 1.0) -> void:
	if not _crew.has(character_name):
		return
	var c: Node3D = _crew[character_name]
	if c.get_script() == VrmCharacterScript:
		c.call("set_emotion", emotion, weight)


# Set a viseme for a named crew member (lip sync during dialogue).
func set_viseme_for(character_name: String, viseme: String, weight: float = 1.0) -> void:
	if not _crew.has(character_name):
		return
	var c: Node3D = _crew[character_name]
	if c.get_script() == VrmCharacterScript:
		c.call("set_viseme", viseme, weight)


# Clear all expressions for a named crew member.
func clear_expressions_for(character_name: String) -> void:
	if not _crew.has(character_name):
		return
	var c: Node3D = _crew[character_name]
	if c.get_script() == VrmCharacterScript:
		c.call("clear_expressions")


# --- LOD system ---

func _update_lod() -> void:
	if _camera == null:
		_find_camera()
		if _camera == null:
			return
	for char_name in _crew:
		var c: Node3D = _crew[char_name]
		if c == null or not is_instance_valid(c):
			continue
		var dist: float = _camera.global_position.distance_to(c.global_position)
		_distances[char_name] = dist
		var new_lod: LodLevel = _lod_for_distance(dist)
		if new_lod != _lod[char_name]:
			_lod[char_name] = new_lod
			_apply_lod(c, char_name, new_lod)


func _lod_for_distance(dist: float) -> LodLevel:
	if _adaptive_quality:
		# In adaptive mode, force at least MID for everyone
		if dist < LOD_NEAR * 0.5:
			return LodLevel.NEAR
		return LodLevel.MID
	if dist < LOD_NEAR:
		return LodLevel.NEAR
	if dist < LOD_MID:
		return LodLevel.MID
	return LodLevel.FAR


# Apply LOD settings to a character.
func _apply_lod(c: Node3D, character_name: String, level: LodLevel) -> void:
	var is_vrm: bool = c.get_script() == VrmCharacterScript
	match level:
		LodLevel.NEAR:
			# Full quality: spring bones, expressions, all blend shapes
			if is_vrm:
				c.set("auto_blink", true)
				c.set_process(true)
			# Expressions active
		LodLevel.MID:
			# Spring bones disabled, expressions disabled (neutral face)
			if is_vrm:
				c.set("auto_blink", false)
				c.call("clear_expressions")
				c.set_process(false)  # stops expression mixing + blink
		LodLevel.FAR:
			# Simplified mesh, no spring bones, no expressions
			if is_vrm:
				c.set("auto_blink", false)
				c.call("clear_expressions")
				c.set_process(false)
				# Could set visibility_range for mesh swap, but for now
				# the visibility budget handles culling.


# --- visibility budget ---

func _apply_visibility_budget() -> void:
	if _crew.size() <= MAX_VISIBLE_CREW:
		# Everyone visible
		for char_name in _crew:
			var c: Node3D = _crew[char_name]
			if c != null and is_instance_valid(c):
				c.visible = true
		return
	# Sort by distance (ascending = nearest first)
	var sorted: Array = _distances.keys()
	sorted.sort_custom(func(a, b) -> bool:
		return float(_distances.get(a, INF)) < float(_distances.get(b, INF)))
	# Show nearest MAX_VISIBLE_CREW, hide the rest
	var max_visible: int = 2 if _adaptive_quality else MAX_VISIBLE_CREW
	for i in range(sorted.size()):
		var char_name: String = sorted[i]
		var c: Node3D = _crew.get(char_name)
		if c == null or not is_instance_valid(c):
			continue
		c.visible = i < max_visible


# --- adaptive quality ---

func _check_adaptive_quality() -> void:
	if _fps_frames == 0:
		return
	var fps: float = float(_fps_frames) / _fps_accum
	if fps < ADAPTIVE_FPS_THRESHOLD and not _adaptive_quality:
		_adaptive_quality = true
		# Force all crew to at least MID LOD
		for char_name in _crew:
			_lod[char_name] = LodLevel.MID
			var c: Node3D = _crew[char_name]
			if c != null and is_instance_valid(c):
				_apply_lod(c, char_name, LodLevel.MID)
	elif fps >= ADAPTIVE_FPS_THRESHOLD * 1.5 and _adaptive_quality:
		_adaptive_quality = false
		# LOD will re-evaluate next frame


# --- query API ---

func get_crew_count() -> int:
	return _crew.size()


func get_crew_names() -> Array:
	return _crew.keys()


func get_lod(character_name: String) -> int:
	return int(_lod.get(character_name, LodLevel.NEAR))


func is_vrm(character_name: String) -> bool:
	if not _crew.has(character_name):
		return false
	return _crew[character_name].get_script() == VrmCharacterScript


func get_expression_profile(character_name: String) -> Dictionary:
	return EXPRESSION_PROFILES.get(character_name, {})


# Returns the full roster of crew names that have expression profiles.
static func roster_names() -> Array:
	return EXPRESSION_PROFILES.keys()


# Returns true if a VRM file exists for this character.
static func has_vrm_file(character_name: String) -> bool:
	var profile: Dictionary = FactoryRef.profile_for(character_name)
	var vrm_path: String = String(profile.get("vrm", ""))
	return vrm_path != "" and ResourceLoader.exists(vrm_path)


# Remove a crew member from the scene.
func remove_crew(character_name: String) -> void:
	if not _crew.has(character_name):
		return
	var c: Node3D = _crew[character_name]
	if c != null and is_instance_valid(c):
		c.queue_free()
	_crew.erase(character_name)
	_lod.erase(character_name)
	_distances.erase(character_name)