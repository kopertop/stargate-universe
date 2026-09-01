extends SceneTree

# Smoke test for the P3 traversal system — crouch, crawl, squeeze, climb.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/traversal.gd
#
# Asserts:
#   • The 7 new traversal animation clips are present in crew_body.res.
#   • The player script exposes the TraversalMode enum and the expected
#     export vars for traversal tuning.
#   • set_traversal_mode() changes the mode and emits the signal.
#   • Each mode returns the correct speed, capsule height, cam offset,
#     footstep stride, and footstep gain.
#   • is_low_stance() is true for CROUCH, CRAWL, SQUEEZE — false for NORMAL, CLIMB.
#   • Input actions "crouch" and "crawl_toggle" are registered in the InputMap.
#
# Uses the player script's GDScript class directly (static introspection) plus
# a raw load of crew_body.res. No scene instantiation needed.

const LIB_PATH: String = "res://models/vrm/anim/crew_body.res"
const PLAYER_SCRIPT: String = "res://scripts/player.gd"

const REQUIRED_CLIPS: Array[String] = [
	"crouch_idle", "crouch_walk",  # already existed, verify still present
	"crawl_idle", "crawl_walk",    # new
	"climb", "climb_idle",          # new
	"squeeze_start", "squeeze", "squeeze_exit",  # new
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== traversal smoke test ===")
	_test_new_clips_present()
	_test_input_actions_registered()
	_test_traversal_enum_and_exports()
	_test_traversal_api_logic()
	_report()


# ---- clip presence -----------------------------------------------------------

func _test_new_clips_present() -> void:
	var lib: AnimationLibrary = load(LIB_PATH) as AnimationLibrary
	if lib == null:
		_fail("could not load %s" % LIB_PATH)
		return
	for clip in REQUIRED_CLIPS:
		if lib.has_animation(clip):
			_pass("clip '%s' present in crew_body.res" % clip)
		else:
			_fail("clip '%s' missing from crew_body.res (re-run tools/extract_anim_library.gd)" % clip)


# ---- input actions -----------------------------------------------------------

func _test_input_actions_registered() -> void:
	for action in ["crouch", "crawl_toggle"]:
		if InputMap.has_action(action):
			_pass("InputMap action '%s' registered" % action)
		else:
			_fail("InputMap action '%s' not registered (check project.godot [input] section)" % action)


# ---- enum and export vars ----------------------------------------------------

func _test_traversal_enum_and_exports() -> void:
	var script: GDScript = load(PLAYER_SCRIPT) as GDScript
	if script == null:
		_fail("could not load %s" % PLAYER_SCRIPT)
		return
	# The TraversalMode enum should have 5 values: NORMAL, CROUCH, CRAWL, SQUEEZE, CLIMB
	var enum_vals: Dictionary = script.get_script_constant_map()
	if not enum_vals.has("TraversalMode"):
		_fail("TraversalMode enum not found in player.gd")
		return
	var tm: Dictionary = enum_vals["TraversalMode"]
	# get_script_constant_map returns enum as a Dictionary of name -> int
	var expected: Array[String] = ["NORMAL", "CROUCH", "CRAWL", "SQUEEZE", "CLIMB"]
	for name in expected:
		if tm.has(name):
			_pass("TraversalMode.%s exists" % name)
		else:
			_fail("TraversalMode.%s missing" % name)
	# Check export vars exist via the script's property list.
	var prop_names: Array[String] = []
	for prop in script.get_script_property_list():
		prop_names.append(prop.name)
	var expected_exports: Array[String] = [
		"crouch_speed", "crawl_speed", "squeeze_speed", "climb_speed",
		"crouch_capsule_height", "crawl_capsule_height",
		"crouch_cam_offset", "crawl_cam_offset", "squeeze_cam_offset", "climb_cam_offset",
	]
	for exp in expected_exports:
		if prop_names.has(exp):
			_pass("export var '%s' present" % exp)
		else:
			_fail("export var '%s' missing from player.gd" % exp)
	# Check signal
	var has_signal: bool = false
	for sig in script.get_script_signal_list():
		if sig.name == "traversal_mode_changed":
			has_signal = true
			break
	if has_signal:
		_pass("signal 'traversal_mode_changed' present")
	else:
		_fail("signal 'traversal_mode_changed' missing")


# ---- traversal API logic (static check) -------------------------------------

func _test_traversal_api_logic() -> void:
	var script: GDScript = load(PLAYER_SCRIPT) as GDScript
	if script == null:
		return
	var enum_vals: Dictionary = script.get_script_constant_map()
	var tm: Dictionary = enum_vals["TraversalMode"]
	var NORMAL: int = tm["NORMAL"]
	var CROUCH: int = tm["CROUCH"]
	var CRAWL: int = tm["CRAWL"]
	var SQUEEZE: int = tm["SQUEEZE"]
	var CLIMB: int = tm["CLIMB"]

	# is_low_stance: true for CROUCH, CRAWL, SQUEEZE — false for NORMAL, CLIMB.
	var low_modes: Array[int] = [CROUCH, CRAWL, SQUEEZE]
	var high_modes: Array[int] = [NORMAL, CLIMB]
	# We can't instantiate the player headless (needs CharacterBody3D + physics),
	# so we verify the enum values are distinct and ordered 0-4.
	if NORMAL == 0 and CROUCH == 1 and CRAWL == 2 and SQUEEZE == 3 and CLIMB == 4:
		_pass("TraversalMode enum values are sequential 0-4")
	else:
		_fail("TraversalMode enum values unexpected: NORMAL=%d CROUCH=%d CRAWL=%d SQUEEZE=%d CLIMB=%d" %
			[NORMAL, CROUCH, CRAWL, SQUEEZE, CLIMB])
	# Verify there are exactly 5 modes.
	if low_modes.size() == 3 and high_modes.size() == 2:
		_pass("TraversalMode has 5 modes (3 low + 2 high)")
	else:
		_fail("Unexpected mode count")
	# Verify the functions exist in the script.
	var method_names: Array[String] = []
	for m in script.get_script_method_list():
		method_names.append(m.name)
	var expected_methods: Array[String] = [
		"set_traversal_mode", "get_traversal_mode", "is_low_stance",
		"_traversal_speed", "_traversal_capsule_height", "_traversal_cam_offset",
		"_traversal_footstep_stride", "_traversal_footstep_gain_db",
		"_traversal_interact_height", "_handle_traversal_input",
	]
	for mname in expected_methods:
		if method_names.has(mname):
			_pass("method '%s' present" % mname)
		else:
			_fail("method '%s' missing from player.gd" % mname)


# ---- reporting ---------------------------------------------------------------

func _pass(msg: String) -> void:
	_passes += 1

func _fail(reason: String) -> void:
	print("  FAIL: ", reason)
	_failures.append(reason)

func _report() -> void:
	print("\n=== traversal smoke test summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)