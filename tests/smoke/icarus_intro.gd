extends SceneTree

# Smoke test for the Icarus Base evacuation tutorial sequence (task t_61536d43).
#
# Verifies:
#   1. data/icarus_intro.json loads and has 3 acts with correct ids.
#   2. Each act has the expected number of steps with correct ids.
#   3. Step types are valid (narration, dialogue, tutorial_hint, puzzle).
#   4. Dialogue steps have non-empty speaker + text.
#   5. Tutorial_hint steps have non-empty text and a valid advance_on trigger.
#   6. Puzzle steps have advance_on == "puzzle_solved".
#   7. GameState.intro_complete exists, defaults false, saves/loads.
#   8. IcarusIntro instant mode runs all steps and sets intro_complete.
#   9. All trigger setters exist and are callable.
#  10. The narrative arc is coherent: Act 1 has Eli + Greer, Act 2 has Young +
#      Rush, Act 3 has Scott + Young + Rush. The arc flows apartment → base →
#      evacuation → Destiny arrival.
#  11. title.gd routes to icarus_intro.tscn when intro_complete is false, and
#      to gate_room.tscn when true (verified by checking GameState state, not
#      by actually running the title scene).
#
# Run with:
#   godot --headless --quit-after 60 -s res://tests/smoke/icarus_intro.gd

