extends Node

# DiplomacySystem — multi-faction diplomacy for Episode 18 "Alliances".
#
# Tracks reputation with alien factions (Nakai, Ursini, Drifters, Builders).
# Supports:
#   - Faction reputation with 6 levels (war → hostile → wary → neutral → friendly → allied).
#   - Trade offers: exchange resources for alien tech.
#   - Negotiations: multi-approach dialogue with success/failure outcomes.
#   - Alien language puzzles: decode glyphs to unlock deeper diplomacy.
#   - Alliance formation: requires high reputation + language comprehension.
#   - Combat fallback: when diplomacy fails and reputation hits "war".
#
# Integration:
#   - GameState.dialog_action signal → apply_diplomacy_action() for data-driven
#     reputation changes from dialog trees (same pattern as RelationshipSystem).
#   - Inventory → check/spend resources for trade offers.
#   - SaveManager → serialize()/deserialize() for save/load round-trip.
#   - QuestLog → can gate quest steps behind alliance or reputation requirements.
#
# Data: res://data/diplomacy.json

signal reputation_changed(faction_id: String, old_value: int, new_value: int)
signal reputation_level_changed(faction_id: String, old_level: String, new_level: String)
signal trade_completed(offer_id: String, faction_id: String)
signal trade_failed(offer_id: String, reason: String)
signal negotiation_completed(negotiation_id: String, approach: String, success: bool)
signal language_fragment_decoded(faction_id: String, fragment_id: String)
signal language_puzzle_completed(faction_id: String, language_id: String)
signal alliance_formed(alliance_id: String)
signal alliance_broken(alliance_id: String)
signal combat_triggered(faction_id: String)
signal combat_resolved(faction_id: String, victory: bool)

const DATA_PATH: String = "res://data/diplomacy.json"

# ── Reputation levels (ordered lowest → highest) ─────────────────────────────

const LEVEL_ORDER: Array[String] = [
	"war", "hostile", "wary", "neutral", "friendly", "allied"
]

# ── Internal state ───────────────────────────────────────────────────────────

# faction_id → _Faction
var _factions: Dictionary = {}

# faction_id → int (current reputation)
var _reputation: Dictionary = {}

# trade_offer_id → Dictionary (from JSON)
var _trade_offers: Dictionary = {}

# negotiation_id → Dictionary (from JSON)
var _negotiations: Dictionary = {}

# language_id → Dictionary (from JSON)
var _language_puzzles: Dictionary = {}

# faction_id → Array[String] (decoded fragment ids)
var _decoded_fragments: Dictionary = {}

# alliance_id → Dictionary (from JSON)
var _alliances: Dictionary = {}

# alliance_id → bool (currently formed)
var _active_alliances: Dictionary = {}

# action_id → Dictionary (from JSON)
var _diplomacy_actions: Dictionary = {}

# combat fallback data: faction_id → Dictionary
var _combat_data: Dictionary = {}

# Tech acquired: tech_id → int (count)
var _acquired_tech: Dictionary = {}

var _loaded: bool = false

# ── Internal classes ─────────────────────────────────────────────────────────

class _Faction:
	var id: String
	var display_name: String
	var description: String = ""
	var reputation_start: int = 0
	var reputation_min: int = -100
	var reputation_max: int = 100
	var home_world: String = ""
	var tech_offers: Array[String] = []
	var resource_needs: Array[String] = []
	var personality: String = ""
	var language_id: String = ""

	func _init(fid: String) -> void:
		id = fid

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_register_with_save_manager()
	_connect_dialog_action()

