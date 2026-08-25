extends SceneTree

# Smoke test for the FactionSystem and MutinySystem autoloads — ship section
# control, faction power/morale, door lock/unlock, mutiny phases, moral
# choices, Rush's secret agenda, and save/load round-trip.
#
# Verifies:
#   • FactionSystem autoload is attached and loaded its config from JSON.
#   • 10 ship sections are registered with correct default controllers.
#   • 4 factions are registered (military, science, civilian, lucian_alliance).
#   • Section control: get/set controller, controlled sections tracking.
#   • Critical sections are identified correctly.
#   • Faction power is calculated from controlled sections + morale.
#   • Faction morale can be adjusted and clamps to [-50, 100].
#   • Door lock/unlock: only controlling faction can lock/unlock.
#   • can_crew_pass: faction membership gates door access.
#   • Decision flags: set/has/get all work.
#   • Faction goals: success/failure condition checking.
#   • Negotiation strength: factors in sections, relationships, morale.
#   • Event effects: apply_event_effects updates all systems.
#   • MutinySystem autoload is attached and loaded its config.
#   • 5 mutiny events are registered across 5 phases.
#   • Phase management: start, advance, set, get_current_phase.
#   • Event access: get_event_info, get_event_choices, get_pending_events.
#   • Making choices: make_choice applies effects, records decision.
#   • Each event has 3 choices with correct effects.
#   • Rush's secret agenda: 4 stages, progression, outcomes.
#   • Mutiny resolution: final standoff resolves with correct outcome.
#   • Negotiation: attempt_negotiation uses faction strength.
#   • Save round-trip: serialize → deserialize preserves all state.
#   • reset() restores initial values.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/faction_warfare.gd

var _passes: int = 0
var _failures: Array[String] = []

# Signal capture.
var _section_changed_received: bool = false
var _section_changed_args: Array = []
var _power_changed_received: bool = false
var _morale_changed_received: bool = false
var _door_lock_changed_received: bool = false
var _phase_changed_received: bool = false
var _phase_changed_args: Array = []
var _event_triggered_received: bool = false
var _choice_made_received: bool = false
var _rush_stage_changed_received: bool = false
var _rush_revealed_received: bool = false
var _mutiny_resolved_received: bool = false
var _mutiny_resolved_outcome: String = ""


func _on_section_changed(sid: String, old: String, new: String) -> void:
	_section_changed_received = true
	_section_changed_args = [sid, old, new]

func _on_power_changed(_fid: String, _power: int) -> void:
	_power_changed_received = true

func _on_morale_changed(_fid: String, _morale: int) -> void:
	_morale_changed_received = true

func _on_door_lock_changed(_sid: String, _locked: bool, _fid: String) -> void:
	_door_lock_changed_received = true

func _on_phase_changed(old: int, new: int) -> void:
	_phase_changed_received = true
	_phase_changed_args = [old, new]

func _on_event_triggered(_eid: String, _phase: int) -> void:
	_event_triggered_received = true

func _on_choice_made(_eid: String, _cid: String) -> void:
	_choice_made_received = true

func _on_rush_stage_changed(_old: String, _new: String) -> void:
	_rush_stage_changed_received = true

func _on_rush_revealed(outcome: String) -> void:
	_rush_revealed_received = true

func _on_mutiny_resolved(outcome: String) -> void:
	_mutiny_resolved_received = true
	_mutiny_resolved_outcome = outcome


