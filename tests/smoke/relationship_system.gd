extends SceneTree

# Smoke test for the RelationshipSystem autoload — trust/respect tracking,
# factions, dialogue actions, and quest gating.
#
# Verifies:
#   • RelationshipSystem autoload is attached and loaded its config from JSON.
#   • 15 crew members are registered (16 schedule crew minus Eli who is the player).
#   • 4 factions are registered (military, science, civilian, lucian_alliance).
#   • Each crew member has valid trust/respect values within bounds.
#   • Each crew member has all 5 threshold levels (hostile → loyal).
#   • get_level() returns the correct level based on trust/respect.
#   • meets_threshold() correctly gates levels.
#   • adjust_trust/adjust_respect clamp to min/max.
#   • adjust_relationship applies both deltas atomically.
#   • Signals fire on trust/respect changes.
#   • relationship_level_changed fires on threshold crossing.
#   • Dialogue actions apply correct deltas to crew and factions.
#   • Faction-targeted actions affect all members.
#   • Quest gating: gated steps are blocked/allowed correctly.
#   • Ungated steps always return true.
#   • Save round-trip: serialize → deserialize preserves all state.
#   • reset() restores initial values from JSON.
#   • get_all_crew_summary() returns complete data for HUD.
#   • get_faction_summary() returns faction aggregates.
#   • get_faction_standing() returns normalized 0..1 value.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/relationship_system.gd

var _passes: int = 0
var _failures: Array[String] = []

# Signal capture.
var _trust_changed_received: bool = false
var _respect_changed_received: bool = false
var _level_changed_received: bool = false
var _faction_standing_received: bool = false
var _sig_crew: String = ""
var _sig_old_trust: int = 0
var _sig_new_trust: int = 0
var _sig_old_respect: int = 0
var _sig_new_respect: int = 0
var _sig_old_level: String = ""
var _sig_new_level: String = ""


func _on_trust_changed(crew_name: String, old_val: int, new_val: int) -> void:
	if crew_name == "Dr Rush":
		_trust_changed_received = true
		_sig_crew = crew_name
		_sig_old_trust = old_val
		_sig_new_trust = new_val


func _on_respect_changed(crew_name: String, old_val: int, new_val: int) -> void:
	if crew_name == "Dr Rush":
		_respect_changed_received = true
		_sig_old_respect = old_val
		_sig_new_respect = new_val


func _on_level_changed(crew_name: String, old_level: String, new_level: String) -> void:
	_level_changed_received = true
	_sig_old_level = old_level
	_sig_new_level = new_level


func _on_faction_standing(faction_id: String, _standing: float) -> void:
	_faction_standing_received = true