func _load_config() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("DiplomacySystem: cannot open %s" % DATA_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("DiplomacySystem: %s did not parse to a Dictionary" % DATA_PATH)
		return
	var data: Dictionary = parsed as Dictionary

	# ── Factions ─────────────────────────────────────────────────────────────
	var factions_raw: Variant = data.get("factions", {})
	if factions_raw is Dictionary:
		for fid in (factions_raw as Dictionary).keys():
			var fd: Dictionary = (factions_raw as Dictionary)[fid]
			var fac: _Faction = _Faction.new(fid)
			fac.display_name = String(fd.get("display_name", fid))
			fac.description = String(fd.get("description", ""))
			fac.reputation_start = int(fd.get("reputation_start", 0))
			fac.reputation_min = int(fd.get("reputation_min", -100))
			fac.reputation_max = int(fd.get("reputation_max", 100))
			fac.home_world = String(fd.get("home_world", ""))
			fac.personality = String(fd.get("personality", ""))
			fac.language_id = String(fd.get("language_id", ""))
			var tech_arr: Variant = fd.get("tech_offers", [])
			if tech_arr is Array:
				for t in (tech_arr as Array):
					fac.tech_offers.append(String(t))
			var res_arr: Variant = fd.get("resource_needs", [])
			if res_arr is Array:
				for r in (res_arr as Array):
					fac.resource_needs.append(String(r))
			_factions[fid] = fac
			_reputation[fid] = fac.reputation_start
			_decoded_fragments[fid] = []

	# ── Trade offers ─────────────────────────────────────────────────────────
	var trades_raw: Variant = data.get("trade_offers", {})
	if trades_raw is Dictionary:
		_trade_offers = (trades_raw as Dictionary).duplicate()

	# ── Negotiations ─────────────────────────────────────────────────────────
	var neg_raw: Variant = data.get("negotiations", {})
	if neg_raw is Dictionary:
		_negotiations = (neg_raw as Dictionary).duplicate()

	# ── Language puzzles ─────────────────────────────────────────────────────
	var lang_raw: Variant = data.get("language_puzzles", {})
	if lang_raw is Dictionary:
		_language_puzzles = (lang_raw as Dictionary).duplicate()

	# ── Alliances ────────────────────────────────────────────────────────────
	var ally_raw: Variant = data.get("alliances", {})
	if ally_raw is Dictionary:
		_alliances = (ally_raw as Dictionary).duplicate()
		for aid in _alliances.keys():
			_active_alliances[aid] = false

	# ── Diplomacy actions ────────────────────────────────────────────────────
	var act_raw: Variant = data.get("diplomacy_actions", {})
	if act_raw is Dictionary:
		_diplomacy_actions = (act_raw as Dictionary).duplicate()

	# ── Combat fallback ──────────────────────────────────────────────────────
	var combat_raw: Variant = data.get("combat_fallback", {})
	if combat_raw is Dictionary:
		var cf: Dictionary = (combat_raw as Dictionary)
		for key in cf.keys():
			if key == "_comment":
				continue
			_combat_data[key] = cf[key]

func _register_with_save_manager() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "diplomacy_system", self)

func _connect_dialog_action() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("dialog_action"):
		if not gs.dialog_action.is_connected(_on_dialog_action):
			gs.dialog_action.connect(_on_dialog_action)

# ── Public API: reputation ───────────────────────────────────────────────────

## Returns the current reputation with a faction (0 if unknown).
func get_reputation(faction_id: String) -> int:
	return int(_reputation.get(faction_id, 0))

## Returns the reputation level string for a faction.
func get_reputation_level(faction_id: String) -> String:
	if not _factions.has(faction_id):
		return "war"
	var rep: int = get_reputation(faction_id)
	return _rep_to_level(rep)

## Adjusts reputation by a delta, clamped to [min, max]. Emits signals.
func adjust_reputation(faction_id: String, delta: int) -> int:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		push_warning("DiplomacySystem: unknown faction '%s'" % faction_id)
		return 0
	var old_val: int = int(_reputation.get(faction_id, fac.reputation_start))
	var old_level: String = _rep_to_level(old_val)
	var new_val: int = clampi(old_val + delta, fac.reputation_min, fac.reputation_max)
	_reputation[faction_id] = new_val
	if new_val != old_val:
		reputation_changed.emit(faction_id, old_val, new_val)
	var new_level: String = _rep_to_level(new_val)
	if new_level != old_level:
		reputation_level_changed.emit(faction_id, old_level, new_level)
	# Check if dropping to war triggers combat fallback.
	if new_level == "war" and old_level != "war":
		combat_triggered.emit(faction_id)
	# Check alliance formation/breaking on any reputation change.
	_check_alliance_formation(faction_id)
	return new_val

