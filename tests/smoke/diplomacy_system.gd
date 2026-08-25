extends SceneTree

# Smoke test for the DiplomacySystem autoload — faction reputation, trade,
# negotiations, language puzzles, alliances, and combat fallback.
#
# Verifies:
#   • DiplomacySystem autoload is attached and loaded its config from JSON.
#   • 4 alien factions are registered (nakai, ursini, drifters, builders).
#   • Each faction has valid reputation values within bounds.
#   • Reputation levels map correctly (war → hostile → wary → neutral → friendly → allied).
#   • adjust_reputation clamps to min/max and emits signals.
#   • set_reputation works and emits signals.
#   • meets_reputation_level gates correctly.
#   • Trade offers: can_trade checks reputation + resources, execute_trade grants tech.
#   • Trade fails on insufficient reputation or resources.
#   • Negotiations: attempt_negotiation with deterministic seed produces expected results.
#   • Language puzzles: decode_fragment tracks progress, completion awards reputation.
#   • Alliances: can_form_alliance checks reputation + language, form_alliance activates.
#   • Alliance breaks when reputation drops below threshold.
#   • Combat fallback: is_combat_only triggers at war level, resolve_combat adjusts reputation.
#   • Diplomacy actions: apply_diplomacy_action adjusts reputation from data.
#   • Save round-trip: serialize → deserialize preserves all state.
#   • reset() restores initial values from JSON.
#   • get_faction_summaries() returns complete data for HUD.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/diplomacy_system.gd

var _passes: int = 0
var _failures: Array[String] = []

# Signal capture.
var _rep_changed_received: bool = false
var _rep_level_changed_received: bool = false
var _trade_completed_received: bool = false
var _trade_failed_received: bool = false
var _negotiation_completed_received: bool = false
var _language_fragment_decoded_received: bool = false
var _language_puzzle_completed_received: bool = false
var _alliance_formed_received: bool = false
var _alliance_broken_received: bool = false
var _combat_triggered_received: bool = false
var _combat_resolved_received: bool = false
var _sig_faction: String = ""
var _sig_old_rep: int = 0
var _sig_new_rep: int = 0
var _sig_old_level: String = ""
var _sig_new_level: String = ""


func _on_rep_changed(faction_id: String, old_val: int, new_val: int) -> void:
	if faction_id == "nakai":
		_rep_changed_received = true
		_sig_faction = faction_id
		_sig_old_rep = old_val
		_sig_new_rep = new_val


func _on_rep_level_changed(faction_id: String, old_level: String, new_level: String) -> void:
	if faction_id == "nakai":
		_rep_level_changed_received = true
		_sig_old_level = old_level
		_sig_new_level = new_level


func _on_trade_completed(offer_id: String, faction_id: String) -> void:
	_trade_completed_received = true


func _on_trade_failed(offer_id: String, reason: String) -> void:
	_trade_failed_received = true


func _on_negotiation_completed(neg_id: String, approach: String, success: bool) -> void:
	_negotiation_completed_received = true


func _on_language_fragment_decoded(faction_id: String, fragment_id: String) -> void:
	_language_fragment_decoded_received = true


func _on_language_puzzle_completed(faction_id: String, language_id: String) -> void:
	_language_puzzle_completed_received = true


func _on_alliance_formed(alliance_id: String) -> void:
	_alliance_formed_received = true


func _on_alliance_broken(alliance_id: String) -> void:
	_alliance_broken_received = true


func _on_combat_triggered(faction_id: String) -> void:
	_combat_triggered_received = true


func _on_combat_resolved(faction_id: String, victory: bool) -> void:
	_combat_resolved_received = true


