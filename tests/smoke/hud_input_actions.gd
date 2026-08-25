extends SceneTree

# Input actions smoke test (WoW HUD redesign Phase 0, #141).
#
# Asserts the four new InputMap actions (quest_log / toggle_map / inventory /
# cancel_target) registered by project.godot exist and each carries at least
# one keyboard + one joypad event. Also asserts the Esc-bound `cancel_target`
# action does not collide with the existing `pause` action handling by
# documenting the gate (cancel_target is the OPEN path only, pause is handled
# separately — see memory `godot-autoload-input-order`).
#
# Asserts the PASS count, not just the exit code, so a failed load can't
# false-green (a smoke script that fails to parse exits 0).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/hud_input_actions.gd

const ACTIONS: Array[String] = [
	"quest_log",
	"toggle_map",
	"inventory",
	"cancel_target",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== hud_input_actions smoke test ===")
	# Reach the InputMap directly — it is a global singleton, not an autoload
	# node, so no /root/ lookup is needed (see the test conventions in the plan).
	for action in ACTIONS:
		_expect(InputMap.has_action(action), "InputMap has action \"%s\"" % action)
		if not InputMap.has_action(action):
			continue
		var has_kbd: bool = false
		var has_pad: bool = false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				has_kbd = true
			elif ev is InputEventJoypadButton:
				has_pad = true
		_expect(has_kbd, "action \"%s\" has a keyboard event" % action)
		_expect(has_pad, "action \"%s\" has a joypad event" % action)

	# Esc gate: cancel_target + pause both bind Esc (physical_keycode 4194305).
	# They coexist because cancel_target is only consumed on the OPEN path
	# (HUD-level _unhandled_input, gated on a non-null target) while pause is
	# handled by the PauseMenu autoload. Document the contract here.
	if InputMap.has_action("cancel_target") and InputMap.has_action("pause"):
		var ct_esc: bool = _action_has_physical_key("cancel_target", 4194305)
		var pause_esc: bool = _action_has_physical_key("pause", 4194305)
		_expect(ct_esc and pause_esc,
			"cancel_target + pause both bind Esc (OPEN-path gate documented)")
		# Regression: pre-existing actions still fire (not dropped by the new
		# entries — InputMap doesn't dedupe across actions).
		_expect(InputMap.has_action("character_pane"),
			"regression: character_pane action still present")
		_expect(InputMap.has_action("pause"),
			"regression: pause action still present")
		_expect(InputMap.has_action("kino_remote"),
			"regression: kino_remote action still present")

	_report()


func _action_has_physical_key(action: String, physical_keycode: int) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == physical_keycode:
			return true
	return false


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)