## Sets reputation directly (clamped). Emits signals.
func set_reputation(faction_id: String, value: int) -> int:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		return 0
	var old_val: int = int(_reputation.get(faction_id, fac.reputation_start))
	var old_level: String = _rep_to_level(old_val)
	var new_val: int = clampi(value, fac.reputation_min, fac.reputation_max)
	_reputation[faction_id] = new_val
	if new_val != old_val:
		reputation_changed.emit(faction_id, old_val, new_val)
	var new_level: String = _rep_to_level(new_val)
	if new_level != old_level:
		reputation_level_changed.emit(faction_id, old_level, new_level)
	if new_level == "war" and old_level != "war":
		combat_triggered.emit(faction_id)
	# Check alliance formation/breaking on any reputation change.
	_check_alliance_formation(faction_id)
	return new_val

## Returns true if the faction's reputation meets or exceeds the given level.
func meets_reputation_level(faction_id: String, level: String) -> bool:
	var current: String = get_reputation_level(faction_id)
	return _level_index(current) >= _level_index(level)

## Returns the display name for a faction.
func get_faction_display_name(faction_id: String) -> String:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		return faction_id
	return fac.display_name

## Returns the description for a faction.
func get_faction_description(faction_id: String) -> String:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		return ""
	return fac.description

## Returns the personality trait for a faction.
func get_faction_personality(faction_id: String) -> String:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		return ""
	return fac.personality

## Returns the home world name for a faction.
func get_faction_home_world(faction_id: String) -> String:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		return ""
	return fac.home_world

## Returns an Array of all faction ids.
func get_all_faction_ids() -> Array:
	return _factions.keys()

## Returns a Dictionary of faction_id → summary data for HUD / diplomacy screen.
func get_faction_summaries() -> Dictionary:
	var result: Dictionary = {}
	for fid in _factions.keys():
		var fac: _Faction = _factions[fid] as _Faction
		var rep: int = int(_reputation.get(fid, fac.reputation_start))
		result[fid] = {
			"display_name": fac.display_name,
			"description": fac.description,
			"reputation": rep,
			"level": _rep_to_level(rep),
			"home_world": fac.home_world,
			"personality": fac.personality,
			"language_id": fac.language_id,
			"tech_offers": fac.tech_offers.duplicate(),
			"resource_needs": fac.resource_needs.duplicate(),
			"decoded_fragments": (_decoded_fragments.get(fid, []) as Array).duplicate(),
			"language_progress": get_language_progress(fid),
		}
	return result

# ── Public API: trade offers ─────────────────────────────────────────────────

## Returns all trade offer ids.
func get_trade_offer_ids() -> Array:
	return _trade_offers.keys()

## Returns the trade offer data for a given id, or {} if not found.
func get_trade_offer(offer_id: String) -> Dictionary:
	var offer: Variant = _trade_offers.get(offer_id, null)
	if offer == null or not (offer is Dictionary):
		return {}
	return (offer as Dictionary).duplicate()

## Returns an Array of trade offer ids available for a faction.
func get_trade_offers_for_faction(faction_id: String) -> Array:
	var result: Array = []
	for oid in _trade_offers.keys():
		var offer: Dictionary = _trade_offers[oid] as Dictionary
		if String(offer.get("faction", "")) == faction_id:
			result.append(oid)
	return result

