extends Node

# @no-save: controller preferences (per-device face-button layout) are persisted
# via the shared user://settings.cfg ConfigFile under a [gamepad] section —
# independent of the gameplay save pipeline, exactly like the Settings autoload.
# Holds no gameplay state.
#
# Gamepad — native controller support for Stargate Universe.
#
# The game is DESIGNED for the gamepad (issue #34): left stick moves, right stick
# looks, the four face buttons + shoulders + triggers drive every gameplay verb,
# and WASD + mouse are the secondary fallback. The static joypad bindings live in
# project.godot's [input] map; this autoload owns the DYNAMIC layer on top:
#
#   1. Connection tracking — which physical pad is "active" (most recently seen),
#      and a `controller_connected` / `controller_disconnected` signal pair so the
#      HUD can swap key glyphs for button glyphs.
#
#   2. Face-button remap — some controllers ship A/B and X/Y physically swapped
#      (Nintendo layout vs Xbox layout). The player presses the four face buttons
#      in a guided order (driven by GamepadConfigDialog) and we record which
#      PHYSICAL JoyButton index sits at each LOGICAL position (bottom/right/left/
#      top). We then rewrite the joypad button events on the affected InputMap
#      actions so "jump = bottom face button" holds regardless of vendor layout.
#
#   3. First-unknown-controller prompt — when a pad whose GUID we've never mapped
#      connects, `new_controller_detected` fires so the config dialog can offer the
#      mapping wizard. Known GUIDs re-apply their saved layout silently.
#
# Persistence: per-GUID layouts live in user://settings.cfg [gamepad] so they
# survive a save wipe and are shared across save slots (a preference, not state).

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "gamepad"

# Logical face-button positions, independent of vendor labels. "Bottom" is the
# A-position on Xbox / B-position on Nintendo, etc.
enum Face { BOTTOM, RIGHT, LEFT, TOP }

# Default PHYSICAL JoyButton index for each logical position — the Godot/SDL
# standard layout (Xbox-style), which is also what project.godot is authored
# against. A controller that matches this needs no remap.
const DEFAULT_FACE_BUTTON: Dictionary = {
	Face.BOTTOM: JOY_BUTTON_A,   # 0
	Face.RIGHT: JOY_BUTTON_B,    # 1
	Face.LEFT: JOY_BUTTON_X,     # 2
	Face.TOP: JOY_BUTTON_Y,      # 3
}

# Which InputMap actions are bound to which LOGICAL face position. Rewiring these
# is how a remap takes effect — we replace the action's joypad button event with
# the physical index the player assigned to that logical slot.
const FACE_ACTION: Dictionary = {
	"jump": Face.BOTTOM,         # bottom face = jump (A)
	"interact": Face.LEFT,       # left face = interact (X)
	"kino_autopilot": Face.TOP,  # top face = autopilot toggle (Y)
	"kino_remote": Face.RIGHT,   # right face = open Kino remote (B)
}

signal controller_connected(device: int, name: String)
signal controller_disconnected(device: int)
# Fired when a pad with a GUID we have no saved layout for connects, so the
# config dialog can offer the guided mapping wizard. Carries the device id.
signal new_controller_detected(device: int, guid: String, name: String)
# Fired after a layout is applied (saved or default) so listeners (HUD) refresh.
signal layout_applied(device: int)

# Most-recently-seen connected device, or -1 when none. The "active" pad for
# glyph display + remap targeting.
var active_device: int = -1
# Logical→physical face-button map currently applied to the InputMap.
var _face_map: Dictionary = DEFAULT_FACE_BUTTON.duplicate()


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# A pad already connected at boot won't fire the signal — seed from the
	# current connection list.
	for device in Input.get_connected_joypads():
		_register_device(device, true)


# --- connection lifecycle -------------------------------------------------

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_register_device(device, false)
	else:
		if device == active_device:
			active_device = -1
		controller_disconnected.emit(device)


func _register_device(device: int, at_boot: bool) -> void:
	active_device = device
	var guid: String = Input.get_joy_guid(device)
	var pad_name: String = Input.get_joy_name(device)
	controller_connected.emit(device, pad_name)
	if has_saved_layout(guid):
		_apply_face_map(load_layout(guid))
		layout_applied.emit(device)
	else:
		# Unknown pad: apply the default layout so it's immediately playable,
		# then offer the wizard. (Don't gate playability on completing setup.)
		_apply_face_map(DEFAULT_FACE_BUTTON.duplicate())
		layout_applied.emit(device)
		new_controller_detected.emit(device, guid, pad_name)