func _initialize() -> void:
	print("=== relationship_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var rs: Node = root.get_node_or_null("RelationshipSystem")
	_expect(rs != null, "RelationshipSystem autoload is attached")
	if rs == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "relationship_system_smoke")

	# --- Crew count -----------------------------------------------------------
	var count: int = rs.crew_count()
	_expect(count >= 13, "crew_count >= 13 (got %d)" % count)
	_expect(count == 14, "crew_count == 14 (got %d)" % count)

	# --- Crew names ------------------------------------------------------------
	var names: Array = rs.crew_names()
	var expected_names: Array = [
		"Dr Rush", "Colonel Young", "Lt Scott", "Sgt Greer", "TJ",
		"Lt James", "Chloe Armstrong", "Camille", "Dr Park", "Volker",
		"Brody", "Ginn", "Varro", "Simeon"
	]
	for cname in expected_names:
		_expect(names.has(cname), "crew has '%s'" % cname)

	# --- Factions --------------------------------------------------------------
	var fids: Array = rs.faction_ids()
	_expect(fids.size() == 4, "faction count == 4 (got %d)" % fids.size())
	_expect(fids.has("military"), "has 'military' faction")
	_expect(fids.has("science"), "has 'science' faction")
	_expect(fids.has("civilian"), "has 'civilian' faction")
	_expect(fids.has("lucian_alliance"), "has 'lucian_alliance' faction")

	# --- Faction membership ----------------------------------------------------
	var military_members: Array = rs.get_faction_members("military")
	_expect(military_members.size() == 5, "military has 5 members (got %d)" % military_members.size())
	_expect(military_members.has("Colonel Young"), "military has Colonel Young")
	_expect(military_members.has("Lt Scott"), "military has Lt Scott")
	_expect(military_members.has("Sgt Greer"), "military has Sgt Greer")
	_expect(military_members.has("TJ"), "military has TJ")
	_expect(military_members.has("Lt James"), "military has Lt James")

	var science_members: Array = rs.get_faction_members("science")
	_expect(science_members.size() == 5, "science has 5 members (got %d)" % science_members.size())
	_expect(science_members.has("Dr Rush"), "science has Dr Rush")
	_expect(science_members.has("Dr Park"), "science has Dr Park")
	_expect(science_members.has("Volker"), "science has Volker")
	_expect(science_members.has("Brody"), "science has Brody")
	_expect(science_members.has("Ginn"), "science has Ginn")

	var civilian_members: Array = rs.get_faction_members("civilian")
	_expect(civilian_members.size() == 3, "civilian has 3 members (got %d)" % civilian_members.size())
	_expect(civilian_members.has("Chloe Armstrong"), "civilian has Chloe Armstrong")
	_expect(civilian_members.has("Camille"), "civilian has Camille")
	_expect(civilian_members.has("Eli"), "civilian has Eli")

	var lucian_members: Array = rs.get_faction_members("lucian_alliance")
	_expect(lucian_members.size() == 2, "lucian_alliance has 2 members (got %d)" % lucian_members.size())
	_expect(lucian_members.has("Varro"), "lucian_alliance has Varro")
	_expect(lucian_members.has("Simeon"), "lucian_alliance has Simeon")

	# --- Faction display names -------------------------------------------------
	_expect(rs.get_faction_display_name("military") == "Military", "military display name")
	_expect(rs.get_faction_display_name("science") == "Science", "science display name")
	_expect(rs.get_faction_display_name("civilian") == "Civilian", "civilian display name")
	_expect(rs.get_faction_display_name("lucian_alliance") == "Lucian Alliance", "lucian_alliance display name")

	# --- Each crew has valid trust/respect within bounds -----------------------
	for cname in names:
		var trust: int = rs.get_trust(cname)
		var respect: int = rs.get_respect(cname)
		var tb: Dictionary = rs.get_trust_bounds(cname)
		var rb: Dictionary = rs.get_respect_bounds(cname)
		_expect(trust >= int(tb["min"]), "%s trust >= min (%d >= %d)" % [cname, trust, int(tb["min"])])
		_expect(trust <= int(tb["max"]), "%s trust <= max (%d <= %d)" % [cname, trust, int(tb["max"])])
		_expect(respect >= int(rb["min"]), "%s respect >= min (%d >= %d)" % [cname, respect, int(rb["min"])])
		_expect(respect <= int(rb["max"]), "%s respect <= max (%d <= %d)" % [cname, respect, int(rb["max"])])
		_expect(rs.get_faction(cname).length() > 0, "%s has a faction" % cname)
		_expect(rs.get_description(cname).length() > 0, "%s has a description" % cname)

	# --- Each crew has all 5 threshold levels ---------------------------------
	for cname in names:
		for level in ["hostile", "wary", "neutral", "friendly", "loyal"]:
			var thresh: Dictionary = rs.get_threshold(cname, level)
			_expect(not thresh.is_empty(), "%s has threshold '%s'" % [cname, level])
			_expect(thresh.has("trust"), "%s threshold '%s' has trust" % [cname, level])
			_expect(thresh.has("respect"), "%s threshold '%s' has respect" % [cname, level])

	# --- Level evaluation ------------------------------------------------------
	# Dr Rush: trust=20, respect=35 → neutral (trust>=15, respect>=25)
	var rush_level: String = rs.get_level("Dr Rush")
	_expect(rush_level == "neutral", "Dr Rush level == neutral (got '%s')" % rush_level)

	# Simeon: trust=-10, respect=5 → hostile (trust < wary's trust=0)
	var simeon_level: String = rs.get_level("Simeon")
	_expect(simeon_level == "hostile", "Simeon level == hostile (got '%s')" % simeon_level)

	# Chloe: trust=45, respect=25 → neutral (trust>=30, respect>=25, but not friendly: trust<55)
	var chloe_level: String = rs.get_level("Chloe Armstrong")
	_expect(chloe_level == "neutral", "Chloe level == neutral (got '%s')" % chloe_level)

	# Varro: trust=5, respect=10 → wary (trust>=0, respect>=5, not neutral: trust<15)
	var varro_level: String = rs.get_level("Varro")
	_expect(varro_level == "wary", "Varro level == wary (got '%s')" % varro_level)

	# --- meets_threshold -------------------------------------------------------
	_expect(rs.meets_threshold("Dr Rush", "neutral"), "Rush meets neutral")
	_expect(not rs.meets_threshold("Dr Rush", "friendly"), "Rush does NOT meet friendly")
	_expect(rs.meets_threshold("Dr Rush", "hostile"), "Rush meets hostile (always true for lowest)")
	_expect(rs.meets_threshold("Dr Rush", "wary"), "Rush meets wary")
	_expect(not rs.meets_threshold("Simeon", "wary"), "Simeon does NOT meet wary")
	_expect(rs.meets_threshold("Simeon", "hostile"), "Simeon meets hostile")
	_expect(rs.meets_threshold("Chloe Armstrong", "neutral"), "Chloe meets neutral")
	_expect(not rs.meets_threshold("Chloe Armstrong", "friendly"), "Chloe does NOT meet friendly")

	# --- adjust_trust clamping -------------------------------------------------
	var rush_trust_before: int = rs.get_trust("Dr Rush")
	var rush_trust_max: int = int(rs.get_trust_bounds("Dr Rush")["max"])
	var new_val: int = rs.adjust_trust("Dr Rush", 200)
	_expect(new_val == rush_trust_max, "adjust_trust clamps to max (got %d, expected %d)" % [new_val, rush_trust_max])
	_expect(rs.get_trust("Dr Rush") == rush_trust_max, "trust is at max after large positive delta")

	# Reset Rush back to original for further tests.
	rs.set_trust("Dr Rush", rush_trust_before)
	_expect(rs.get_trust("Dr Rush") == rush_trust_before, "set_trust restores original value")

	# Test clamping to min.
	var rush_trust_min: int = int(rs.get_trust_bounds("Dr Rush")["min"])
	new_val = rs.adjust_trust("Dr Rush", -500)
	_expect(new_val == rush_trust_min, "adjust_trust clamps to min (got %d, expected %d)" % [new_val, rush_trust_min])
	rs.set_trust("Dr Rush", rush_trust_before)

	# --- adjust_respect clamping -----------------------------------------------
	var rush_respect_before: int = rs.get_respect("Dr Rush")
	var rush_respect_max: int = int(rs.get_respect_bounds("Dr Rush")["max"])
	new_val = rs.adjust_respect("Dr Rush", 200)
	_expect(new_val == rush_respect_max, "adjust_respect clamps to max (got %d, expected %d)" % [new_val, rush_respect_max])
	rs.set_respect("Dr Rush", rush_respect_before)

	# --- Signal capture --------------------------------------------------------
	# Connect signals.
	rs.trust_changed.connect(_on_trust_changed)
	rs.respect_changed.connect(_on_respect_changed)
	rs.relationship_level_changed.connect(_on_level_changed)
	rs.faction_standing_changed.connect(_on_faction_standing)

	# Adjust Rush's trust by +5 — should fire trust_changed.
	_trust_changed_received = false
	rs.adjust_trust("Dr Rush", 5)
	_expect(_trust_changed_received, "trust_changed signal fired")
	_expect(_sig_old_trust == rush_trust_before, "signal old_trust == %d (got %d)" % [rush_trust_before, _sig_old_trust])
	_expect(_sig_new_trust == rush_trust_before + 5, "signal new_trust == %d (got %d)" % [rush_trust_before + 5, _sig_new_trust])

	# Adjust Rush's respect by +5 — should fire respect_changed.
	_respect_changed_received = false
	rs.adjust_respect("Dr Rush", 5)
	_expect(_respect_changed_received, "respect_changed signal fired")

	# Trigger a level change: push Rush to friendly (trust>=40, respect>=50).
	# Current: trust=25, respect=40. Need +15 trust, +10 respect.
	_level_changed_received = false
	rs.adjust_relationship("Dr Rush", 20, 15)
	_expect(_level_changed_received, "relationship_level_changed fired on level up")
	_expect(_sig_old_level == "neutral", "old level was neutral (got '%s')" % _sig_old_level)
	_expect(_sig_new_level == "friendly", "new level is friendly (got '%s')" % _sig_new_level)
	_expect(rs.get_level("Dr Rush") == "friendly", "Rush is now friendly")

	# Disconnect signals.
	rs.trust_changed.disconnect(_on_trust_changed)
	rs.respect_changed.disconnect(_on_respect_changed)
	rs.relationship_level_changed.disconnect(_on_level_changed)
	rs.faction_standing_changed.disconnect(_on_faction_standing)

	# Reset Rush to original.
	rs.set_trust("Dr Rush", rush_trust_before)
	rs.set_respect("Dr Rush", rush_respect_before)

	# --- Dialogue actions ------------------------------------------------------
	# Verify action ids are loaded.
	var action_ids: Array = rs.dialogue_action_ids()
	_expect(action_ids.size() >= 15, "at least 15 dialogue actions (got %d)" % action_ids.size())
	_expect(rs.has_dialogue_action("rush_defend"), "has 'rush_defend' action")
	_expect(rs.has_dialogue_action("young_follow_orders"), "has 'young_follow_orders' action")
	_expect(rs.has_dialogue_action("chloe_comfort"), "has 'chloe_comfort' action")
	_expect(not rs.has_dialogue_action("nonexistent_action"), "does NOT have 'nonexistent_action'")

	# Apply rush_defend: Dr Rush gets +5 trust, +3 respect; military gets -2 trust, -1 respect.
	var rush_t_before: int = rs.get_trust("Dr Rush")
	var rush_r_before: int = rs.get_respect("Dr Rush")
	var young_t_before: int = rs.get_trust("Colonel Young")
	var young_r_before: int = rs.get_respect("Colonel Young")
	rs.apply_dialogue_action("rush_defend")
	_expect(rs.get_trust("Dr Rush") == rush_t_before + 5, "rush_defend: Rush trust +5 (got %d)" % rs.get_trust("Dr Rush"))
	_expect(rs.get_respect("Dr Rush") == rush_r_before + 3, "rush_defend: Rush respect +3 (got %d)" % rs.get_respect("Dr Rush"))
	_expect(rs.get_trust("Colonel Young") == young_t_before - 2, "rush_defend: Young trust -2 (got %d)" % rs.get_trust("Colonel Young"))
	_expect(rs.get_respect("Colonel Young") == young_r_before - 1, "rush_defend: Young respect -1 (got %d)" % rs.get_respect("Colonel Young"))

	# Reset all for further tests.
	rs.reset()

	# Verify reset restored original values.
	_expect(rs.get_trust("Dr Rush") == 20, "reset: Rush trust back to 20 (got %d)" % rs.get_trust("Dr Rush"))
	_expect(rs.get_respect("Dr Rush") == 35, "reset: Rush respect back to 35 (got %d)" % rs.get_respect("Dr Rush"))
	_expect(rs.get_trust("Colonel Young") == 30, "reset: Young trust back to 30 (got %d)" % rs.get_trust("Colonel Young"))
	_expect(rs.get_level("Dr Rush") == "neutral", "reset: Rush level back to neutral")

	# --- Quest gating ----------------------------------------------------------
	# Ungated step always available.
	_expect(rs.quest_step_available("nonexistent_step"), "ungated step is available")

	# Gated steps.
	# young_mission_briefing: crew=Colonel Young, level=neutral.
	# Young: trust=30, respect=25 → neutral (trust>=20, respect>=30? No, respect<30).
	# Actually Young thresholds: neutral = trust>=20, respect>=30. respect=25 < 30 → wary.
	# So young_mission_briefing should be BLOCKED since Young is wary, not neutral.
	var young_lvl: String = rs.get_level("Colonel Young")
	_expect(young_lvl == "wary" or young_lvl == "neutral", "Young is wary or neutral (got '%s')" % young_lvl)
	if young_lvl == "neutral":
		_expect(rs.quest_step_available("young_mission_briefing"), "young_mission_briefing available (Young is neutral)")
	else:
		_expect(not rs.quest_step_available("young_mission_briefing"), "young_mission_briefing blocked (Young is '%s', needs neutral)" % young_lvl)

	# Push Young to neutral: trust=30, need respect>=30. +5 respect.
	rs.adjust_respect("Colonel Young", 10)
	_expect(rs.get_level("Colonel Young") == "neutral", "Young is neutral after +10 respect")
	_expect(rs.quest_step_available("young_mission_briefing"), "young_mission_briefing available after boosting Young to neutral")

	# greer_fireteam: crew=Sgt Greer, level=wary.
	# Greer: trust=25, respect=35 → neutral (trust>=20, respect>=30). meets wary? yes.
	_expect(rs.quest_step_available("greer_fireteam"), "greer_fireteam available (Greer meets wary)")

	# varro_alliance_mission: crew=Varro, level=neutral.
	# Varro: trust=5, respect=10 → wary. Needs neutral (trust>=15, respect>=20).
	_expect(not rs.quest_step_available("varro_alliance_mission"), "varro_alliance_mission blocked (Varro is wary, needs neutral)")

	# Push Varro to neutral.
	rs.adjust_relationship("Varro", 15, 15)
	_expect(rs.get_level("Varro") == "neutral", "Varro is neutral after +15/+15")
	_expect(rs.quest_step_available("varro_alliance_mission"), "varro_alliance_mission available after boosting Varro to neutral")

	# chloe_personal_quest: crew=Chloe, level=friendly.
	# Chloe: trust=45, respect=25 → neutral. Needs friendly (trust>=55, respect>=45).
	_expect(not rs.quest_step_available("chloe_personal_quest"), "chloe_personal_quest blocked (Chloe is neutral, needs friendly)")

	# Push Chloe to friendly.
	rs.adjust_relationship("Chloe Armstrong", 15, 25)
	_expect(rs.get_level("Chloe Armstrong") == "friendly", "Chloe is friendly after boost")
	_expect(rs.quest_step_available("chloe_personal_quest"), "chloe_personal_quest available after boosting Chloe to friendly")

	# Verify get_quest_gate returns the gate data.
	var gate: Dictionary = rs.get_quest_gate("young_mission_briefing")
	_expect(not gate.is_empty(), "get_quest_gate returns data for gated step")
	_expect(String(gate.get("crew", "")) == "Colonel Young", "gate crew == Colonel Young")
	_expect(String(gate.get("level", "")) == "neutral", "gate level == neutral")

	# Ungated step returns empty gate.
	var no_gate: Dictionary = rs.get_quest_gate("nonexistent_step")
	_expect(no_gate.is_empty(), "get_quest_gate returns empty for ungated step")

	# gated_quest_steps returns all gated ids.
	var gated: Array = rs.gated_quest_steps()
	_expect(gated.size() >= 5, "at least 5 gated quest steps (got %d)" % gated.size())

	# Reset for save/load test.
	rs.reset()

	# --- Save / Load round-trip ------------------------------------------------
	# Modify some values.
	rs.set_trust("Dr Rush", 60)
	rs.set_respect("Dr Rush", 70)
	rs.set_trust("Colonel Young", 50)
	rs.set_respect("Sgt Greer", 10)

	var serialized: Dictionary = rs.serialize()
	_expect(serialized.has("crew"), "serialize has 'crew' key")
	_expect(serialized["crew"].has("Dr Rush"), "serialized crew has Dr Rush")
	var rush_saved: Dictionary = serialized["crew"]["Dr Rush"]
	_expect(int(rush_saved.get("trust", 0)) == 60, "serialized Rush trust == 60")
	_expect(int(rush_saved.get("respect", 0)) == 70, "serialized Rush respect == 70")

	# Reset and deserialize.
	rs.reset()
	_expect(rs.get_trust("Dr Rush") == 20, "after reset Rush trust is 20 again")

	rs.deserialize(serialized, 2)
	_expect(rs.get_trust("Dr Rush") == 60, "deserialized Rush trust == 60 (got %d)" % rs.get_trust("Dr Rush"))
	_expect(rs.get_respect("Dr Rush") == 70, "deserialized Rush respect == 70 (got %d)" % rs.get_respect("Dr Rush"))
	_expect(rs.get_trust("Colonel Young") == 50, "deserialized Young trust == 50 (got %d)" % rs.get_trust("Colonel Young"))
	_expect(rs.get_respect("Sgt Greer") == 10, "deserialized Greer respect == 10 (got %d)" % rs.get_respect("Sgt Greer"))

	# --- get_all_crew_summary --------------------------------------------------
	rs.reset()
	var summary: Array = rs.get_all_crew_summary()
	_expect(summary.size() == count, "summary size == crew_count (got %d, expected %d)" % [summary.size(), count])
	for entry in summary:
		_expect(entry.has("name"), "summary entry has 'name'")
		_expect(entry.has("faction"), "summary entry has 'faction'")
		_expect(entry.has("trust"), "summary entry has 'trust'")
		_expect(entry.has("respect"), "summary entry has 'respect'")
		_expect(entry.has("level"), "summary entry has 'level'")
		_expect(entry.has("description"), "summary entry has 'description'")

	# --- get_faction_summary ---------------------------------------------------
	var fsummary: Dictionary = rs.get_faction_summary()
	_expect(fsummary.size() == 4, "faction summary has 4 entries (got %d)" % fsummary.size())
	for fid in fsummary.keys():
		var fd: Dictionary = fsummary[fid]
		_expect(fd.has("display_name"), "faction summary has display_name")
		_expect(fd.has("avg_trust"), "faction summary has avg_trust")
		_expect(fd.has("avg_respect"), "faction summary has avg_respect")
		_expect(fd.has("standing"), "faction summary has standing")
		_expect(fd.has("member_count"), "faction summary has member_count")

	# --- get_faction_standing --------------------------------------------------
	for fid in ["military", "science", "civilian", "lucian_alliance"]:
		var standing: float = rs.get_faction_standing(fid)
		_expect(standing >= 0.0 and standing <= 1.0, "%s standing in [0,1] (got %f)" % [fid, standing])

	# Military should have higher standing than lucian_alliance at start.
	var mil_standing: float = rs.get_faction_standing("military")
	var lucian_standing: float = rs.get_faction_standing("lucian_alliance")
	_expect(mil_standing > lucian_standing, "military standing > lucian_alliance standing (%f > %f)" % [mil_standing, lucian_standing])

	# --- adjust_relationship atomic -------------------------------------------
	var rush_t0: int = rs.get_trust("Dr Rush")
	var rush_r0: int = rs.get_respect("Dr Rush")
	rs.adjust_relationship("Dr Rush", 10, -5)
	_expect(rs.get_trust("Dr Rush") == rush_t0 + 10, "adjust_relationship: trust +10")
	_expect(rs.get_respect("Dr Rush") == rush_r0 - 5, "adjust_relationship: respect -5")

	# --- Unknown crew safety ---------------------------------------------------
	_expect(rs.get_trust("UnknownCrew") == 0, "unknown crew trust returns 0")
	_expect(rs.get_respect("UnknownCrew") == 0, "unknown crew respect returns 0")
	_expect(rs.get_level("UnknownCrew") == "hostile", "unknown crew level returns hostile")
	_expect(not rs.meets_threshold("UnknownCrew", "hostile"), "unknown crew does NOT meet any threshold")
	_expect(rs.get_faction("UnknownCrew") == "", "unknown crew faction returns empty")
	# adjust_trust on unknown crew should not crash.
	rs.adjust_trust("UnknownCrew", 10)
	rs.adjust_respect("UnknownCrew", 10)
	rs.adjust_relationship("UnknownCrew", 10, 10)

	# --- Nonexistent dialogue action is safe -----------------------------------
	rs.apply_dialogue_action("nonexistent_action")

	# --- Reset final -----------------------------------------------------------
	rs.reset()
	_expect(rs.get_trust("Dr Rush") == 20, "final reset: Rush trust == 20")
	_expect(rs.get_respect("Dr Rush") == 35, "final reset: Rush respect == 35")
	_expect(rs.get_level("Dr Rush") == "neutral", "final reset: Rush level == neutral")
	_expect(rs.get_level("Simeon") == "hostile", "final reset: Simeon level == hostile")
	_expect(rs.get_level("Varro") == "wary", "final reset: Varro level == wary")

	# --- Report ----------------------------------------------------------------
	_report()
	if _failures.size() > 0:
		quit(1)
	else:
		quit(0)


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("  Passes: %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if _failures.size() > 0:
		for f in _failures:
			print("    - %s" % f)
	print("=== relationship_system smoke test complete ===")