## Returns true if the player can execute a trade (reputation + resources).
func can_trade(offer_id: String) -> bool:
	var offer: Dictionary = get_trade_offer(offer_id)
	if offer.is_empty():
		return false
	var faction_id: String = String(offer.get("faction", ""))
	var min_rep: int = int(offer.get("min_reputation", 0))
	if get_reputation(faction_id) < min_rep:
		return false
	var give: Variant = offer.get("give", {})
	if not (give is Dictionary):
		return false
	var give_d: Dictionary = give as Dictionary
	var resource: String = String(give_d.get("resource", ""))
	var amount: int = int(give_d.get("amount", 0))
	return _has_resource(resource, amount)

## Executes a trade offer. Spends resources, grants tech, adjusts reputation.
## Returns true on success, false on failure (emits trade_failed signal).
func execute_trade(offer_id: String) -> bool:
	var offer: Dictionary = get_trade_offer(offer_id)
	if offer.is_empty():
		trade_failed.emit(offer_id, "unknown_offer")
		return false
	var faction_id: String = String(offer.get("faction", ""))
	var min_rep: int = int(offer.get("min_reputation", 0))
	if get_reputation(faction_id) < min_rep:
		trade_failed.emit(offer_id, "insufficient_reputation")
		return false
	var give: Variant = offer.get("give", {})
	if not (give is Dictionary):
		trade_failed.emit(offer_id, "invalid_give")
		return false
	var give_d: Dictionary = give as Dictionary
	var resource: String = String(give_d.get("resource", ""))
	var amount: int = int(give_d.get("amount", 0))
	if not _spend_resource(resource, amount):
		trade_failed.emit(offer_id, "insufficient_resources")
		return false
	# Grant tech.
	var receive: Variant = offer.get("receive", {})
	if receive is Dictionary:
		var recv_d: Dictionary = receive as Dictionary
		var tech: String = String(recv_d.get("tech", ""))
		var tech_amount: int = int(recv_d.get("amount", 1))
		if tech != "":
			_acquired_tech[tech] = int(_acquired_tech.get(tech, 0)) + tech_amount
	# Adjust reputation.
	var rep_change: int = int(offer.get("reputation_change", 0))
	if rep_change != 0:
		adjust_reputation(faction_id, rep_change)
	trade_completed.emit(offer_id, faction_id)
	return true

## Returns the count of a acquired tech.
func get_tech_count(tech_id: String) -> int:
	return int(_acquired_tech.get(tech_id, 0))

## Returns true if the player has acquired at least `amount` of a tech.
func has_tech(tech_id: String, amount: int = 1) -> bool:
	return get_tech_count(tech_id) >= amount

## Returns a Dictionary of all acquired tech (tech_id → count).
func get_all_acquired_tech() -> Dictionary:
	return _acquired_tech.duplicate()

# ── Public API: negotiations ──────────────────────────────────────────────────

## Returns all negotiation ids.
func get_negotiation_ids() -> Array:
	return _negotiations.keys()

## Returns the negotiation data for a given id, or {} if not found.
func get_negotiation(negotiation_id: String) -> Dictionary:
	var neg: Variant = _negotiations.get(negotiation_id, null)
	if neg == null or not (neg is Dictionary):
		return {}
	return (neg as Dictionary).duplicate()

## Returns an Array of approach ids for a negotiation.
func get_negotiation_approaches(negotiation_id: String) -> Array:
	var neg: Dictionary = get_negotiation(negotiation_id)
	if neg.is_empty():
		return []
	var approaches: Variant = neg.get("approaches", {})
	if not (approaches is Dictionary):
		return []
	return (approaches as Dictionary).keys()

## Returns true if the negotiation is available (reputation meets minimum).
func negotiation_available(negotiation_id: String) -> bool:
	var neg: Dictionary = get_negotiation(negotiation_id)
	if neg.is_empty():
		return false
	var faction_id: String = String(neg.get("faction", ""))
	var min_rep: int = int(neg.get("min_reputation", 0))
	return get_reputation(faction_id) >= min_rep

