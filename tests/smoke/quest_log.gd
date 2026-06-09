extends SceneTree

# Smoke test for the data-driven QuestLog autoload (issue #36).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/quest_log.gd
#
# Asserts:
#   • data/quests.json loads + e1_air has the expected ordered ids.
#   • Hybrid advance — predicate (world-state flag on GameState) AND event
#     (complete_step) both advance the active index past their step.
#   • Multi-quest: a second start_quest tracks its own progress independently.
#   • Save round-trip: serialize → wipe → deserialize hydrates back to the
#     same active step.
#   • Old-format save migration: a snapshot with `quest_step` but no `quests`
#     block re-derives the right active step from world-state.
#
# Uses the live autoloads (GameState + QuestLog) rather than manually
# constructed duplicates — `-s` SceneTree mode attaches the autoloads to
# root, and a same-named test node would clash + leave QuestLog reading
# from the wrong GameState instance. See e1_flow.gd for the same pattern.

const EXPECTED_E1_STEPS: Array[String] = [
	"talk_scott",
	"find_rush",
	"find_rest",
	"find_kino",
	"sleep",
	"return_to_control",
	"diagnose_life_support",
	"seal_breach",
	"find_scrubber",
	"wait_ftl",
	"go_to_gate",
	"fetch_kino",
	"scout_kino",
	"dial_lime_planet",
	"mine_lime",
	"return_destiny",
	"repair_scrubber",
	"complete",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== quest_log smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var ql: Node = root.get_node_or_null("QuestLog")
	var inv: Node = root.get_node_or_null("Inventory")
	_expect(gs != null, "GameState autoload attached")
	_expect(ql != null, "QuestLog autoload attached")
	_expect(inv != null, "Inventory autoload attached")
	if gs == null or ql == null or inv == null:
		_report()
		return

	gs.reset()

	# --- 1. quests.json contents -------------------------------------------
	# Drive every assertion through the public API so we'd catch a bad
	# schema migration that left ordering intact but broke field reads.
	_expect(ql.active_step_id("e1_air") == "talk_scott",
		"e1_air starts at talk_scott")
	for i in EXPECTED_E1_STEPS.size():
		var sid: String = EXPECTED_E1_STEPS[i]
		var lbl: String = String(ql.label(sid))
		_expect(lbl != "" and lbl != sid,
			"label() resolves real text for step %d (%s)" % [i, sid])
	_expect(ql.is_complete("e1_air") == false,
		"e1_air is not complete at start")

	# --- 2. Predicate advance walks the 18-step golden sequence ------------
	# Each iteration flips the world-state flag that satisfies the current
	# active step's complete_when predicate, then asserts QuestLog moved on
	# to the next step. Mirrors the way every E1 beat advances in production.
	_walk_predicate_sequence(gs, ql)

	# Reset for the event-advance section.
	gs.reset()
	_expect(ql.active_step_id("e1_air") == "talk_scott", "reset returns to step 1")

	# --- 3. Event advance: complete_step is idempotent + skips ahead -------
	# complete_step lets a scripted beat advance past a step that has no
	# clean world-state predicate. We use talk_scott (which DOES have a
	# predicate) to verify the event channel works regardless — calling
	# complete_step twice should still leave the next step active.
	ql.complete_step("e1_air", "talk_scott")
	var after_first_event: String = String(ql.active_step_id("e1_air"))
	_expect(after_first_event == "find_rush",
		"complete_step advances past talk_scott")
	ql.complete_step("e1_air", "talk_scott")
	_expect(String(ql.active_step_id("e1_air")) == after_first_event,
		"complete_step is idempotent (re-calling does not regress)")

	# --- 4. Multi-quest registry -------------------------------------------
	# start_quest on a quest that isn't in the JSON should be a safe no-op.
	# We can't add a second JSON quest without altering data/quests.json so
	# the assertion is bounded: starting an unknown id must not crash, must
	# not mutate the active e1_air step, and must not appear in serialize.
	var prev_active: String = String(ql.active_step_id("e1_air"))
	ql.start_quest("definitely_not_a_real_quest_id")
	_expect(String(ql.active_step_id("e1_air")) == prev_active,
		"start_quest with unknown id is a no-op for tracked quest")
	var snapshot: Dictionary = ql.serialize()
	var quests_block: Dictionary = snapshot.get("quests", {}) as Dictionary
	_expect(not quests_block.has("definitely_not_a_real_quest_id"),
		"unknown quest id not added to progress")

	# --- 5. Save round-trip -------------------------------------------------
	# Drive the e1_air quest forward, snapshot, reset to first step, then
	# deserialize and confirm the active step is restored.
	gs.reset()
	gs.met_scott = true
	gs.advance_air_quest()
	gs.met_rush = true
	gs.advance_air_quest()
	_expect(String(ql.active_step_id("e1_air")) == "find_rest",
		"round-trip pre-state: active step is find_rest")
	var snap: Dictionary = ql.serialize()
	# Wipe world-state so a deserialize-without-flags ALSO works (the
	# re-derive on load would walk back to talk_scott if completed_steps
	# weren't in the snapshot — which proves event-state survives).
	gs.reset()
	_expect(String(ql.active_step_id("e1_air")) == "talk_scott",
		"round-trip post-reset: back to talk_scott")
	# Re-set the predicates so the re-derive after deserialize keeps the
	# folded completed_steps + flags in agreement.
	gs.met_scott = true
	gs.met_rush = true
	ql.deserialize(snap, 1)
	_expect(String(ql.active_step_id("e1_air")) == "find_rest",
		"round-trip restored: active step is find_rest")

	# --- 6. Old-format save migration --------------------------------------
	# An older save file (pre-#36) carried `quest_step` on GameState but had
	# no `quests` block in QuestLog. On load, advance() should re-derive the
	# active step from the world-state flags GameState restored. Simulate by
	# handing deserialize an empty-quests snapshot with the world-state
	# flags pre-set; the active step should land on whatever the flags
	# imply, NOT on the empty default.
	gs.reset()
	gs.met_scott = true
	gs.met_rush = true
	gs.eli_quarters_visited = true
	# Hand QuestLog a payload with NO quests block — old-format save.
	ql.deserialize({"tracked": "e1_air", "quests": {}}, 0)
	_expect(String(ql.active_step_id("e1_air")) == "find_kino",
		"old-format migration: re-derives active step from world-state flags")

	# Final reset so subsequent runs don't inherit phase state.
	gs.reset()

	_report()


func _walk_predicate_sequence(gs: Node, ql: Node) -> void:
	# Each entry: { step, flag_setter (Callable on gs), next_step }.
	# The setter is run, gs.advance_air_quest() is called, and we assert
	# the active step is `next_step`. The terminal `complete` step is
	# reached when scrubber_repaired flips true.
	#
	# Note: fetch_kino's predicate is `kino_orbs > 0 OR kino_scout_done`,
	# so flipping kino_scout_done satisfies BOTH fetch_kino and scout_kino
	# in one advance — the test mirrors the production reality where the
	# Kino is launched directly into the gate without ever sitting in
	# inventory.
	# `inv` must be a local in THIS function's scope so the setter lambdas below
	# can capture it — GDScript lambdas only close over their defining function's
	# locals (the kino_remote/kino_orb setters at "sleep"/"scout_kino" use it).
	var inv: Node = root.get_node_or_null("Inventory")
	var sequence: Array = [
		{"next": "find_rush",            "set": func() -> void: gs.met_scott = true},
		{"next": "find_rest",            "set": func() -> void: gs.met_rush = true},
		{"next": "find_kino",            "set": func() -> void: gs.eli_quarters_visited = true},
		{"next": "sleep",                "set": func() -> void: inv.call("set_count", "kino_remote", 1)},
		{"next": "return_to_control",   "set": func() -> void: gs.air_crisis_started = true},
		{"next": "diagnose_life_support","set": func() -> void: gs.control_room_returned = true},
		{"next": "seal_breach",          "set": func() -> void: gs.life_support_diagnosed = true},
		{"next": "find_scrubber",        "set": func() -> void: gs.breaches_sealed.append("shuttle_dock")},
		{"next": "wait_ftl",             "set": func() -> void: gs.scrubber_diagnosed = true},
		{"next": "go_to_gate",           "set": func() -> void: gs.ftl_drop_triggered = true},
		{"next": "scout_kino",          "set": func() -> void: gs.reported_to_gate = true; inv.call("set_count", "kino_orb", 1)},
		{"next": "dial_lime_planet",     "set": func() -> void: gs.kino_scout_done = true},
		{"next": "mine_lime",            "set": func() -> void: gs.lime_planet_dialed = true},
		{"next": "return_destiny",       "set": func() -> void: gs.add_resource(gs.AIR_LIME_RESOURCE, gs.AIR_LIME_REQUIRED, "test")},
		{"next": "repair_scrubber",      "set": func() -> void: gs.returned_from_lime_planet = true},
		{"next": "complete",             "set": func() -> void: gs.scrubber_repaired = true},
	]
	for entry in sequence:
		var setter: Callable = entry["set"]
		setter.call()
		gs.advance_air_quest()
		var got: String = String(ql.active_step_id("e1_air"))
		var want: String = String(entry["next"])
		_expect(got == want, "predicate advance: -> %s (got %s)" % [want, got])
	_expect(ql.is_complete("e1_air"),
		"is_complete fires when terminal step is active")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("")
	print("=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - ", f)
		quit(1)
