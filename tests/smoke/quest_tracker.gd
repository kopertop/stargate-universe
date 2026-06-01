extends SceneTree

# Smoke test for the WoW-style quest objective tracker (issue #66).
#
# Instances the real HUD scene with autoloads active and asserts the upper-right
# tracker:
#   • the QuestTracker node exists with a Title + Objective label
#   • on _ready it shows the tracked quest's title (QuestLog.title()) and its
#     active objective (QuestLog.objective())
#   • advancing the tracked quest a step (QuestLog.complete_step) refreshes the
#     objective line WITHOUT a reload — it reflects the new QuestLog.objective()
#   • the recent-log feed sits BELOW the tracker (no overlap)
#
# The tracker is driven by GameState.quest_step_changed, which mirrors
# QuestLog.quest_step_changed, so completing a step exercises the real signal
# path the running game uses.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/quest_tracker.gd

const HUD_SCENE: String = "res://objects/hud.tscn"

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null
var _game: Node = null
var _ql: Node = null


func _initialize() -> void:
	print("=== quest_tracker smoke test ===")
	# Autoloads aren't reachable on /root in _initialize (no frame has ticked);
	# defer everything past frame 0.
	call_deferred("_run_checks")


func _run_checks() -> void:
	_game = root.get_node_or_null("/root/GameState")
	_ql = root.get_node_or_null("/root/QuestLog")
	_expect(_game != null, "GameState autoload present")
	_expect(_ql != null, "QuestLog autoload present")
	if _game == null or _ql == null:
		_report()
		return

	var scene: PackedScene = load(HUD_SCENE) as PackedScene
	_expect(scene != null, "objects/hud.tscn loads")
	if scene == null:
		_report()
		return
	_hud = scene.instantiate()
	root.add_child(_hud)
	await process_frame

	# --- structure --------------------------------------------------------
	var tracker: Node = _hud.get_node_or_null("QuestTracker")
	_expect(tracker != null, "HUD builds the upper-right QuestTracker")
	if tracker == null:
		_finish()
		return
	var title_label: Label = tracker.get_node_or_null("Title") as Label
	var objective_label: Label = tracker.get_node_or_null("Objective") as Label
	_expect(title_label != null, "QuestTracker has a Title label")
	_expect(objective_label != null, "QuestTracker has an Objective label")
	if title_label == null or objective_label == null:
		_finish()
		return

	# --- initial render from QuestLog -------------------------------------
	var expected_title: String = String(_ql.call("title"))
	var expected_objective: String = String(_ql.call("objective"))
	_expect(expected_title != "", "QuestLog exposes a tracked-quest title")
	_expect(title_label.text == expected_title,
		"tracker title matches QuestLog.title() ('%s')" % expected_title)
	_expect(objective_label.text.find(expected_objective) != -1 and expected_objective != "",
		"tracker objective contains QuestLog.objective()")
	_expect((tracker as Control).visible,
		"tracker is visible while a quest is tracked")

	# --- live update on step advance (no reload) --------------------------
	var quest_id: String = String(_ql.call("tracked_quest_id"))
	var before_objective: String = objective_label.text
	# Walk forward until the objective text actually changes (some steps may
	# share copy); cap the walk so a misbehaving quest can't hang the test.
	var changed: bool = false
	for _i in range(12):
		var active: String = String(_ql.call("active_step_id", quest_id))
		if active == "" or _ql.call("is_complete", quest_id) == true:
			break
		_ql.call("complete_step", quest_id, active)
		await process_frame
		if objective_label.text != before_objective:
			changed = true
			break
	_expect(changed, "advancing a quest step refreshes the tracker objective (no reload)")
	var live_objective: String = String(_ql.call("objective", quest_id))
	_expect(live_objective == "" or objective_label.text.find(live_objective) != -1,
		"refreshed tracker objective reflects the new QuestLog.objective()")

	# --- no overlap with the recent-log feed ------------------------------
	await process_frame
	var log_box: Control = _hud.get_node_or_null("Log") as Control
	_expect(log_box != null, "recent-log feed exists")
	if log_box != null:
		var tracker_bottom: float = (tracker as Control).offset_top + (tracker as Control).size.y
		_expect(log_box.offset_top >= tracker_bottom,
			"log feed (top %.0f) sits below the tracker (bottom %.0f)"
				% [log_box.offset_top, tracker_bottom])

	_finish()


func _finish() -> void:
	if _hud != null and is_instance_valid(_hud):
		root.remove_child(_hud)
		_hud.free()
	_report()


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