## Attempts a negotiation approach. Returns a Dictionary with:
##   { "success": bool, "result": String, "description": String,
##     "reputation_change": int, "approach": String }
## Uses deterministic RNG seeded by faction + negotiation + approach for
## reproducibility in tests; in-game uses random.
func attempt_negotiation(negotiation_id: String, approach: String, deterministic_seed: int = -1) -> Dictionary:
	var neg: Dictionary = get_negotiation(negotiation_id)
	if neg.is_empty():
		return {"success": false, "result": "unknown_negotiation", "description": "", "reputation_change": 0, "approach": approach}
	var approaches: Variant = neg.get("approaches", {})
	if not (approaches is Dictionary):
		return {"success": false, "result": "no_approaches", "description": "", "reputation_change": 0, "approach": approach}
	var ap: Variant = (approaches as Dictionary).get(approach, null)
	if ap == null or not (ap is Dictionary):
		return {"success": false, "result": "unknown_approach", "description": "", "reputation_change": 0, "approach": approach}
	var ap_d: Dictionary = ap as Dictionary
	var faction_id: String = String(neg.get("faction", ""))
	var min_rep: int = int(neg.get("min_reputation", 0))
	if get_reputation(faction_id) < min_rep:
		return {"success": false, "result": "locked", "description": "Reputation too low.", "reputation_change": 0, "approach": approach}
	var success_chance: float = float(ap_d.get("success_chance", 0.5))
	# Determine success.
	var roll: float
	if deterministic_seed >= 0:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = deterministic_seed
		roll = rng.randf()
	else:
		roll = randf()
	var success: bool = roll < success_chance
	var result_str: String = String(ap_d.get("result", "unknown"))
	var description: String = String(ap_d.get("description", ""))
	var rep_change: int = int(ap_d.get("reputation_change", 0))
	# Apply reputation change.
	if rep_change != 0:
		adjust_reputation(faction_id, rep_change)
	negotiation_completed.emit(negotiation_id, approach, success)
	return {
		"success": success,
		"result": result_str,
		"description": description,
		"reputation_change": rep_change,
		"approach": approach,
	}

# ── Public API: language puzzles ─────────────────────────────────────────────

## Returns the language puzzle data for a language_id, or {} if not found.
func get_language_puzzle(language_id: String) -> Dictionary:
	var lp: Variant = _language_puzzles.get(language_id, null)
	if lp == null or not (lp is Dictionary):
		return {}
	return (lp as Dictionary).duplicate()

## Returns the language_id for a faction, or "" if not found.
func get_faction_language(faction_id: String) -> String:
	var fac: _Faction = _factions.get(faction_id, null) as _Faction
	if fac == null:
		return ""
	return fac.language_id

## Returns an Array of decoded fragment ids for a faction.
func get_decoded_fragments(faction_id: String) -> Array:
	return (_decoded_fragments.get(faction_id, []) as Array).duplicate()

## Decodes a language fragment. Returns true if newly decoded, false if already
## decoded or fragment not found. Awards reputation on puzzle completion.
func decode_fragment(faction_id: String, fragment_id: String) -> bool:
	var language_id: String = get_faction_language(faction_id)
	if language_id == "":
		return false
	var puzzle: Dictionary = get_language_puzzle(language_id)
	if puzzle.is_empty():
		return false
	var fragments: Variant = puzzle.get("fragments", [])
	if not (fragments is Array):
		return false
	# Verify the fragment exists in the puzzle.
	var found: bool = false
	for frag in (fragments as Array):
		if frag is Dictionary and String((frag as Dictionary).get("id", "")) == fragment_id:
			found = true
			break
	if not found:
		return false
	var decoded: Array = _decoded_fragments.get(faction_id, []) as Array
	if decoded.has(fragment_id):
		return false
	decoded.append(fragment_id)
	_decoded_fragments[faction_id] = decoded
	language_fragment_decoded.emit(faction_id, fragment_id)
	# Check completion.
	var threshold: int = int(puzzle.get("completion_threshold", 3))
	if decoded.size() >= threshold:
		var reward: int = int(puzzle.get("reputation_reward", 0))
		if reward > 0:
			adjust_reputation(faction_id, reward)
		language_puzzle_completed.emit(faction_id, language_id)
	return true

