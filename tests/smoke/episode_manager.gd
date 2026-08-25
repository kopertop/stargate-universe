extends SceneTree

# Smoke test for the EpisodeManager autoload (task t_8a589eee).
#
# Run with:
#   godot --headless --quit-after 60 -s res://tests/smoke/episode_manager.gd
#
# Asserts:
#   • data/episodes.json loads with E1-E5 definitions.
#   • start_episode / complete_episode flow works.
#   • next_episode_id() returns the correct next episode.
#   • is_episode_complete() tracks completed episodes.
#   • Save round-trip (serialize/deserialize) preserves state.
#   • EpisodeManager syncs GameState's legacy vars.
#
# Uses the live autoloads (GameState + EpisodeManager + QuestLog) via
# root.get_node_or_null("Name") — autoloads ARE attached to root in -s
# mode. Save isolation is MANDATORY per tests/AGENTS.md.

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== episode_manager smoke test ===")

	# --- Save isolation (MANDATORY per tests/AGENTS.md) -------------------
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "episode_manager")

	var gs: Node = root.get_node_or_null("GameState")
	var em: Node = root.get_node_or_null("EpisodeManager")
	var ql: Node = root.get_node_or_null("QuestLog")
	_expect(gs != null, "GameState autoload attached")
	_expect(em != null, "EpisodeManager autoload attached")
	_expect(ql != null, "QuestLog autoload attached")
	if gs == null or em == null or ql == null:
		_report()
		return

	# Reset to a clean slate before testing.
	gs.reset()

	# --- 1. Episode definitions load correctly -----------------------------
	_expect(em.total_episodes() == 8, "total_episodes() == 8 (E1-E7 + E12)")
	_expect(em.current_episode_id() == "e1_air",
		"after reset, current episode is e1_air (auto_start)")
	_expect(em.current_episode_title() == "Air",
		"current episode title is 'Air'")
	_expect(em.current_episode_number() == 1,
		"current episode number is 1")
	_expect(not em.is_episode_complete("e1_air"),
		"e1_air is not complete at start")

	# --- 2. next_episode_id() returns correct next episode -----------------
	_expect(em.next_episode_id() == "e2_explore",
		"next_episode_id() after e1_air is e2_explore")
	# Test next_episode_id_for with explicit episode ids.
	_expect(em.next_episode_id_for("e2_explore") == "e3_water",
		"next_episode_id_for('e2_explore') == 'e3_water'")
	_expect(em.next_episode_id_for("e3_water") == "e4_darkness",
		"next_episode_id_for('e3_water') == 'e4_darkness'")
	_expect(em.next_episode_id_for("e4_darkness") == "e5_earth",
		"next_episode_id_for('e4_darkness') == 'e5_earth'")
	_expect(em.next_episode_id_for("e5_earth") == "e6_life",
		"next_episode_id_for('e5_earth') == 'e6_life'")
	_expect(em.next_episode_id_for("e12_divided") == "",
		"next_episode_id_for('e12_divided') == '' (last episode)")

	# --- 3. start_episode / complete_episode flow -------------------------
	# Start e2_explore manually (it has auto_start=false).
	em.start_episode("e2_explore")
	_expect(em.current_episode_id() == "e2_explore",
		"start_episode('e2_explore') sets current to e2_explore")
	_expect(em.current_episode_number() == 2,
		"e2_explore is episode number 2")
	_expect(em.current_episode_title() == "Explore the Ship",
		"e2_explore title is 'Explore the Ship'")

	# Starting an unknown episode is a safe no-op.
	em.start_episode("definitely_not_real")
	_expect(em.current_episode_id() == "e2_explore",
		"start_episode with unknown id is a no-op")

	# Starting an already-active episode is a no-op.
	em.start_episode("e2_explore")
	_expect(em.current_episode_id() == "e2_explore",
		"start_episode with already-active id is a no-op")

	# --- 4. complete_episode flow -----------------------------------------
	# Go back to e1_air to test the full completion chain.
	gs.reset()
	_expect(em.current_episode_id() == "e1_air",
		"after reset, back to e1_air")

	# Complete e1_air — should auto-start e2_explore.
	em.complete_episode("e1_air")
	_expect(em.is_episode_complete("e1_air"),
		"e1_air is complete after complete_episode")
	_expect(em.current_episode_id() == "e2_explore",
		"completing e1_air auto-starts e2_explore")
	_expect(em.current_episode_number() == 2,
		"current episode number is now 2")

	# Completing an already-completed episode is idempotent.
	em.complete_episode("e1_air")
	_expect(em.current_episode_id() == "e2_explore",
		"re-completing e1_air is a no-op (still on e2_explore)")

	# --- 5. GameState legacy var sync -------------------------------------
	_expect(gs.get("episode_complete") == true,
		"GameState.episode_complete is true after completion")
	_expect(String(gs.get("current_episode")) == "e2_explore",
		"GameState.current_episode synced to e2_explore")

	# --- 6. check_completion predicate evaluation -------------------------
	gs.reset()
	# scrubber_repaired is false after reset → e1_air not complete.
	_expect(not em.check_completion("e1_air"),
		"check_completion('e1_air') is false when scrubber not repaired")
	# Set the flag and check again.
	gs.set("scrubber_repaired", true)
	_expect(em.check_completion("e1_air"),
		"check_completion('e1_air') is true when scrubber_repaired")

	# --- 7. check_current_episode_complete() ------------------------------
	gs.reset()
	gs.set("scrubber_repaired", true)
	em.call("check_current_episode_complete")
	_expect(em.is_episode_complete("e1_air"),
		"check_current_episode_complete() completes e1_air when predicate satisfied")
	_expect(em.current_episode_id() == "e2_explore",
		"check_current_episode_complete() auto-started e2_explore")

	# --- 8. Save round-trip (serialize/deserialize) ------------------------
	gs.reset()
	em.complete_episode("e1_air")
	# We should now be on e2_explore with e1_air completed.
	var snap: Dictionary = em.serialize()
	_expect(String(snap.get("current_episode_id", "")) == "e2_explore",
		"serialize captures current_episode_id")
	var saved_completed: Array = snap.get("completed_episodes", [])
	_expect(saved_completed.has("e1_air"),
		"serialize captures completed_episodes list")

	# Deserialize into a fresh state.
	gs.reset()
	em.deserialize(snap, 2)
	_expect(em.current_episode_id() == "e2_explore",
		"deserialize restores current_episode_id to e2_explore")
	_expect(em.is_episode_complete("e1_air"),
		"deserialize restores completed_episodes (e1_air)")

	# --- 9. deserialize with empty data (fresh save) ----------------------
	gs.reset()
	em.deserialize({}, 2)
	# Should auto-start e1_air since it has auto_start=true.
	_expect(em.current_episode_id() == "e1_air",
		"deserialize with empty data auto-starts e1_air")
	_expect(not em.is_episode_complete("e1_air"),
		"deserialize with empty data has no completed episodes")

	# --- 10. All episodes completed signal --------------------------------
	# Complete all episodes and check all_episodes_completed fires.
	gs.reset()
	var all_done_fired: Array[bool] = []
	var on_all_done := func() -> void: all_done_fired.append(true)
	em.all_episodes_completed.connect(on_all_done)
	# Complete all 8 episodes in sequence.
	em.complete_episode("e1_air")
	em.complete_episode("e2_explore")
	em.complete_episode("e3_water")
	em.complete_episode("e4_darkness")
	em.complete_episode("e5_earth")
	em.complete_episode("e6_life")
	em.complete_episode("e7_justice")
	em.complete_episode("e12_divided")
	_expect(all_done_fired.size() == 1,
		"all_episodes_completed emitted once after last episode")
	_expect(em.is_episode_complete("e12_divided"),
		"e12_divided is complete")
	em.all_episodes_completed.disconnect(on_all_done)

	# Final reset so subsequent runs don't inherit state.
	gs.reset()

	_report()


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
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)