extends SceneTree

# Smoke test for the Gamepad autoload — native controller support (issue #34).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/gamepad.gd
#
# Asserts:
#   • The autoload is attached and exposes the remap API.
#   • The DEFAULT (SDL/Xbox) layout binds the four face-bound actions to the
#     standard A/B/X/Y physical indices, AND leaves their keyboard fallback
#     events intact (WASD/mouse stays secondary, not clobbered).
#   • A SWAPPED layout (A/B and X/Y physically swapped, the Nintendo case the
#     issue calls out) rewrites those actions so "jump = bottom face" holds even
#     though the bottom face is physically JOY_BUTTON_B on that pad.
#   • A captured layout round-trips through user://settings.cfg (persist + load),
#     keyed by GUID, and re-applying it reproduces the same InputMap bindings.
#   • reset_layout restores the standard layout.
#   • Saving a gamepad layout does NOT disturb the audio/gameplay settings the
#     Settings autoload writes to the same file.
#
# Drives the live Gamepad autoload via root.get_node_or_null (the bare global
# identifier does NOT compile under -s).

var _failures: Array[String] = []
var _passes: int = 0

const TEST_GUID: String = "smoke-test-pad-guid-0001"

# A swapped pad: bottom face is physically B(1), right is A(0), left is Y(3),
# top is X(2) — the classic Xbox<->Nintendo face quad rotation.
var _swapped_map: Dictionary = {}


func _initialize() -> void:
	print("=== gamepad smoke test ===")

	var gp: Node = root.get_node_or_null("Gamepad")
	_expect(gp != null, "Gamepad autoload attached")
	if gp == null:
		_report()
		return

	_swapped_map = {
		gp.Face.BOTTOM: JOY_BUTTON_B,   # 1
		gp.Face.RIGHT: JOY_BUTTON_A,    # 0
		gp.Face.LEFT: JOY_BUTTON_Y,     # 3
		gp.Face.TOP: JOY_BUTTON_X,      # 2
	}

	# --- 1. default layout binds the standard quad --------------------------
	gp.call("reset_layout", TEST_GUID)
	_expect(_joy_button_of("jump") == JOY_BUTTON_A, "default: jump → bottom face (A=0)")
	_expect(_joy_button_of("kino_remote") == JOY_BUTTON_B, "default: kino_remote → right face (B=1)")
	_expect(_joy_button_of("interact") == JOY_BUTTON_X, "default: interact → left face (X=2)")
	_expect(_joy_button_of("kino_autopilot") == JOY_BUTTON_Y, "default: kino_autopilot → top face (Y=3)")

	# --- 2. keyboard fallback preserved (WASD/mouse stays secondary) --------
	_expect(_has_key_event("jump"), "default: jump keeps a keyboard event (Space)")
	_expect(_has_key_event("interact"), "default: interact keeps a keyboard event (E)")

	# --- 3. swapped layout rewires the quad ---------------------------------
	gp.call("set_layout", TEST_GUID, _swapped_map)
	_expect(_joy_button_of("jump") == JOY_BUTTON_B,
		"swapped: jump → bottom face is now physically B(1)")
	_expect(_joy_button_of("kino_remote") == JOY_BUTTON_A,
		"swapped: kino_remote → right face is now physically A(0)")
	_expect(_joy_button_of("interact") == JOY_BUTTON_Y,
		"swapped: interact → left face is now physically Y(3)")
	_expect(_joy_button_of("kino_autopilot") == JOY_BUTTON_X,
		"swapped: kino_autopilot → top face is now physically X(2)")
	# Fallback survives the remap.
	_expect(_has_key_event("jump"), "swapped: jump STILL keeps its keyboard event")

	# --- 4. persistence round-trip (keyed by GUID) --------------------------
	_expect(bool(gp.call("has_saved_layout", TEST_GUID)),
		"layout persisted for the GUID after set_layout")
	var loaded: Dictionary = gp.call("load_layout", TEST_GUID)
	_expect(int(loaded.get(gp.Face.BOTTOM, -1)) == JOY_BUTTON_B,
		"loaded layout: BOTTOM physical = B(1)")
	_expect(int(loaded.get(gp.Face.TOP, -1)) == JOY_BUTTON_X,
		"loaded layout: TOP physical = X(2)")

	# Stomp the live InputMap to default, then re-apply the SAVED layout and
	# confirm the swapped bindings come back — proves apply-from-disk works.
	gp.call("reset_layout", "some-other-pad")
	_expect(_joy_button_of("jump") == JOY_BUTTON_A, "reset to a different pad → default A")
	gp.call("set_layout", TEST_GUID, gp.call("load_layout", TEST_GUID))
	_expect(_joy_button_of("jump") == JOY_BUTTON_B,
		"re-applying the loaded layout restores swapped jump=B")

	# --- 5. settings.cfg coexistence ---------------------------------------
	var settings: Node = root.get_node_or_null("Settings")
	if settings != null:
		# Write an audio setting, then save a gamepad layout, then re-read the
		# audio setting straight off disk — it must survive.
		settings.call("set_music_volume", 0.42)
		gp.call("set_layout", TEST_GUID, _swapped_map)
		var cfg: ConfigFile = ConfigFile.new()
		cfg.load("user://settings.cfg")
		_expect(abs(float(cfg.get_value("audio", "music_volume", -1.0)) - 0.42) < 0.001,
			"saving a gamepad layout preserves the audio music_volume setting")
		_expect((cfg.get_value("gamepad", "layouts", {}) as Dictionary).has(TEST_GUID),
			"the gamepad section coexists with the audio section")

	# --- 6. cleanup so we don't leave a sandbox layout lingering -----------
	_cleanup_test_layout()

	_report()


# Read the (single) joypad-button index currently bound to an action, or -1.
func _joy_button_of(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			return (ev as InputEventJoypadButton).button_index
	return -1


func _has_key_event(action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return true
	return false


func _cleanup_test_layout() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	var layouts: Variant = cfg.get_value("gamepad", "layouts", {})
	if layouts is Dictionary and (layouts as Dictionary).has(TEST_GUID):
		(layouts as Dictionary).erase(TEST_GUID)
		cfg.set_value("gamepad", "layouts", layouts)
		cfg.save("user://settings.cfg")


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