## Returns the number of decoded fragments for a faction.
func get_decoded_fragment_count(faction_id: String) -> int:
	return (_decoded_fragments.get(faction_id, []) as Array).size()

## Returns a float 0..1 representing language comprehension progress.
func get_language_progress(faction_id: String) -> float:
	var language_id: String = get_faction_language(faction_id)
	if language_id == "":
		return 0.0
	var puzzle: Dictionary = get_language_puzzle(language_id)
	if puzzle.is_empty():
		return 0.0
	var fragments: Variant = puzzle.get("fragments", [])
	if not (fragments is Array) or (fragments as Array).is_empty():
		return 0.0
	var total: int = (fragments as Array).size()
	var decoded: int = get_decoded_fragment_count(faction_id)
	return float(decoded) / float(total)

## Returns true if the language puzzle for a faction is complete.
func is_language_complete(faction_id: String) -> bool:
	var language_id: String = get_faction_language(faction_id)
	if language_id == "":
		return false
	var puzzle: Dictionary = get_language_puzzle(language_id)
	if puzzle.is_empty():
		return false
	var threshold: int = int(puzzle.get("completion_threshold", 3))
	return get_decoded_fragment_count(faction_id) >= threshold

## Returns the total number of fragments in a language puzzle.
func get_language_fragment_count(faction_id: String) -> int:
	var language_id: String = get_faction_language(faction_id)
	if language_id == "":
		return 0
	var puzzle: Dictionary = get_language_puzzle(language_id)
	if puzzle.is_empty():
		return 0
	var fragments: Variant = puzzle.get("fragments", [])
	if not (fragments is Array):
		return 0
	return (fragments as Array).size()

## Returns an Array of all fragment data for a faction's language.
func get_language_fragments(faction_id: String) -> Array:
	var language_id: String = get_faction_language(faction_id)
	if language_id == "":
		return []
	var puzzle: Dictionary = get_language_puzzle(language_id)
	if puzzle.is_empty():
		return []
	var fragments: Variant = puzzle.get("fragments", [])
	if not (fragments is Array):
		return []
	return (fragments as Array).duplicate()

# ── Public API: alliances ────────────────────────────────────────────────────

## Returns all alliance ids.
func get_alliance_ids() -> Array:
	return _alliances.keys()

## Returns the alliance data for a given id, or {} if not found.
func get_alliance(alliance_id: String) -> Dictionary:
	var al: Variant = _alliances.get(alliance_id, null)
	if al == null or not (al is Dictionary):
		return {}
	return (al as Dictionary).duplicate()

## Returns true if an alliance is currently formed.
func is_alliance_active(alliance_id: String) -> bool:
	return bool(_active_alliances.get(alliance_id, false))

## Returns true if an alliance can be formed (reputation + language requirements met).
func can_form_alliance(alliance_id: String) -> bool:
	var al: Dictionary = get_alliance(alliance_id)
	if al.is_empty():
		return false
	var factions: Variant = al.get("factions", [])
	if not (factions is Array):
		return false
	var required_rep: int = int(al.get("required_reputation", 71))
	for fid in (factions as Array):
		if get_reputation(String(fid)) < required_rep:
			return false
	# Check language requirement (if any).
	var req_lang: String = String(al.get("required_language", ""))
	if not req_lang.is_empty():
		# Find the faction that owns this language.
		for fid in (factions as Array):
			var fac: _Faction = _factions.get(String(fid), null) as _Faction
			if fac != null and fac.language_id == req_lang:
				if not is_language_complete(String(fid)):
					return false
	return true