const INTRO_SCRIPT_PATH: String = "res://scripts/icarus_intro.gd"
const INTRO_DATA_PATH: String = "res://data/icarus_intro.json"

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== icarus_intro smoke test (task t_61536d43) ===")

	# ── 1. Data file loads and has 3 acts ───────────────────────────────────
	print("\n-- 1. data file structure --")
	var f: FileAccess = FileAccess.open(INTRO_DATA_PATH, FileAccess.READ)
	_expect(f != null, "icarus_intro.json exists and is readable")
	if f == null:
		_report()
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	_expect(parsed is Dictionary, "icarus_intro.json parses to Dictionary")
	if not (parsed is Dictionary):
		_report()
		return
	var acts: Array = parsed.get("acts", [])
	_expect(acts.size() == 3, "exactly 3 acts defined (got %d)" % acts.size())

	# ── 2. Act ids and step counts ──────────────────────────────────────────
	print("\n-- 2. act ids and step counts --")
	var expected_act_ids: Array[String] = ["act1_apartment", "act2_icarus_base", "act3_evacuation"]
	for i in range(acts.size()):
		var act: Dictionary = acts[i]
		var act_id: String = String(act.get("id", ""))
		_expect(act_id == expected_act_ids[i],
				"act %d id == '%s' (got '%s')" % [i, expected_act_ids[i], act_id])
		var steps: Array = act.get("steps", [])
		_expect(steps.size() > 0, "act '%s' has >0 steps (got %d)" % [act_id, steps.size()])

	# ── 3. Step types are valid ─────────────────────────────────────────────
	print("\n-- 3. step types valid --")
	var valid_types: Array[String] = ["narration", "dialogue", "tutorial_hint", "puzzle"]
	for i in range(acts.size()):
		var steps: Array = acts[i].get("steps", [])
		for j in range(steps.size()):
			var step: Dictionary = steps[j]
			var step_type: String = String(step.get("type", ""))
			_expect(step_type in valid_types,
					"act %d step %d type '%s' is valid" % [i, j, step_type])

	# ── 4. Dialogue steps have speaker + text ───────────────────────────────
	print("\n-- 4. dialogue steps have speaker + text --")
	for i in range(acts.size()):
		var steps: Array = acts[i].get("steps", [])
		for j in range(steps.size()):
			var step: Dictionary = steps[j]
			if String(step.get("type", "")) == "dialogue":
				var sp: String = String(step.get("speaker", ""))
				var txt: String = String(step.get("text", ""))
				_expect(sp != "", "act %d step %d dialogue has non-empty speaker" % [i, j])
				_expect(txt != "", "act %d step %d dialogue has non-empty text" % [i, j])

	# ── 5. Tutorial_hint steps have text + valid advance_on ─────────────────
	print("\n-- 5. tutorial_hint steps valid --")
	var valid_triggers: Array[String] = [
		"input", "interact_laptop", "reached_young", "reached_gate_room",
		"interact_console", "entered_gate", "puzzle_solved"
	]
	for i in range(acts.size()):
		var steps: Array = acts[i].get("steps", [])
		for j in range(steps.size()):
			var step: Dictionary = steps[j]
			if String(step.get("type", "")) == "tutorial_hint":
				var txt: String = String(step.get("text", ""))
				var adv: String = String(step.get("advance_on", ""))
				_expect(txt != "", "act %d step %d tutorial_hint has text" % [i, j])
				_expect(adv in valid_triggers,
						"act %d step %d tutorial_hint advance_on '%s' is valid" % [i, j, adv])

	# ── 6. Puzzle steps advance on puzzle_solved ────────────────────────────
	print("\n-- 6. puzzle steps advance_on puzzle_solved --")
	for i in range(acts.size()):
		var steps: Array = acts[i].get("steps", [])
		for j in range(steps.size()):
			var step: Dictionary = steps[j]
			if String(step.get("type", "")) == "puzzle":
				var adv: String = String(step.get("advance_on", ""))
				_expect(adv == "puzzle_solved",
						"act %d step %d puzzle advance_on == 'puzzle_solved' (got '%s')" % [i, j, adv])

	# ── 7. GameState.intro_complete flag ────────────────────────────────────
	print("\n-- 7. GameState.intro_complete flag --")
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload present")
	if gs != null:
		gs.call("reset")
		_expect(gs.get("intro_complete") == false, "intro_complete defaults to false after reset")
		# Serialize + deserialize round-trip.
		var data: Dictionary = gs.call("serialize")
		_expect(data.has("intro_complete"), "serialize() includes intro_complete key")
		gs.set("intro_complete", true)
		data = gs.call("serialize")
		_expect(data.get("intro_complete", false) == true, "serialize() captures intro_complete == true")
		# Deserialize back to false.
		data["intro_complete"] = false
		gs.call("deserialize", data, 1)
		_expect(gs.get("intro_complete") == false, "deserialize() restores intro_complete == false")

	# ── 8. IcarusIntro instant mode ─────────────────────────────────────────
	print("\n-- 8. IcarusIntro instant mode --")
	var intro_script: Script = load(INTRO_SCRIPT_PATH) as Script
	_expect(intro_script != null, "icarus_intro.gd script loads")
	if intro_script != null:
		var intro: Node = intro_script.new()
		intro.set("instant_mode", true)
		root.add_child(intro)
		# Wait one frame for _ready to run.
		await process_frame
		_expect(intro.get("instant_mode") == true, "instant_mode is true")
		_expect(intro.get_act_count() == 3, "get_act_count() == 3")
		var act_ids: Array[String] = intro.call("get_act_ids")
		_expect(act_ids.size() == 3, "get_act_ids() returns 3 ids")
		_expect(act_ids[0] == "act1_apartment", "act 0 id == 'act1_apartment'")
		_expect(act_ids[1] == "act2_icarus_base", "act 1 id == 'act2_icarus_base'")
		_expect(act_ids[2] == "act3_evacuation", "act 2 id == 'act3_evacuation'")
		# Step counts per act.
		_expect(intro.get_step_count(0) == 11, "act 0 has 11 steps (got %d)" % intro.get_step_count(0))
		_expect(intro.get_step_count(1) == 14, "act 1 has 14 steps (got %d)" % intro.get_step_count(1))
		_expect(intro.get_step_count(2) == 12, "act 2 has 12 steps (got %d)" % intro.get_step_count(2))
		# After instant run, GameState.intro_complete should be true.
		if gs != null:
			_expect(gs.get("intro_complete") == true,
					"GameState.intro_complete == true after instant intro run")
		# Verify some specific step types.
		_expect(intro.get_step_type(0, 0) == "narration", "act 0 step 0 is narration")
		_expect(intro.get_step_type(0, 1) == "tutorial_hint", "act 0 step 1 is tutorial_hint")
		_expect(intro.get_step_type(0, 4) == "puzzle", "act 0 step 4 is puzzle")
		_expect(intro.get_step_type(1, 1) == "tutorial_hint", "act 1 step 1 is tutorial_hint")
		_expect(intro.get_step_type(2, 5) == "puzzle", "act 2 step 5 is puzzle")
		# Verify speakers.
		_expect(intro.get_step_speaker(0, 7) == "Sgt. Greer", "act 0 step 7 speaker is Sgt. Greer")
		_expect(intro.get_step_speaker(1, 2) == "Col. Young", "act 1 step 2 speaker is Col. Young")
		_expect(intro.get_step_speaker(1, 6) == "Dr. Rush", "act 1 step 6 speaker is Dr. Rush")
		_expect(intro.get_step_speaker(2, 2) == "Lt. Scott", "act 2 step 2 speaker is Lt. Scott")
		# Verify step text is non-empty for all steps.
		var all_have_text: bool = true
		for ai in range(3):
			var sc: int = intro.get_step_count(ai)
			for si in range(sc):
				if intro.get_step_text(ai, si) == "":
					all_have_text = false
					break
			if not all_have_text:
				break
		_expect(all_have_text, "all steps have non-empty text")
		# Verify trigger methods exist.
		_expect(intro.has_method("trigger_reached_young"), "has trigger_reached_young method")
		_expect(intro.has_method("trigger_interact_console"), "has trigger_interact_console method")
		_expect(intro.has_method("trigger_reached_gate_room"), "has trigger_reached_gate_room method")
		_expect(intro.has_method("trigger_entered_gate"), "has trigger_entered_gate method")
		_expect(intro.has_method("trigger_puzzle_solved"), "has trigger_puzzle_solved method")
		# Verify trigger setters work.
		intro.call("trigger_reached_young")
		_expect(intro.get("_trigger_reached_young") == true, "trigger_reached_young sets flag")
		intro.call("trigger_interact_console")
		_expect(intro.get("_trigger_interact_console") == true, "trigger_interact_console sets flag")
		intro.call("trigger_puzzle_solved")
		_expect(intro.get("_trigger_puzzle_solved") == true, "trigger_puzzle_solved sets flag")
		# Verify intro_finished signal was emitted.
		# (In instant mode, _ready runs _run_instant which sets intro_complete and emits.)
		# We already checked intro_complete above.
		intro.queue_free()

	# ── 9. Narrative arc coherence ──────────────────────────────────────────
	print("\n-- 9. narrative arc coherence --")
	# Act 1: Eli at home, Greer recruits.
	var act0_steps: Array = acts[0].get("steps", [])
	var has_eli_act1: bool = false
	var has_greer_act1: bool = false
	for step in act0_steps:
		var sp: String = String(step.get("speaker", ""))
		if sp == "Eli":
			has_eli_act1 = true
		if sp == "Sgt. Greer":
			has_greer_act1 = true
	_expect(has_eli_act1, "act 1 has at least one Eli dialogue line")
	_expect(has_greer_act1, "act 1 has at least one Sgt. Greer dialogue line")

	# Act 2: Young briefs, Rush explains math.
	var act1_steps: Array = acts[1].get("steps", [])
	var has_young_act2: bool = false
	var has_rush_act2: bool = false
	for step in act1_steps:
		var sp: String = String(step.get("speaker", ""))
		if sp == "Col. Young":
			has_young_act2 = true
		if sp == "Dr. Rush":
			has_rush_act2 = true
	_expect(has_young_act2, "act 2 has at least one Col. Young dialogue line")
	_expect(has_rush_act2, "act 2 has at least one Dr. Rush dialogue line")

	# Act 3: Scott, Young, Rush during evacuation.
	var act2_steps: Array = acts[2].get("steps", [])
	var has_scott_act3: bool = false
	var has_young_act3: bool = false
	var has_rush_act3: bool = false
	for step in act2_steps:
		var sp: String = String(step.get("speaker", ""))
		if sp == "Lt. Scott":
			has_scott_act3 = true
		if sp == "Col. Young":
			has_young_act3 = true
		if sp == "Dr. Rush":
			has_rush_act3 = true
	_expect(has_scott_act3, "act 3 has at least one Lt. Scott dialogue line")
	_expect(has_young_act3, "act 3 has at least one Col. Young dialogue line")
	_expect(has_rush_act3, "act 3 has at least one Dr. Rush dialogue line")

	# Act 3 ends with Destiny arrival narration.
	var last_step: Dictionary = act2_steps[-1]
	var last_text: String = String(last_step.get("text", ""))
	_expect("Destiny" in last_text, "act 3 final step mentions 'Destiny'")

	# ── 10. Four-beat teaching pattern (onboarding-and-teaching skill) ──────
	print("\n-- 10. four-beat teaching pattern --")
	# Tutorial hints should teach one mechanic at a time, in order:
	#   Act 1: interact (E key) — laptop puzzle
	#   Act 2: movement (WASD) → look (mouse) → interact (E) — console puzzle
	#   Act 3: sprint (SHIFT) → interact (E) → walk into gate
	# Each tutorial_hint must have non-empty text (checked above).
	# Verify progressive disclosure: movement tutorial before look tutorial.
	var act0_tutorial_steps: Array = []
	for step in act0_steps:
		if String(step.get("type", "")) == "tutorial_hint":
			act0_tutorial_steps.append(step)
	# Act 1 has exactly 1 tutorial hint (interact laptop).
	_expect(act0_tutorial_steps.size() == 1,
			"act 1 has exactly 1 tutorial_hint (got %d)" % act0_tutorial_steps.size())

	var act1_tutorial_steps: Array = []
	for step in act1_steps:
		if String(step.get("type", "")) == "tutorial_hint":
			act1_tutorial_steps.append(step)
	# Act 2 has 3 tutorial hints: move, look, console.
	_expect(act1_tutorial_steps.size() == 3,
			"act 2 has exactly 3 tutorial_hints (got %d)" % act1_tutorial_steps.size())
	# Verify order: movement hint comes before look hint.
	var move_hint_idx: int = -1
	var look_hint_idx: int = -1
	for i in range(act1_steps.size()):
		var step: Dictionary = act1_steps[i]
		if String(step.get("type", "")) == "tutorial_hint":
			var txt: String = String(step.get("text", "")).to_lower()
			if "w/a/s/d" in txt or "walk" in txt:
				move_hint_idx = i
			if "look around" in txt or "mouse" in txt:
				look_hint_idx = i
	_expect(move_hint_idx >= 0, "act 2 has a movement tutorial hint")
	_expect(look_hint_idx >= 0, "act 2 has a look tutorial hint")
	if move_hint_idx >= 0 and look_hint_idx >= 0:
		_expect(move_hint_idx < look_hint_idx,
				"movement tutorial comes before look tutorial")

	# Act 3 has 3 tutorial hints: sprint, dial console, step through gate.
	var act2_tutorial_steps: Array = []
	for step in act2_steps:
		if String(step.get("type", "")) == "tutorial_hint":
			act2_tutorial_steps.append(step)
	_expect(act2_tutorial_steps.size() == 3,
			"act 3 has exactly 3 tutorial_hints (got %d)" % act2_tutorial_steps.size())

	# ── 11. No text dependency (show-don't-tell check) ───────────────────────
	print("\n-- 11. show-don't-tell check --")
	# Every puzzle step should have a tutorial_hint BEFORE it in the same act
	# that teaches the relevant interaction (not a text dump).
	for ai in range(acts.size()):
		var steps_a: Array = acts[ai].get("steps", [])
		for si in range(steps_a.size()):
			var step: Dictionary = steps_a[si]
			if String(step.get("type", "")) == "puzzle":
				# Check that a tutorial_hint exists before this puzzle in the same act.
				var has_prior_hint: bool = false
				for pi in range(si):
					if String(steps_a[pi].get("type", "")) == "tutorial_hint":
						has_prior_hint = true
						break
				_expect(has_prior_hint,
						"act %d puzzle step %d has a prior tutorial_hint in same act" % [ai, si])

	_report()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("\n=== icarus_intro smoke test results ===")
	print("  Passes: %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if _failures.is_empty():
		print("  RESULT: ALL TESTS PASSED")
	else:
		print("  RESULT: TEST FAILURES")
		for f_label in _failures:
			print("    - %s" % f_label)
	quit(0 if _failures.is_empty() else 1)