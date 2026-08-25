extends Node

# @no-save: input remapping preferences persisted via user://settings.cfg
# under the [input_remap] section — independent of the gameplay save pipeline.
#
# Full keyboard + controller remapping system. Players can rebind any
# InputMap action to a different key or controller button. Remaps are
# persisted and restored on boot. The system:
#   1. Stores custom bindings per action as physical_keycode / joypad button
#   2. Overrides the InputMap at runtime when a remap exists
#   3. Restores the original (project.godot) bindings as fallback
#   4. Provides a rebind UI: "press any key" capture mode

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "input_remap"

signal action_rebound(action: String, event: InputEvent)
signal remaps_restored()

# Remappable actions (excludes movement axes which use stick motion).
const REMAPPABLE_ACTIONS: Array[String] = [
	"jump", "interact", "sprint", "kino_remote", "kino_autopilot",
	"pause", "quest_log", "toggle_map", "inventory", "character_pane",
	"crew_viewer", "crouch", "crawl_toggle", "cancel_target",
	"kino_descend", "zoom_in", "zoom_out",
	"camera_left", "camera_right", "camera_up", "camera_down",
]

# Stored remaps: action -> Dictionary with "type" (key/joypad), " keycode/button_index
var _remaps: Dictionary = {}
# Cache of original InputMap bindings so we can restore them.
var _original_bindings: Dictionary = {}


func _ready() -> void:
	# Cache original bindings for all remappable actions.
	for action in REMAPPABLE_ACTIONS:
		if InputMap.has_action(action):
			_original_bindings[action] = InputMap.action_get_events(action).duplicate()
	load_from_disk()
	_apply_all_remaps()


# Rebind an action to a new input event. Replaces the keyboard OR joypad
# event on the given action. The other device type's bindings are preserved.
func rebind(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		return false
	if not REMAPPABLE_ACTIONS.has(action):
		return false

	# Determine which device type this event is.
	var is_key: bool = event is InputEventKey
	var is_joypad: bool = event is InputEventJoypadButton
	if not is_key and not is_joypad:
		return false

	# Remove existing events of the same type from the action.
	var existing := InputMap.action_get_events(action)
	for ev in existing:
		if is_key and ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
		elif is_joypad and ev is InputEventJoypadButton:
			InputMap.action_erase_event(action, ev)

	# Add the new event.
	InputMap.action_add_event(action, event)

	# Store the remap.
	if is_key:
		var key_event: InputEventKey = event as InputEventKey
		_remaps[action] = {
			"type": "key",
			"physical_keycode": key_event.physical_keycode,
		}
	elif is_joypad:
		var joy_event: InputEventJoypadButton = event as InputEventJoypadButton
		_remaps[action] = {
			"type": "joypad",
			"button_index": joy_event.button_index,
		}

	action_rebound.emit(action, event)
	save_to_disk()
	return true


# Reset a single action to its original project.godot bindings.
func reset_action(action: String) -> void:
	if not _original_bindings.has(action):
		return
	# Erase all current events.
	for ev in InputMap.action_get_events(action):
		InputMap.action_erase_event(action, ev)
	# Restore originals.
	for ev in _original_bindings[action]:
		InputMap.action_add_event(action, ev)
	_remaps.erase(action)
	save_to_disk()


# Reset all actions to their original bindings.
func reset_all() -> void:
	for action in _original_bindings.keys():
		for ev in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, ev)
		for ev in _original_bindings[action]:
			InputMap.action_add_event(action, ev)
	_remaps.clear()
	save_to_disk()
	remaps_restored.emit()


# Get a human-readable label for the current binding of an action.
func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	var ev: InputEvent = events[0]
	if ev is InputEventKey:
		var key: InputEventKey = ev as InputEventKey
		return OS.get_keycode_string(key.physical_keycode)
	if ev is InputEventJoypadButton:
		var joy: InputEventJoypadButton = ev as InputEventJoypadButton
		return "Joy " + str(joy.button_index)
	return "—"


# Get the stored remap type for an action (for UI display).
func get_remap_info(action: String) -> Dictionary:
	return _remaps.get(action, {})


func has_remap(action: String) -> bool:
	return _remaps.has(action)


# ── Application ───────────────────────────────────────────────────────────────────

func _apply_all_remaps() -> void:
	for action in _remaps.keys():
		_apply_remap(action, _remaps[action])


func _apply_remap(action: String, info: Dictionary) -> void:
	if not InputMap.has_action(action):
		return
	var type: String = String(info.get("type", ""))
	if type == "key":
		var keycode: int = int(info.get("physical_keycode", 0))
		if keycode == 0:
			return
		# Remove existing key events.
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		# Create and add the new key event.
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action, key_event)
	elif type == "joypad":
		var button_index: int = int(info.get("button_index", -1))
		if button_index < 0:
			return
		# Remove existing joypad button events.
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				InputMap.action_erase_event(action, ev)
		# Create and add the new joypad event.
		var joy_event := InputEventJoypadButton.new()
		joy_event.button_index = button_index
		InputMap.action_add_event(action, joy_event)


# ── Persistence ─────────────────────────────────────────────────────────────────────

func load_from_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	# All remaps are stored as "action_type" = value keys.
	for action in REMAPPABLE_ACTIONS:
		var key_key := action + "_key"
		var joy_key := action + "_joypad"
		if cfg.has_section_key(SECTION, key_key):
			_remaps[action] = {
				"type": "key",
				"physical_keycode": int(cfg.get_value(SECTION, key_key)),
			}
		elif cfg.has_section_key(SECTION, joy_key):
			_remaps[action] = {
				"type": "joypad",
				"button_index": int(cfg.get_value(SECTION, joy_key)),
			}


func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for action in _remaps.keys():
		var info: Dictionary = _remaps[action]
		var type: String = String(info.get("type", ""))
		if type == "key":
			cfg.set_value(SECTION, action + "_key", int(info.get("physical_keycode", 0)))
			# Clear any stale joypad entry for this action.
			if cfg.has_section_key(SECTION, action + "_joypad"):
				cfg.erase_section_key(SECTION, action + "_joypad")
		elif type == "joypad":
			cfg.set_value(SECTION, action + "_joypad", int(info.get("button_index", -1)))
			if cfg.has_section_key(SECTION, action + "_key"):
				cfg.erase_section_key(SECTION, action + "_key")
	cfg.save(SETTINGS_PATH)