## Forms an alliance if requirements are met. Returns true on success.
func form_alliance(alliance_id: String) -> bool:
	if is_alliance_active(alliance_id):
		return true  # Already formed.
	if not can_form_alliance(alliance_id):
		return false
	_active_alliances[alliance_id] = true
	alliance_formed.emit(alliance_id)
	return true

## Breaks an alliance (e.g., reputation dropped below threshold).
func break_alliance(alliance_id: String) -> void:
	if not is_alliance_active(alliance_id):
		return
	_active_alliances[alliance_id] = false
	alliance_broken.emit(alliance_id)

## Returns an Array of currently active alliance ids.
func get_active_alliances() -> Array:
	var result: Array = []
	for aid in _active_alliances.keys():
		if bool(_active_alliances[aid]):
			result.append(aid)
	return result

## Checks all alliances for formation/breaking based on current reputation.
## Called automatically after reputation changes.
func _check_alliance_formation(faction_id: String) -> void:
	for aid in _alliances.keys():
		var al: Dictionary = _alliances[aid] as Dictionary
		var factions: Variant = al.get("factions", [])
		if not (factions is Array):
			continue
		if not (factions as Array).has(faction_id):
			continue
		if is_alliance_active(aid):
			# Check if it should break.
			var required_rep: int = int(al.get("required_reputation", 71))
			if get_reputation(faction_id) < required_rep:
				break_alliance(aid)
		else:
			# Check if it can form.
			if can_form_alliance(aid):
				form_alliance(aid)

# ── Public API: combat fallback ──────────────────────────────────────────────

## Returns true if combat is the only option for a faction (reputation at war).
func is_combat_only(faction_id: String) -> bool:
	return get_reputation_level(faction_id) == "war"

## Returns the combat fallback data for a faction, or {} if not found.
func get_combat_data(faction_id: String) -> Dictionary:
	var cd: Variant = _combat_data.get(faction_id, null)
	if cd == null or not (cd is Dictionary):
		return {}
	return (cd as Dictionary).duplicate()

## Resolves a combat encounter with a faction. Adjusts reputation based on
## victory or defeat. Returns the reward/penalty data.
func resolve_combat(faction_id: String, victory: bool) -> Dictionary:
	var cd: Dictionary = get_combat_data(faction_id)
	if cd.is_empty():
		return {}
	var reward_key: String = "reward_on_victory" if victory else "penalty_on_defeat"
	var reward: Variant = cd.get(reward_key, {})
	var result: Dictionary = {}
	if reward is Dictionary:
		result = (reward as Dictionary).duplicate()
		var rep_change: int = int(result.get("reputation", 0))
		if rep_change != 0:
			adjust_reputation(faction_id, rep_change)
	combat_resolved.emit(faction_id, victory)
	return result

## Returns the enemy type for combat with a faction.
func get_combat_enemy_type(faction_id: String) -> String:
	var cd: Dictionary = get_combat_data(faction_id)
	return String(cd.get("enemy_type", ""))

# ── Public API: diplomacy actions ────────────────────────────────────────────

## Apply a diplomacy action by its action_id. Looks up the action in
## _diplomacy_actions and applies reputation deltas to the specified factions.
## This is the primary integration point for data-driven diplomacy changes from
## dialog trees.
func apply_diplomacy_action(action_id: String) -> void:
	var action: Variant = _diplomacy_actions.get(action_id, null)
	if action == null:
		return
	if not (action is Dictionary):
		return
	var ad: Dictionary = action as Dictionary
	for key in ad.keys():
		if key == "_comment":
			continue
		var deltas: Variant = ad[key]
		if not (deltas is Dictionary):
			continue
		var dd: Dictionary = deltas as Dictionary
		var rep_delta: int = int(dd.get("reputation", 0))
		if rep_delta != 0:
			adjust_reputation(String(key), rep_delta)

## Returns true if the given action_id is a known diplomacy action.
func has_diplomacy_action(action_id: String) -> bool:
	return _diplomacy_actions.has(action_id)