func _initialize() -> void:
	print("=== diplomacy_system smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	var ds: Node = root.get_node_or_null("DiplomacySystem")
	_expect(ds != null, "DiplomacySystem autoload is attached")
	if ds == null:
		_report()
		quit(1)
		return

	# Connect signal listeners.
	ds.reputation_changed.connect(_on_rep_changed)
	ds.reputation_level_changed.connect(_on_rep_level_changed)
	ds.trade_completed.connect(_on_trade_completed)
	ds.trade_failed.connect(_on_trade_failed)
	ds.negotiation_completed.connect(_on_negotiation_completed)
	ds.language_fragment_decoded.connect(_on_language_fragment_decoded)
	ds.language_puzzle_completed.connect(_on_language_puzzle_completed)
	ds.alliance_formed.connect(_on_alliance_formed)
	ds.alliance_broken.connect(_on_alliance_broken)
	ds.combat_triggered.connect(_on_combat_triggered)
	ds.combat_resolved.connect(_on_combat_resolved)

	# --- Factions registered --------------------------------------------------
	var faction_ids: Array = ds.get_all_faction_ids()
	_expect(faction_ids.size() == 4, "4 factions registered (got %d)" % faction_ids.size())
	_expect(faction_ids.has("nakai"), "nakai faction exists")
	_expect(faction_ids.has("ursini"), "ursini faction exists")
	_expect(faction_ids.has("drifters"), "drifters faction exists")
	_expect(faction_ids.has("builders"), "builders faction exists")

	# --- Faction display names and descriptions ------------------------------
	_expect(ds.get_faction_display_name("nakai") == "Nakai", "nakai display name")
	_expect(ds.get_faction_display_name("ursini") == "Ursini", "ursini display name")
	_expect(ds.get_faction_display_name("drifters") == "Drifters", "drifters display name")
	_expect(ds.get_faction_display_name("builders") == "The Builders", "builders display name")
	_expect(not ds.get_faction_description("nakai").is_empty(), "nakai has description")
	_expect(ds.get_faction_home_world("nakai") == "Nakai Prime", "nakai home world")
	_expect(ds.get_faction_personality("nakai") == "honorable", "nakai personality")

	# --- Starting reputation --------------------------------------------------
	_expect(ds.get_reputation("nakai") == 0, "nakai starting reputation == 0")
	_expect(ds.get_reputation("ursini") == 10, "ursini starting reputation == 10")
	_expect(ds.get_reputation("drifters") == -20, "drifters starting reputation == -20")
	_expect(ds.get_reputation("builders") == 0, "builders starting reputation == 0")

	# --- Reputation levels ----------------------------------------------------
	_expect(ds.get_reputation_level("nakai") == "wary", "nakai level == wary (rep 0)")
	_expect(ds.get_reputation_level("ursini") == "wary", "ursini level == wary (rep 10)")
	_expect(ds.get_reputation_level("drifters") == "hostile", "drifters level == hostile (rep -20)")

	# --- meets_reputation_level ----------------------------------------------
	_expect(ds.meets_reputation_level("nakai", "war"), "nakai meets war")
	_expect(ds.meets_reputation_level("nakai", "hostile"), "nakai meets hostile")
	_expect(ds.meets_reputation_level("nakai", "wary"), "nakai meets wary")
	_expect(not ds.meets_reputation_level("nakai", "neutral"), "nakai does NOT meet neutral")
	_expect(not ds.meets_reputation_level("nakai", "friendly"), "nakai does NOT meet friendly")
	_expect(not ds.meets_reputation_level("nakai", "allied"), "nakai does NOT meet allied")

	# --- adjust_reputation + signals -----------------------------------------
	var nakai_rep0: int = ds.get_reputation("nakai")
	ds.adjust_reputation("nakai", 15)
	_expect(ds.get_reputation("nakai") == nakai_rep0 + 15, "adjust_reputation: +15")
	_expect(_rep_changed_received, "reputation_changed signal fired")
	_expect(_sig_old_rep == nakai_rep0, "signal old_rep correct")
	_expect(_sig_new_rep == nakai_rep0 + 15, "signal new_rep correct")

	# Level change signal.
	# nakai started at 0 (wary), +15 = 15 (neutral).
	_expect(_rep_level_changed_received, "reputation_level_changed signal fired")
	_expect(_sig_old_level == "wary", "signal old_level == wary")
	_expect(_sig_new_level == "neutral", "signal new_level == neutral")

	# --- Clamping -------------------------------------------------------------
	ds.adjust_reputation("nakai", 200)  # Would go to 215, clamped to 100.
	_expect(ds.get_reputation("nakai") == 100, "reputation clamped to max (100)")
	ds.adjust_reputation("nakai", -300)  # Would go to -200, clamped to -100.
	_expect(ds.get_reputation("nakai") == -100, "reputation clamped to min (-100)")

	# --- set_reputation -------------------------------------------------------
	ds.set_reputation("nakai", 50)
	_expect(ds.get_reputation("nakai") == 50, "set_reputation: 50")
	ds.set_reputation("nakai", 200)
	_expect(ds.get_reputation("nakai") == 100, "set_reputation clamped to 100")
	ds.set_reputation("nakai", -200)
	_expect(ds.get_reputation("nakai") == -100, "set_reputation clamped to -100")

	# --- Unknown faction safety ----------------------------------------------
	_expect(ds.get_reputation("unknown") == 0, "unknown faction reputation returns 0")
	_expect(ds.get_reputation_level("unknown") == "war", "unknown faction level returns war")
	_expect(ds.get_faction_display_name("unknown") == "unknown", "unknown faction display name returns id")
	ds.adjust_reputation("unknown", 10)  # Should not crash.

	# --- Reset to start -------------------------------------------------------
	ds.reset()
	_expect(ds.get_reputation("nakai") == 0, "reset: nakai reputation == 0")
	_expect(ds.get_reputation("ursini") == 10, "reset: ursini reputation == 10")
	_expect(ds.get_reputation("drifters") == -20, "reset: drifters reputation == -20")
	_expect(ds.get_reputation("builders") == 0, "reset: builders reputation == 0")

	# --- Trade offers ---------------------------------------------------------
	var trade_ids: Array = ds.get_trade_offer_ids()
	_expect(trade_ids.size() == 9, "9 trade offers (got %d)" % trade_ids.size())

	var nakai_trades: Array = ds.get_trade_offers_for_faction("nakai")
	_expect(nakai_trades.size() == 2, "nakai has 2 trade offers (got %d)" % nakai_trades.size())
	_expect(nakai_trades.has("nakai_shield_for_naquadah"), "nakai shield trade exists")
	_expect(nakai_trades.has("nakai_plasma_for_trinium"), "nakai plasma trade exists")

	# can_trade: reputation too low for nakai (needs 11, currently 0).
	_expect(not ds.can_trade("nakai_shield_for_naquadah"), "can_trade: nakai rep too low")

	# Raise nakai reputation to neutral.
	ds.set_reputation("nakai", 15)
	# can_trade: still can't because no resources in inventory.
	_expect(not ds.can_trade("nakai_shield_for_naquadah"), "can_trade: no resources")

	# Add resources to inventory.
	var inv: Node = root.get_node_or_null("Inventory")
	if inv != null:
		inv.call("add_item", "naquadah", 10, "test")
		# Now should be able to trade.
		_expect(ds.can_trade("nakai_shield_for_naquadah"), "can_trade: reputation + resources OK")

		# Execute the trade.
		_trade_completed_received = false
		var trade_result: bool = ds.execute_trade("nakai_shield_for_naquadah")
		_expect(trade_result, "execute_trade: success")
		_expect(_trade_completed_received, "trade_completed signal fired")
		_expect(ds.get_tech_count("shield_tech") == 1, "shield_tech acquired (count 1)")
		_expect(int(inv.call("count", "naquadah")) == 5, "naquadah spent (5 remaining)")
		# Reputation should have increased by 5 (from 15 to 20).
		_expect(ds.get_reputation("nakai") == 20, "trade: reputation +5 to 20")

		# Trade with insufficient resources (spend remaining naquadah first).
		inv.call("remove_item", "naquadah", 5, "test")
		_trade_failed_received = false
		var trade_fail: bool = ds.execute_trade("nakai_shield_for_naquadah")
		_expect(not trade_fail, "execute_trade: fails on insufficient resources")
		_expect(_trade_failed_received, "trade_failed signal fired")

		# Trade with insufficient reputation.
		ds.set_reputation("nakai", 0)
		_trade_failed_received = false
		var trade_rep_fail: bool = ds.execute_trade("nakai_shield_for_naquadah")
		_expect(not trade_rep_fail, "execute_trade: fails on insufficient reputation")
	else:
		print("  SKIP: trade tests (Inventory not available)")

	# --- Negotiations ---------------------------------------------------------
	var neg_ids: Array = ds.get_negotiation_ids()
	_expect(neg_ids.size() == 4, "4 negotiations (got %d)" % neg_ids.size())

	# nakai_first_contact: min_reputation -19, nakai currently 0 → available.
	_expect(ds.negotiation_available("nakai_first_contact"), "nakai_first_contact available")

	# Approaches.
	var approaches: Array = ds.get_negotiation_approaches("nakai_first_contact")
	_expect(approaches.size() == 3, "nakai_first_contact has 3 approaches")
	_expect(approaches.has("direct"), "direct approach exists")
	_expect(approaches.has("diplomatic"), "diplomatic approach exists")
	_expect(approaches.has("aggressive"), "aggressive approach exists")

	# Attempt negotiation with deterministic seed.
	# direct: success_chance 0.8, seed should produce roll < 0.8 → success.
	ds.set_reputation("nakai", 0)
	_negotiation_completed_received = false
	var neg_result: Dictionary = ds.attempt_negotiation("nakai_first_contact", "direct", 42)
	_expect(neg_result.has("success"), "negotiation result has 'success'")
	_expect(neg_result.has("result"), "negotiation result has 'result'")
	_expect(neg_result.has("description"), "negotiation result has 'description'")
	_expect(neg_result["approach"] == "direct", "negotiation result approach == direct")
	_expect(_negotiation_completed_received, "negotiation_completed signal fired")
	# Reputation should have changed by +10 (direct approach).
	_expect(ds.get_reputation("nakai") == 10, "negotiation direct: reputation +10 to 10")

	# Aggressive approach: reputation -15.
	ds.set_reputation("nakai", 0)
	var agg_result: Dictionary = ds.attempt_negotiation("nakai_first_contact", "aggressive", 42)
	_expect(agg_result["approach"] == "aggressive", "aggressive approach recorded")
	_expect(ds.get_reputation("nakai") == -15, "negotiation aggressive: reputation -15 to -15")

	# Unknown negotiation.
	var unk_result: Dictionary = ds.attempt_negotiation("nonexistent", "direct", 42)
	_expect(not unk_result["success"], "unknown negotiation fails")
	_expect(unk_result["result"] == "unknown_negotiation", "unknown negotiation result")

	# Unknown approach.
	var unk_approach: Dictionary = ds.attempt_negotiation("nakai_first_contact", "nonexistent", 42)
	_expect(not unk_approach["success"], "unknown approach fails")
	_expect(unk_approach["result"] == "unknown_approach", "unknown approach result")

	# Locked negotiation (reputation too low).
	ds.set_reputation("nakai", -50)
	var locked_result: Dictionary = ds.attempt_negotiation("nakai_first_contact", "direct", 42)
	_expect(not locked_result["success"], "locked negotiation fails")
	_expect(locked_result["result"] == "locked", "locked negotiation result")

	# --- Language puzzles -----------------------------------------------------
	ds.reset()

	# Nakai language: nakai_glyphs, 4 fragments, threshold 3.
	var lang_fragments: Array = ds.get_language_fragments("nakai")
	_expect(lang_fragments.size() == 4, "nakai has 4 language fragments")

	_expect(ds.get_language_progress("nakai") == 0.0, "nakai language progress 0%")
	_expect(not ds.is_language_complete("nakai"), "nakai language not complete")
	_expect(ds.get_decoded_fragment_count("nakai") == 0, "nakai 0 decoded fragments")

	# Decode first fragment.
	_language_fragment_decoded_received = false
	var dec1: bool = ds.decode_fragment("nakai", "nakai_01")
	_expect(dec1, "decode nakai_01 success")
	_expect(_language_fragment_decoded_received, "language_fragment_decoded signal fired")
	_expect(ds.get_decoded_fragment_count("nakai") == 1, "nakai 1 decoded fragment")
	_expect(ds.get_language_progress("nakai") == 0.25, "nakai language progress 25%")

	# Decode duplicate fragment (should return false).
	var dec_dup: bool = ds.decode_fragment("nakai", "nakai_01")
	_expect(not dec_dup, "decode duplicate fragment returns false")
	_expect(ds.get_decoded_fragment_count("nakai") == 1, "nakai still 1 decoded (no dup)")

	# Decode nonexistent fragment.
	var dec_bad: bool = ds.decode_fragment("nakai", "nonexistent_fragment")
	_expect(not dec_bad, "decode nonexistent fragment returns false")

	# Decode second and third fragments to complete puzzle.
	ds.decode_fragment("nakai", "nakai_02")
	_expect(ds.get_decoded_fragment_count("nakai") == 2, "nakai 2 decoded fragments")
	_expect(not ds.is_language_complete("nakai"), "nakai language not complete (2/3)")

	_language_puzzle_completed_received = false
	var nakai_rep_before: int = ds.get_reputation("nakai")
	ds.decode_fragment("nakai", "nakai_03")
	_expect(ds.get_decoded_fragment_count("nakai") == 3, "nakai 3 decoded fragments")
	_expect(ds.is_language_complete("nakai"), "nakai language complete (3/3)")
	_expect(_language_puzzle_completed_received, "language_puzzle_completed signal fired")
	# Reputation should have increased by 15 (puzzle reward).
	_expect(ds.get_reputation("nakai") == nakai_rep_before + 15, "language puzzle: reputation +15")

	# Decode 4th fragment (beyond threshold, still allowed).
	var dec4: bool = ds.decode_fragment("nakai", "nakai_04")
	_expect(dec4, "decode nakai_04 success")
	_expect(ds.get_decoded_fragment_count("nakai") == 4, "nakai 4 decoded fragments")
	_expect(ds.get_language_progress("nakai") == 1.0, "nakai language progress 100%")

	# Unknown faction language.
	_expect(ds.get_faction_language("unknown") == "", "unknown faction language empty")
	_expect(ds.get_language_progress("unknown") == 0.0, "unknown faction progress 0%")
	_expect(not ds.is_language_complete("unknown"), "unknown faction not complete")

	# --- Alliances ------------------------------------------------------------
	ds.reset()

	# Initially no alliances active.
	_expect(ds.get_active_alliances().is_empty(), "no active alliances at start")

	# nakai_alliance: requires rep 71 + nakai_glyphs language complete.
	_expect(not ds.can_form_alliance("nakai_alliance"), "nakai_alliance: cannot form (low rep)")

	# Raise reputation to 71+.
	ds.set_reputation("nakai", 75)
	_expect(not ds.can_form_alliance("nakai_alliance"), "nakai_alliance: cannot form (no language)")

	# Complete language puzzle.
	ds.decode_fragment("nakai", "nakai_01")
	ds.decode_fragment("nakai", "nakai_02")
	ds.decode_fragment("nakai", "nakai_03")
	_expect(ds.can_form_alliance("nakai_alliance"), "nakai_alliance: can form (rep + language)")

	# The set_reputation(75) above may have auto-formed the alliance via
	# _check_alliance_formation. Reset state to test form_alliance explicitly.
	ds.break_alliance("nakai_alliance")
	_expect(not ds.is_alliance_active("nakai_alliance"), "nakai_alliance broken before explicit form test")

	# Form the alliance.
	_alliance_formed_received = false
	var form_result: bool = ds.form_alliance("nakai_alliance")
	_expect(form_result, "form_alliance: success")
	_expect(_alliance_formed_received, "alliance_formed signal fired")
	_expect(ds.is_alliance_active("nakai_alliance"), "nakai_alliance is active")
	_expect(ds.get_active_alliances().has("nakai_alliance"), "nakai_alliance in active list")

	# Forming again should return true (idempotent).
	var form_again: bool = ds.form_alliance("nakai_alliance")
	_expect(form_again, "form_alliance: idempotent returns true")

	# Break the alliance when reputation drops.
	_alliance_broken_received = false
	ds.set_reputation("nakai", 50)  # Below 71 threshold.
	# Alliance should auto-break via _check_alliance_formation.
	_expect(_alliance_broken_received, "alliance_broken signal fired on rep drop")
	_expect(not ds.is_alliance_active("nakai_alliance"), "nakai_alliance broken after rep drop")

	# Unknown alliance.
	_expect(not ds.can_form_alliance("nonexistent"), "unknown alliance cannot form")
	_expect(not ds.form_alliance("nonexistent"), "unknown alliance form returns false")
	_expect(not ds.is_alliance_active("nonexistent"), "unknown alliance not active")

	# --- Grand alliance (requires 3 factions) ---------------------------------
	ds.reset()
	# Set all 3 factions to allied reputation.
	ds.set_reputation("nakai", 75)
	ds.set_reputation("ursini", 75)
	ds.set_reputation("builders", 75)
	# grand_alliance has no required_language.
	_expect(ds.can_form_alliance("grand_alliance"), "grand_alliance: can form (3 factions at 75)")
	# Break any auto-formed alliances first to test explicit formation.
	ds.break_alliance("grand_alliance")
	_alliance_formed_received = false
	ds.form_alliance("grand_alliance")
	_expect(_alliance_formed_received, "grand_alliance formed")
	_expect(ds.is_alliance_active("grand_alliance"), "grand_alliance is active")

	# --- Combat fallback ------------------------------------------------------
	ds.reset()

	# Not combat-only at start.
	_expect(not ds.is_combat_only("nakai"), "nakai not combat-only at start")

	# Drop to war level.
	_combat_triggered_received = false
	ds.set_reputation("nakai", -60)
	_expect(ds.get_reputation_level("nakai") == "war", "nakai at war level")
	_expect(ds.is_combat_only("nakai"), "nakai combat-only at war")
	_expect(_combat_triggered_received, "combat_triggered signal fired")

	# Combat data.
	var cd: Dictionary = ds.get_combat_data("nakai")
	_expect(not cd.is_empty(), "nakai combat data exists")
	_expect(cd.get("enemy_type") == "nakai_warrior", "nakai combat enemy type")
	_expect(cd.has("reward_on_victory"), "combat data has reward_on_victory")
	_expect(cd.has("penalty_on_defeat"), "combat data has penalty_on_defeat")

	# Resolve combat: victory.
	_combat_resolved_received = false
	var nakai_rep_pre: int = ds.get_reputation("nakai")
	var combat_result: Dictionary = ds.resolve_combat("nakai", true)
	_expect(_combat_resolved_received, "combat_resolved signal fired")
	_expect(combat_result.has("reputation"), "combat result has reputation")
	# Victory reward: reputation +10.
	_expect(ds.get_reputation("nakai") == nakai_rep_pre + 10, "combat victory: reputation +10")

	# Resolve combat: defeat.
	var nakai_rep_pre2: int = ds.get_reputation("nakai")
	var defeat_result: Dictionary = ds.resolve_combat("nakai", false)
	_expect(defeat_result.has("reputation"), "defeat result has reputation")
	# Defeat penalty: reputation -20.
	_expect(ds.get_reputation("nakai") == nakai_rep_pre2 - 20, "combat defeat: reputation -20")

	# Combat enemy type.
	_expect(ds.get_combat_enemy_type("nakai") == "nakai_warrior", "nakai combat enemy type")
	_expect(ds.get_combat_enemy_type("unknown") == "", "unknown faction combat enemy type empty")

	# --- Diplomacy actions ----------------------------------------------------
	ds.reset()
	var action_ids: Array = ds.diplomacy_action_ids()
	_expect(action_ids.size() == 16, "16 diplomacy actions (got %d)" % action_ids.size())
	_expect(ds.has_diplomacy_action("diplo_nakai_respect_show"), "diplo_nakai_respect_show exists")
	_expect(not ds.has_diplomacy_action("nonexistent"), "nonexistent action not found")

	# Apply action: diplo_nakai_respect_show → nakai +10.
	var nakai_rep_a0: int = ds.get_reputation("nakai")
	ds.apply_diplomacy_action("diplo_nakai_respect_show")
	_expect(ds.get_reputation("nakai") == nakai_rep_a0 + 10, "diplo action: nakai +10")

	# Apply action: diplo_nakai_insult → nakai -20.
	var nakai_rep_a1: int = ds.get_reputation("nakai")
	ds.apply_diplomacy_action("diplo_nakai_insult")
	_expect(ds.get_reputation("nakai") == nakai_rep_a1 - 20, "diplo action: nakai -20")

	# Apply nonexistent action (should not crash).
	ds.apply_diplomacy_action("nonexistent_action")

	# --- get_faction_summaries -----------------------------------------------
	var summaries: Dictionary = ds.get_faction_summaries()
	_expect(summaries.size() == 4, "faction summaries has 4 entries")
	for fid in summaries.keys():
		var fd: Dictionary = summaries[fid]
		_expect(fd.has("display_name"), "summary has display_name")
		_expect(fd.has("description"), "summary has description")
		_expect(fd.has("reputation"), "summary has reputation")
		_expect(fd.has("level"), "summary has level")
		_expect(fd.has("home_world"), "summary has home_world")
		_expect(fd.has("personality"), "summary has personality")
		_expect(fd.has("language_id"), "summary has language_id")
		_expect(fd.has("tech_offers"), "summary has tech_offers")
		_expect(fd.has("resource_needs"), "summary has resource_needs")
		_expect(fd.has("decoded_fragments"), "summary has decoded_fragments")
		_expect(fd.has("language_progress"), "summary has language_progress")

	# --- Save / Load round-trip -----------------------------------------------
	ds.reset()
	# Set up some state.
	ds.set_reputation("nakai", 50)
	ds.set_reputation("ursini", 30)
	ds.decode_fragment("nakai", "nakai_01")
	ds.decode_fragment("nakai", "nakai_02")
	ds.decode_fragment("nakai", "nakai_03")
	ds.set_reputation("nakai", 75)  # + language complete → alliance auto-forms
	# Execute a trade to get some tech.
	if inv != null:
		inv.call("add_item", "naquadah", 10, "test")
		ds.execute_trade("nakai_shield_for_naquadah")

	var saved: Dictionary = ds.serialize()
	_expect(saved.has("reputation"), "serialize has reputation")
	_expect(saved.has("decoded_fragments"), "serialize has decoded_fragments")
	_expect(saved.has("active_alliances"), "serialize has active_alliances")
	_expect(saved.has("acquired_tech"), "serialize has acquired_tech")

	# Deserialize into a fresh state.
	ds.reset()
	ds.deserialize(saved, 1)
	# The reputation after: set(50) → decode 3 (+15=65) → set(75) → trade(+5=80).
	var saved_nakai_rep: int = int((saved["reputation"] as Dictionary).get("nakai", 0))
	_expect(ds.get_reputation("nakai") == saved_nakai_rep, "deserialize: nakai reputation matches serialized value (%d)" % saved_nakai_rep)

	_expect(ds.get_reputation("ursini") == 30, "deserialize: ursini reputation == 30")
	_expect(ds.get_decoded_fragment_count("nakai") == 3, "deserialize: nakai 3 decoded fragments")
	_expect(ds.is_language_complete("nakai"), "deserialize: nakai language still complete")
	_expect(ds.is_alliance_active("nakai_alliance"), "deserialize: nakai_alliance still active")
	if inv != null:
		_expect(ds.get_tech_count("shield_tech") == 1, "deserialize: shield_tech still acquired")

	# --- Reset final ----------------------------------------------------------
	ds.reset()
	_expect(ds.get_reputation("nakai") == 0, "final reset: nakai reputation == 0")
	_expect(ds.get_reputation("ursini") == 10, "final reset: ursini reputation == 10")
	_expect(ds.get_reputation("drifters") == -20, "final reset: drifters reputation == -20")
	_expect(ds.get_reputation("builders") == 0, "final reset: builders reputation == 0")
	_expect(ds.get_decoded_fragment_count("nakai") == 0, "final reset: nakai 0 decoded fragments")
	_expect(not ds.is_language_complete("nakai"), "final reset: nakai language not complete")
	_expect(ds.get_active_alliances().is_empty(), "final reset: no active alliances")
	_expect(ds.get_tech_count("shield_tech") == 0, "final reset: no acquired tech")

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
	print("=== diplomacy_system smoke test complete ===")