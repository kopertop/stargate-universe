extends SceneTree

# Drift guard for the E1 cold open. The cold open is now driven by ONE master
# recording (sounds/dialog/prologue/cold_open_master.mp3) played in
# scripts/gate_room.gd::_play_prologue_cinematic; the visual beats + captions are
# timed against its playhead. This guards the load-bearing invariants of that design:
#
#   1. The master track is referenced in code AND the file exists on disk (a renamed
#      or missing clip would silently drop the whole cold-open soundtrack).
#   2. The Find-Rush hand-off captions stay wired (the climax that launches the quest).
#   3. The hand-off END-STATE: the cinematic marks Scott met + advances the e1_air
#      quest itself, and does NOT re-enable Scott's walk-up auto_greet — so the first
#      thing after the cold open is that the player ALREADY holds the Find-Rush quest,
#      not a Scott briefing.
#
# Headless, no assets, no autoloads.
#
# Run with:
#   godot --headless -s res://tests/smoke/cold_open_lines.gd

const GATE_ROOM: String = "res://scripts/gate_room.gd"
const MASTER_AUDIO: String = "res://sounds/dialog/prologue/cold_open_bed.mp3"

# Verbatim transcript beats that MUST stay wired (the command hand-off + the Rush
# hand-off button). Match docs/OPENING_SCENE_SCRIPT.md §1 exactly.
const REQUIRED_CAPTIONS: Array[String] = [
	"Get out of the way!",
	"Where's Colonel Young?",
	"You're in charge, okay? You're...",
	"TJ!",
	"I'm coming!",
	"Rush! Eli, help me find him.",
	"What in the hell was that?!",
	"Eli! Now!",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	# Arrange.
	var code: String = _read(GATE_ROOM)
	if code == "":
		_report()
		return

	# Act / Assert.
	test_cold_open_master_track_referenced_and_present(code)
	test_cold_open_handoff_captions_present(code)
	test_cold_open_advances_quest_without_scott_walkup(code)
	_report()


# The master soundtrack must be referenced in code and actually exist on disk.
func test_cold_open_master_track_referenced_and_present(code: String) -> void:
	if code.find(MASTER_AUDIO) != -1:
		_passes += 1
	else:
		_fail("master cold-open track '%s' is not referenced in gate_room.gd" % MASTER_AUDIO)
	if FileAccess.file_exists(MASTER_AUDIO):
		_passes += 1
	else:
		_fail("master cold-open track file missing on disk: %s" % MASTER_AUDIO)


# The Find-Rush climax captions must all still be present.
func test_cold_open_handoff_captions_present(code: String) -> void:
	for cap: String in REQUIRED_CAPTIONS:
		if code.find(cap) != -1:
			_passes += 1
		else:
			_fail("required hand-off caption '%s' is no longer present in gate_room.gd" % cap)


# The cinematic must end by handing the player the quest itself — NOT by walking
# Scott over to brief them.
func test_cold_open_advances_quest_without_scott_walkup(code: String) -> void:
	if code.find("GameState.met_scott = true") != -1:
		_passes += 1
	else:
		_fail("cold open no longer marks Scott met (GameState.met_scott = true) at hand-off")
	if code.find("advance_air_quest()") != -1:
		_passes += 1
	else:
		_fail("cold open no longer advances the e1_air quest (advance_air_quest()) at hand-off")
	# The whole point of the redesign: Scott does not auto-greet after the cold open.
	if code.find("_set_scott_autogreet(true)") == -1:
		_passes += 1
	else:
		_fail("cold open re-enables Scott's walk-up (_set_scott_autogreet(true)) — the player " +
			"should already hold the Find-Rush quest, not be briefed by Scott")


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot open %s" % path)
		return ""
	return f.get_as_text()


func _fail(reason: String) -> void:
	print("  FAIL: ", reason)
	_failures.append(reason)


func _report() -> void:
	print("\n=== cold_open_lines summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f: String in _failures:
		print("  - ", f)
	quit(1)
