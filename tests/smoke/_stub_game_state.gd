extends Node

# Stub GameState for the misc_enhancements smoke test. Exposes only the
# properties + QUEST_* ordering constants that GateTravel queries, so the
# test can exercise the persistent-open lifecycle in isolation (without
# depending on the real GameState autoload's full init / signal graph).
#
# This file lives under tests/smoke/ so the production code never loads it.

# Quest ordering — must match the real GameState's QUEST_* constants so
# GateTravel._step_at_or_after walks the right sequence.
const QUEST_GO_TO_GATE: String = "go_to_gate"
const QUEST_SCOUT_KINO: String = "scout_kino"
const QUEST_MINE_LIME: String = "mine_lime"
const QUEST_RETURN_DESTINY: String = "return_destiny"
const QUEST_REPAIR_SCRUBBER: String = "repair_scrubber"
const QUEST_COMPLETE: String = "complete"

var lime_planet_dialed: bool = false
var returned_from_lime_planet: bool = false
var scrubber_repaired: bool = false
var pending_planet_return: bool = false
var quest_step: String = QUEST_GO_TO_GATE

# Per-destination crossing counter storage (GateTravel.crossing_count uses
# get_state/set_state when available, else direct property access).
var _state: Dictionary = {}

func reset() -> void:
	lime_planet_dialed = false
	returned_from_lime_planet = false
	scrubber_repaired = false
	pending_planet_return = false
	quest_step = QUEST_GO_TO_GATE
	_state.clear()

func get_state(key: String, default: Variant = null) -> Variant:
	return _state.get(key, default)

func set_state(key: String, value: Variant) -> void:
	_state[key] = value