## Returns the list of all diplomacy action ids.
func diplomacy_action_ids() -> Array:
	return _diplomacy_actions.keys()

# ── Signal handler ────────────────────────────────────────────────────────────

func _on_dialog_action(action_id: String) -> void:
	apply_diplomacy_action(action_id)

# ── Internal helpers ──────────────────────────────────────────────────────────

## Maps a reputation value to a level string.
func _rep_to_level(rep: int) -> String:
	# Level boundaries are defined in the JSON, but we hardcode the ranges
	# here for speed since they're fixed.
	if rep <= -50:
		return "war"
	elif rep <= -20:
		return "hostile"
	elif rep <= 10:
		return "wary"
	elif rep <= 40:
		return "neutral"
	elif rep <= 70:
		return "friendly"
	else:
		return "allied"

## Returns the index of a level in LEVEL_ORDER (0 = lowest).
func _level_index(level: String) -> int:
	for i in range(LEVEL_ORDER.size()):
		if LEVEL_ORDER[i] == level:
			return i
	return 0

## Checks if the player has at least `amount` of a resource via Inventory.
func _has_resource(resource: String, amount: int) -> bool:
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	return int(inv.call("count", resource)) >= amount

## Spends `amount` of a resource via Inventory. Returns true on success.
func _spend_resource(resource: String, amount: int) -> bool:
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	if int(inv.call("count", resource)) < amount:
		return false
	inv.call("remove_item", resource, amount, "diplomacy_trade")
	return true

# ── Save / Load ───────────────────────────────────────────────────────────────

func serialize() -> Dictionary:
	var rep_data: Dictionary = {}
	for fid in _reputation.keys():
		rep_data[fid] = int(_reputation[fid])
	var decoded_data: Dictionary = {}
	for fid in _decoded_fragments.keys():
		decoded_data[fid] = (_decoded_fragments[fid] as Array).duplicate()
	var alliance_data: Dictionary = {}
	for aid in _active_alliances.keys():
		alliance_data[aid] = bool(_active_alliances[aid])
	return {
		"reputation": rep_data,
		"decoded_fragments": decoded_data,
		"active_alliances": alliance_data,
		"acquired_tech": _acquired_tech.duplicate(),
	}

func deserialize(data: Dictionary, _version: int) -> void:
	var rep_raw: Variant = data.get("reputation", {})
	if rep_raw is Dictionary:
		for fid in (rep_raw as Dictionary).keys():
			if _factions.has(String(fid)):
				_reputation[String(fid)] = int((rep_raw as Dictionary)[fid])
	var dec_raw: Variant = data.get("decoded_fragments", {})
	if dec_raw is Dictionary:
		for fid in (dec_raw as Dictionary).keys():
			if _factions.has(String(fid)):
				var arr: Array = []
				var raw_arr: Variant = (dec_raw as Dictionary)[fid]
				if raw_arr is Array:
					for frag_id in (raw_arr as Array):
						arr.append(String(frag_id))
				_decoded_fragments[String(fid)] = arr
	var ally_raw: Variant = data.get("active_alliances", {})
	if ally_raw is Dictionary:
		for aid in (ally_raw as Dictionary).keys():
			if _alliances.has(String(aid)):
				_active_alliances[String(aid)] = bool((ally_raw as Dictionary)[aid])
	var tech_raw: Variant = data.get("acquired_tech", {})
	if tech_raw is Dictionary:
		_acquired_tech = (tech_raw as Dictionary).duplicate()

func reset() -> void:
	# Reset reputation to starting values.
	for fid in _factions.keys():
		var fac: _Faction = _factions[fid] as _Faction
		_reputation[fid] = fac.reputation_start
		_decoded_fragments[fid] = []
	# Reset alliances.
	for aid in _active_alliances.keys():
		_active_alliances[aid] = false
	# Reset acquired tech.
	_acquired_tech.clear()