func _initialize() -> void:
	print("=== faction_warfare smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var fs: Node = root.get_node_or_null("FactionSystem")
	_expect(fs != null, "FactionSystem autoload is attached")
	if fs == null:
		_report()
		quit(1)
		return

	var ms: Node = root.get_node_or_null("MutinySystem")
	_expect(ms != null, "MutinySystem autoload is attached")
	if ms == null:
		_report()
		quit(1)
		return

	# Save isolation — mandatory per tests/AGENTS.md.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "faction_warfare_smoke")

	# ── FactionSystem: sections ──────────────────────────────────────────────

	var sections: Array = fs.get_all_sections()
	_expect(sections.size() == 10, "10 sections registered (got %d)" % sections.size())

	# Check default controllers
	_expect(fs.get_controller("gate_room") == "military", "gate_room controlled by military")
	_expect(fs.get_controller("control_interface_room") == "military", "control_interface_room controlled by military")
	_expect(fs.get_controller("engineering") == "science", "engineering controlled by science")
	_expect(fs.get_controller("observation_deck") == "science", "observation_deck controlled by science")
	_expect(fs.get_controller("eli_quarters") == "civilian", "eli_quarters controlled by civilian")
	_expect(fs.get_controller("med_bay") == "military", "med_bay controlled by military")
	_expect(fs.get_controller("mess_hall") == "civilian", "mess_hall controlled by civilian")
	_expect(fs.get_controller("aft_storage_hall") == "science", "aft_storage_hall controlled by science")
	_expect(fs.get_controller("south_corridor") == "military", "south_corridor controlled by military")
	_expect(fs.get_controller("north_corridor") == "civilian", "north_corridor controlled by civilian")

	# Section info
	var gate_info: Dictionary = fs.get_section_info("gate_room")
	_expect(gate_info["display_name"] == "Gate Room", "gate_room display name")
	_expect(gate_info["critical"] == true, "gate_room is critical")
	_expect(gate_info["controller"] == "military", "gate_room controller in info")

	var mess_info: Dictionary = fs.get_section_info("mess_hall")
	_expect(mess_info["critical"] == false, "mess_hall is not critical")

	# All section info
	var all_info: Array = fs.get_all_section_info()
	_expect(all_info.size() == 10, "get_all_section_info returns 10 entries")

	# ── FactionSystem: faction sections ─────────────────────────────────────

	var mil_sections: Array = fs.get_faction_sections("military")
	_expect(mil_sections.size() == 4, "military controls 4 sections (got %d)" % mil_sections.size())
	_expect(mil_sections.has("gate_room"), "military has gate_room")
	_expect(mil_sections.has("control_interface_room"), "military has control_interface_room")
	_expect(mil_sections.has("med_bay"), "military has med_bay")
	_expect(mil_sections.has("south_corridor"), "military has south_corridor")

	var sci_sections: Array = fs.get_faction_sections("science")
	_expect(sci_sections.size() == 3, "science controls 3 sections (got %d)" % sci_sections.size())

	var civ_sections: Array = fs.get_faction_sections("civilian")
	_expect(civ_sections.size() == 3, "civilian controls 3 sections (got %d)" % civ_sections.size())

	# Section counts
	_expect(fs.get_section_count("military") == 4, "military section count == 4")
	_expect(fs.get_section_count("science") == 3, "science section count == 3")
	_expect(fs.get_section_count("civilian") == 3, "civilian section count == 3")
	_expect(fs.get_section_count("lucian_alliance") == 0, "lucian_alliance section count == 0")

	# Critical section counts
	_expect(fs.get_critical_section_count("military") == 3, "military has 3 critical sections")
	_expect(fs.get_critical_section_count("science") == 1, "science has 1 critical section")
	_expect(fs.get_critical_section_count("civilian") == 0, "civilian has 0 critical sections")

	# ── FactionSystem: faction power ────────────────────────────────────────

	var mil_power: int = fs.get_faction_power("military")
	_expect(mil_power > 0, "military power > 0 (got %d)" % mil_power)
	# 4 sections (3 critical * 25 + 1 normal * 10 = 85) + morale(50)*0.5 = 25 → 110
	_expect(mil_power == 110, "military power == 110 (got %d)" % mil_power)

	var sci_power: int = fs.get_faction_power("science")
	_expect(sci_power > 0, "science power > 0 (got %d)" % sci_power)
	# 3 sections (1 critical * 25 + 2 normal * 10 = 45) + morale(50)*0.5 = 25 → 70
	_expect(sci_power == 70, "science power == 70 (got %d)" % sci_power)

	var civ_power: int = fs.get_faction_power("civilian")
	_expect(civ_power > 0, "civilian power > 0 (got %d)" % civ_power)
	# 3 sections (0 critical, 3 normal * 10 = 30) + morale(50)*0.5 = 25 → 55
	_expect(civ_power == 55, "civilian power == 55 (got %d)" % civ_power)

	var luc_power: int = fs.get_faction_power("lucian_alliance")
	_expect(luc_power >= 0, "lucian_alliance power >= 0 (got %d)" % luc_power)

	# ── FactionSystem: morale ───────────────────────────────────────────────

	# Default morale is 50 for all factions
	_expect(fs.get_faction_morale("military") == 50, "military default morale == 50")
	_expect(fs.get_faction_morale("science") == 50, "science default morale == 50")
	_expect(fs.get_faction_morale("civilian") == 50, "civilian default morale == 50")
	_expect(fs.get_faction_morale("lucian_alliance") == 50, "lucian_alliance default morale == 50")

	# Connect signals for morale test
	fs.faction_morale_changed.connect(_on_morale_changed)
	_morale_changed_received = false
	fs.adjust_morale("military", -10)
	_expect(_morale_changed_received, "faction_morale_changed signal fired")
	_expect(fs.get_faction_morale("military") == 40, "military morale == 40 after -10")
	fs.faction_morale_changed.disconnect(_on_morale_changed)

	# Clamp to -50
	fs.set_morale("civilian", -100)
	_expect(fs.get_faction_morale("civilian") == -50, "civilian morale clamped to -50")

	# Clamp to 100
	fs.set_morale("civilian", 200)
	_expect(fs.get_faction_morale("civilian") == 100, "civilian morale clamped to 100")

	# Reset morale for later tests
	fs.set_morale("military", 50)
	fs.set_morale("civilian", 50)

	# ── FactionSystem: section control changes ──────────────────────────────

	fs.section_control_changed.connect(_on_section_changed)
	_section_changed_received = false
	fs.set_controller("mess_hall", "military")
	_expect(_section_changed_received, "section_control_changed signal fired")
	_expect(_section_changed_args[0] == "mess_hall", "section id in signal")
	_expect(_section_changed_args[1] == "civilian", "old faction in signal")
	_expect(_section_changed_args[2] == "military", "new faction in signal")
	_expect(fs.get_controller("mess_hall") == "military", "mess_hall now controlled by military")
	_expect(fs.get_section_count("military") == 5, "military now controls 5 sections")
	_expect(fs.get_section_count("civilian") == 2, "civilian now controls 2 sections")
	fs.section_control_changed.disconnect(_on_section_changed)

	# Reset for later tests
	fs.set_controller("mess_hall", "civilian")

	# ── FactionSystem: door lock/unlock ─────────────────────────────────────

	fs.door_lock_state_changed.connect(_on_door_lock_changed)

	# Military controls gate_room — can lock it
	_door_lock_changed_received = false
	var locked: bool = fs.lock_section_doors("gate_room", "military")
	_expect(locked, "military can lock gate_room doors")
	_expect(_door_lock_changed_received, "door_lock_state_changed signal fired")
	_expect(fs.is_section_locked("gate_room"), "gate_room is locked")
	_expect(fs.get_locking_faction("gate_room") == "military", "gate_room locking faction is military")

	# Science cannot lock gate_room (not the controller)
	var locked2: bool = fs.lock_section_doors("gate_room", "science")
	_expect(not locked2, "science cannot lock gate_room doors")

	# Military can unlock
	var unlocked: bool = fs.unlock_section_doors("gate_room", "military")
	_expect(unlocked, "military can unlock gate_room doors")
	_expect(not fs.is_section_locked("gate_room"), "gate_room is unlocked")

	# Unknown section
	var locked3: bool = fs.lock_section_doors("nonexistent_section", "military")
	_expect(not locked3, "locking nonexistent section returns false")

	fs.door_lock_state_changed.disconnect(_on_door_lock_changed)

	# ── FactionSystem: can_crew_pass ────────────────────────────────────────

	# Lock gate_room (military controlled)
	fs.lock_section_doors("gate_room", "military")

	# Military crew can pass
	_expect(fs.can_crew_pass("Colonel Young", "gate_room"), "military crew can pass gate_room")
	_expect(fs.can_crew_pass("Sgt Greer", "gate_room"), "military crew can pass gate_room")

	# Science crew cannot pass
	_expect(not fs.can_crew_pass("Dr Rush", "gate_room"), "science crew cannot pass gate_room")
	_expect(not fs.can_crew_pass("Dr Park", "gate_room"), "science crew cannot pass gate_room")

	# Civilian crew cannot pass
	_expect(not fs.can_crew_pass("Camille", "gate_room"), "civilian crew cannot pass gate_room")

	# Unlock — everyone can pass
	fs.unlock_section_doors("gate_room", "military")
	_expect(fs.can_crew_pass("Dr Rush", "gate_room"), "science crew can pass unlocked gate_room")
	_expect(fs.can_crew_pass("Camille", "gate_room"), "civilian crew can pass unlocked gate_room")

	# Unlocked section — everyone passes
	_expect(fs.can_crew_pass("Dr Rush", "mess_hall"), "science crew can pass unlocked mess_hall")

	# ── FactionSystem: decision flags ──────────────────────────────────────

	_expect(not fs.has_flag("rush_reported"), "rush_reported flag not set initially")
	fs.set_flag("rush_reported")
	_expect(fs.has_flag("rush_reported"), "rush_reported flag is set")
	fs.set_flag("council_formed")
	_expect(fs.has_flag("council_formed"), "council_formed flag is set")
	var flags: Dictionary = fs.get_flags()
	_expect(flags.size() == 2, "2 decision flags set (got %d)" % flags.size())

	# ── FactionSystem: faction goals ────────────────────────────────────────

	var mil_goals: Dictionary = fs.get_faction_goals("military")
	_expect(not mil_goals.is_empty(), "military has goals")
	_expect(mil_goals.has("primary"), "military has primary goal")
	_expect(mil_goals.has("success_condition"), "military has success condition")
	_expect(mil_goals.has("failure_condition"), "military has failure condition")

	# ── FactionSystem: faction summary ──────────────────────────────────────

	var summary: Dictionary = fs.get_faction_summary()
	_expect(summary.size() == 4, "faction summary has 4 entries")
	_expect(summary.has("military"), "summary has military")
	_expect(summary.has("science"), "summary has science")
	_expect(summary.has("civilian"), "summary has civilian")
	_expect(summary.has("lucian_alliance"), "summary has lucian_alliance")
	_expect(summary["military"]["sections"] == 4, "summary military sections == 4")
	_expect(summary["military"]["critical_sections"] == 3, "summary military critical == 3")

	# ── FactionSystem: negotiation strength ─────────────────────────────────

	var mil_str: int = fs.get_negotiation_strength("military")
	_expect(mil_str > 0, "military negotiation strength > 0 (got %d)" % mil_str)
	_expect(mil_str <= 200, "military negotiation strength <= 200 (got %d)" % mil_str)

	var luc_str: int = fs.get_negotiation_strength("lucian_alliance")
	_expect(luc_str >= 0, "lucian_alliance negotiation strength >= 0 (got %d)" % luc_str)

	# ── FactionSystem: apply_event_effects ──────────────────────────────────

	# Reset flags for this section
	fs.reset()

	# Apply a test effect
	fs.apply_event_effects({
		"morale": { "military": 10, "civilian": -10 },
		"sections": { "mess_hall": "military" },
		"flag": "test_flag"
	})
	_expect(fs.get_faction_morale("military") == 60, "military morale == 60 after +10")
	_expect(fs.get_faction_morale("civilian") == 40, "civilian morale == 40 after -10")
	_expect(fs.get_controller("mess_hall") == "military", "mess_hall now military after event")
	_expect(fs.has_flag("test_flag"), "test_flag set by event")

	# ── MutinySystem: events ────────────────────────────────────────────────

	var event_ids: Array = ms.get_event_ids()
	_expect(event_ids.size() == 5, "5 mutiny events registered (got %d)" % event_ids.size())
	_expect(event_ids.has("food_shortage"), "has food_shortage event")
	_expect(event_ids.has("rush_secret_project"), "has rush_secret_project event")
	_expect(event_ids.has("civilian_protest"), "has civilian_protest event")
	_expect(event_ids.has("lucian_infiltration"), "has lucian_infiltration event")
	_expect(event_ids.has("final_standoff"), "has final_standoff event")

	# Event info
	var food_info: Dictionary = ms.get_event_info("food_shortage")
	_expect(food_info["phase"] == 1, "food_shortage is phase 1")
	_expect(food_info["title"] == "Food Shortage", "food_shortage title")
	_expect(food_info["faction_affected"] == "civilian", "food_shortage affects civilian")

	var rush_info: Dictionary = ms.get_event_info("rush_secret_project")
	_expect(rush_info["phase"] == 2, "rush_secret_project is phase 2")

	var standoff_info: Dictionary = ms.get_event_info("final_standoff")
	_expect(standoff_info["phase"] == 5, "final_standoff is phase 5")
	_expect(standoff_info["faction_affected"] == "all", "final_standoff affects all")

	# Event choices
	var food_choices: Array = ms.get_event_choices("food_shortage")
	_expect(food_choices.size() == 3, "food_shortage has 3 choices")
	var food_choice_ids: Array = []
	for c in food_choices:
		food_choice_ids.append(c["id"])
	_expect(food_choice_ids.has("ration_military_priority"), "has ration_military_priority choice")
	_expect(food_choice_ids.has("ration_equal_split"), "has ration_equal_split choice")
	_expect(food_choice_ids.has("ration_science_priority"), "has ration_science_priority choice")

	var standoff_choices: Array = ms.get_event_choices("final_standoff")
	_expect(standoff_choices.size() == 3, "final_standoff has 3 choices")

	# ── MutinySystem: phase management ───────────────────────────────────────

	_expect(ms.get_current_phase() == 0, "initial phase == 0 (Calm)")
	_expect(ms.get_current_phase_name() == "Calm", "initial phase name == Calm")

	ms.mutiny_phase_changed.connect(_on_phase_changed)
	ms.mutiny_event_triggered.connect(_on_event_triggered)
	ms.mutiny_choice_made.connect(_on_choice_made)
	ms.rush_agenda_stage_changed.connect(_on_rush_stage_changed)
	ms.rush_agenda_revealed.connect(_on_rush_revealed)
	ms.mutiny_resolved.connect(_on_mutiny_resolved)

	# Start the mutiny
	_phase_changed_received = false
	_event_triggered_received = false
	ms.start_mutiny()
	_expect(_phase_changed_received, "mutiny_phase_changed signal fired on start")
	_expect(ms.get_current_phase() == 1, "phase == 1 (Tension) after start")
	_expect(ms.get_current_phase_name() == "Tension", "phase name == Tension")
	# Phase 1 auto-triggers food_shortage
	_expect(_event_triggered_received, "mutiny_event_triggered fired for phase 1")

	# Advance to phase 2
	_phase_changed_received = false
	ms.advance_phase()
	_expect(_phase_changed_phase_is(2), "phase == 2 (Division) after advance")

	# Advance to phase 3
	ms.advance_phase()
	_expect(ms.get_current_phase() == 3, "phase == 3 (Crisis)")

	# Advance to phase 4
	ms.advance_phase()
	_expect(ms.get_current_phase() == 4, "phase == 4 (Standoff)")

	# ── MutinySystem: making choices ─────────────────────────────────────────

	# Reset and test choices properly
	ms.mutiny_phase_changed.disconnect(_on_phase_changed)
	ms.mutiny_event_triggered.disconnect(_on_event_triggered)
	ms.reset()
	fs.reset()

	# Start mutiny and make the food shortage choice
	ms.start_mutiny()
	_choice_made_received = false
	var choice_result: bool = ms.make_choice("food_shortage", "ration_equal_split")
	_expect(choice_result, "make_choice returns true for valid choice")
	_expect(_choice_made_received, "mutiny_choice_made signal fired")
	_expect(ms.is_event_completed("food_shortage"), "food_shortage is completed")
	_expect(ms.get_event_choice("food_shortage") == "ration_equal_split", "food_shortage choice recorded")
	_expect(ms.completed_event_count() == 1, "1 completed event")

	# Check effects were applied via FactionSystem
	# ration_equal_split: military morale -10, civilian morale +10
	# Plus event morale_impact: civilian -15, military -5
	# Net: military -15, civilian -5
	_expect(fs.get_faction_morale("military") == 35, "military morale == 35 after food shortage (got %d)" % fs.get_faction_morale("military"))
	_expect(fs.get_faction_morale("civilian") == 45, "civilian morale == 45 after food shortage (got %d)" % fs.get_faction_morale("civilian"))

	# Check relationship effects
	var rs: Node = root.get_node_or_null("RelationshipSystem")
	if rs != null and rs.has_method("get_trust"):
		# Camille trust +10 from ration_equal_split
		var camille_trust: int = rs.get_trust("Camille")
		_expect(camille_trust > 0, "Camille trust increased from equal split (got %d)" % camille_trust)

	# Cannot make the same choice twice
	var choice_result2: bool = ms.make_choice("food_shortage", "ration_military_priority")
	_expect(not choice_result2, "cannot make choice for completed event")

	# Unknown event
	var choice_result3: bool = ms.make_choice("nonexistent_event", "some_choice")
	_expect(not choice_result3, "make_choice returns false for unknown event")

	# Unknown choice
	var choice_result4: bool = ms.make_choice("rush_secret_project", "nonexistent_choice")
	_expect(not choice_result4, "make_choice returns false for unknown choice")

	# ── MutinySystem: Rush's secret agenda ──────────────────────────────────

	# Make the rush_secret_project choice
	_rush_stage_changed_received = false
	ms.make_choice("rush_secret_project", "report_rush")
	_expect(_rush_stage_changed_received, "rush_agenda_stage_changed fired")
	_expect(ms.get_rush_stage() >= 2, "rush stage >= 2 after rush_secret_project (got %d)" % ms.get_rush_stage())
	_expect(fs.has_flag("rush_reported"), "rush_reported flag set by choice")

	# Make the civilian protest choice
	ms.make_choice("civilian_protest", "negotiate_protest")
	_expect(fs.has_flag("council_formed"), "council_formed flag set")

	# Make the lucian infiltration choice
	ms.make_choice("lucian_infiltration", "arrest_simeon")
	_expect(fs.has_flag("simeon_arrested"), "simeon_arrested flag set")

	# ── MutinySystem: final standoff and resolution ──────────────────────────

	# Advance to the standoff phase
	ms.set_phase(4)

	_rush_revealed_received = false
	_mutiny_resolved_received = false
	ms.make_choice("final_standoff", "side_military_end")
	_expect(_mutiny_resolved_received, "mutiny_resolved signal fired")
	_expect(_mutiny_resolved_outcome == "military_victory", "mutiny outcome == military_victory")
	_expect(ms.is_mutiny_resolved(), "mutiny is resolved")
	_expect(ms.get_mutiny_outcome() == "military_victory", "get_mutiny_outcome == military_victory")
	_expect(ms.get_current_phase() == 5, "phase == 5 (Resolved) after standoff")
	_expect(_rush_revealed_received, "rush_agenda_revealed fired on final standoff")
	_expect(ms.is_rush_agenda_revealed(), "rush agenda is revealed")
	_expect(ms.get_rush_agenda_outcome() == "rush_agenda_revealed_military", "rush outcome == military")

	# ── MutinySystem: pending events ─────────────────────────────────────────

	# Reset and check pending events
	ms.reset()
	fs.reset()
	var phase1_pending: Array = ms.get_pending_events(1)
	_expect(phase1_pending.size() == 1, "1 pending event in phase 1 (got %d)" % phase1_pending.size())
	_expect(phase1_pending.has("food_shortage"), "food_shortage is pending in phase 1")

	# ── MutinySystem: negotiation ────────────────────────────────────────────

	var neg_str: int = ms.get_negotiation_strength("military")
	_expect(neg_str > 0, "military negotiation strength > 0 via MutinySystem")

	var neg_result: bool = ms.attempt_negotiation("military", "science")
	# Both have similar strength, should succeed
	_expect(neg_result, "negotiation between military and science succeeds (diff within threshold)")

	# ── MutinySystem: mutiny summary ─────────────────────────────────────────

	var mutiny_summary: Dictionary = ms.get_mutiny_summary()
	_expect(mutiny_summary.has("phase"), "summary has phase")
	_expect(mutiny_summary.has("rush_stage"), "summary has rush_stage")
	_expect(mutiny_summary.has("resolved"), "summary has resolved")

	# ── Save / Load round-trip ──────────────────────────────────────────────

	# Set up a known state
	ms.reset()
	fs.reset()
	ms.start_mutiny()
	ms.make_choice("food_shortage", "ration_military_priority")
	ms.make_choice("rush_secret_project", "help_rush")
	fs.set_controller("engineering", "science")
	fs.lock_section_doors("engineering", "science")
	fs.adjust_morale("military", -20)

	# Serialize
	var fs_data: Dictionary = fs.serialize()
	var ms_data: Dictionary = ms.serialize()

	_expect(fs_data.has("section_controllers"), "fs serialize has section_controllers")
	_expect(fs_data.has("faction_morale"), "fs serialize has faction_morale")
	_expect(fs_data.has("faction_power"), "fs serialize has faction_power")
	_expect(fs_data.has("faction_locked_doors"), "fs serialize has faction_locked_doors")
	_expect(fs_data.has("decision_flags"), "fs serialize has decision_flags")

	_expect(ms_data.has("current_phase"), "ms serialize has current_phase")
	_expect(ms_data.has("completed_events"), "ms serialize has completed_events")
	_expect(ms_data.has("rush_stage"), "ms serialize has rush_stage")

	# Deserialize into fresh state
	fs.reset()
	ms.reset()
	_expect(fs.get_faction_morale("military") == 50, "military morale reset to 50")
	_expect(ms.get_current_phase() == 0, "mutiny phase reset to 0")

	fs.deserialize(fs_data, 2)
	ms.deserialize(ms_data, 2)

	# Verify state was restored
	_expect(fs.get_controller("engineering") == "science", "engineering controller restored")
	_expect(fs.is_section_locked("engineering"), "engineering door lock restored")
	# Military morale: 50 - 20 (adjust) - 5 (food event) + 5 (ration choice) - 10 (rush event) - 20 (help_rush choice) = 0
	_expect(fs.get_faction_morale("military") == 0, "military morale restored to 0 (got %d)" % fs.get_faction_morale("military"))
	_expect(fs.has_flag("rush_helped"), "rush_helped flag restored")
	_expect(ms.get_current_phase() == 1, "mutiny phase restored to 1")
	_expect(ms.is_event_completed("food_shortage"), "food_shortage completion restored")
	_expect(ms.get_event_choice("food_shortage") == "ration_military_priority", "food_shortage choice restored")
	_expect(ms.is_event_completed("rush_secret_project"), "rush_secret_project completion restored")
	_expect(ms.get_rush_stage() >= 2, "rush stage restored")

	# ── Reset ────────────────────────────────────────────────────────────────

	ms.reset()
	fs.reset()
	_expect(ms.get_current_phase() == 0, "mutiny phase == 0 after reset")
	_expect(ms.completed_event_count() == 0, "0 completed events after reset")
	_expect(ms.get_rush_stage() == 0, "rush stage == 0 after reset")
	_expect(ms.get_mutiny_outcome() == "", "mutiny outcome cleared after reset")
	_expect(not fs.has_flag("rush_reported"), "flags cleared after reset")
	_expect(fs.get_faction_morale("military") == 50, "military morale reset to 50")
	_expect(fs.get_controller("engineering") == "science", "engineering controller reset to science")

	# ── Report ───────────────────────────────────────────────────────────────

	_report()
	var exit_code: int = 1 if _failures.size() > 0 else 0
	quit(exit_code)


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("")
	print("  Passes:   %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if _failures.size() > 0:
		print("  ---")
		for f in _failures:
			print("  • %s" % f)
	print("=== faction_warfare smoke test complete ===")


func _phase_changed_phase_is(expected: int) -> bool:
	return _phase_changed_args.size() >= 2 and _phase_changed_args[1] == expected