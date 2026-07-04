extends SceneTree

# Presence guard for the shared crew animation library (models/vrm/anim/crew_body.res),
# built by tools/extract_anim_library.gd. Asserts the E1 cold-open arrival clips (Mixamo
# roll/get-up/crash) are present so _co_arrival/_co_roll_settle/_wound_crew can play them.
# Headless, no scene. Run:  godot --headless -s res://tests/smoke/anim_library.gd

const LIB: String = "res://models/vrm/anim/crew_body.res"
const REQUIRED: Array[String] = [
	"dive_roll", "falling_roll", "sprint_roll", "roll_to_run", "run_roll", "get_up", "crash",
	# load-bearing existing clips the cold open also uses:
	"idle", "run", "crouch_idle",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	var lib: AnimationLibrary = load(LIB) as AnimationLibrary
	if lib == null:
		_fail("could not load %s" % LIB)
		_report()
		return
	for clip: String in REQUIRED:
		if lib.has_animation(clip):
			_passes += 1
		else:
			_fail("crew_body.res missing clip '%s' (re-run tools/extract_anim_library.gd)" % clip)
	_report()


func _fail(reason: String) -> void:
	print("  FAIL: ", reason)
	_failures.append(reason)


func _report() -> void:
	print("\n=== anim_library summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f: String in _failures:
		print("  - ", f)
	quit(1)