func is_connected_any() -> bool:
	return not Input.get_connected_joypads().is_empty()


func active_guid() -> String:
	if active_device < 0:
		return ""
	return Input.get_joy_guid(active_device)


func active_name() -> String:
	if active_device < 0:
		return ""
	return Input.get_joy_name(active_device)


# --- remap application ----------------------------------------------------

# Apply a logical→physical face map: rewrite each face-bound action's joypad
# button event so the physical index matches the player's assignment. Keyboard
# events on the same actions are left untouched (WASD/mouse fallback intact).
func _apply_face_map(face_map: Dictionary) -> void:
	_face_map = _normalize_face_map(face_map)
	for action in FACE_ACTION.keys():
		if not InputMap.has_action(action):
			continue
		var logical: int = int(FACE_ACTION[action])
		var physical: int = int(_face_map.get(logical, DEFAULT_FACE_BUTTON[logical]))
		_rebind_action_joy_button(action, physical)


# Replace the (single) joypad-button event on an action with one pointing at
# `button_index`, preserving every non-joypad-button event (keys, axes).
func _rebind_action_joy_button(action: String, button_index: int) -> void:
	var kept: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventJoypadButton):
			kept.append(ev)
	var joy: InputEventJoypadButton = InputEventJoypadButton.new()
	joy.button_index = button_index
	joy.pressed = true
	InputMap.action_erase_events(action)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	InputMap.action_add_event(action, joy)


# Guarantee every logical slot is present + integer-typed, falling back to the
# default index when a saved/partial map omits one.
func _normalize_face_map(face_map: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for logical in DEFAULT_FACE_BUTTON.keys():
		out[logical] = int(face_map.get(logical, DEFAULT_FACE_BUTTON[logical]))
	return out


# The currently applied physical button index for a logical position.
func face_button(logical: int) -> int:
	return int(_face_map.get(logical, DEFAULT_FACE_BUTTON.get(logical, JOY_BUTTON_A)))


# Public: apply + persist a freshly-captured layout for a GUID. Called by the
# config dialog when the wizard finishes. `face_map` is logical(int)→physical(int).
func set_layout(guid: String, face_map: Dictionary) -> void:
	var normalized: Dictionary = _normalize_face_map(face_map)
	_apply_face_map(normalized)
	save_layout(guid, normalized)
	if active_device >= 0:
		layout_applied.emit(active_device)


# Reset to the SDL/Xbox standard layout for a GUID (and re-apply live).
func reset_layout(guid: String) -> void:
	set_layout(guid, DEFAULT_FACE_BUTTON.duplicate())


# --- persistence (shared settings.cfg) ------------------------------------

# A GUID's saved-layout key. GUIDs can contain characters that are awkward as
# ConfigFile keys, so we store under a single dictionary keyed by GUID.
func has_saved_layout(guid: String) -> bool:
	if guid == "":
		return false
	return _all_layouts().has(guid)


func load_layout(guid: String) -> Dictionary:
	var raw: Variant = _all_layouts().get(guid, null)
	if raw is Dictionary:
		# ConfigFile round-trips dict keys as strings/floats; coerce to int→int.
		var out: Dictionary = {}
		for k in (raw as Dictionary).keys():
			out[int(k)] = int((raw as Dictionary)[k])
		return _normalize_face_map(out)
	return DEFAULT_FACE_BUTTON.duplicate()


func save_layout(guid: String, face_map: Dictionary) -> void:
	if guid == "":
		return
	var layouts: Dictionary = _all_layouts()
	# Store with string keys so ConfigFile serialization is stable across loads.
	var stored: Dictionary = {}
	for logical in face_map.keys():
		stored[str(int(logical))] = int(face_map[logical])
	layouts[guid] = stored
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # preserve other sections (audio/gameplay)
	cfg.set_value(SECTION, "layouts", layouts)
	cfg.save(SETTINGS_PATH)


func _all_layouts() -> Dictionary:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return {}
	var raw: Variant = cfg.get_value(SECTION, "layouts", {})
	return raw if raw is Dictionary else {}


# Human-readable label for a logical position (for the wizard prompts).
func face_label(logical: int) -> String:
	match logical:
		Face.BOTTOM: return "BOTTOM"
		Face.RIGHT: return "RIGHT"
		Face.LEFT: return "LEFT"
		Face.TOP: return "TOP"
		_: return "?"
