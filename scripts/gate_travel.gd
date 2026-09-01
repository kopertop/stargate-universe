class_name GateTravel
extends Node

# Issue #68 — player-side free two-way gate travel, persistent-open gate
# lifecycle, and dialing interface.
#
# This is the PLAYER-side companion to PlanetGate (which owns the actual
# Area3D cross-scene trigger). PlanetGate handles the physics overlap / scene
# swap; GateTravel owns the higher-level lifecycle questions a player-facing
# dialing UI cares about:
#
#   • Is the gate open right now, and why / why not?
#   • Which destinations can the player dial?
#   • What is the persistent-open window (open from first dial until the
#     terminal world/story condition closes it — NOT one-shot per crossing)?
#   • A dialing interface: pick a destination, run the dial sequence on the
#     owning gate room, and hand off to PlanetGate for the actual crossing.
#
# Designed as a pure-data / pure-logic singleton-style helper that the gate
# room and the HUD can both query without reaching into GameState internals.
# It never touches the filesystem or scene tree directly except through the
# gate_room reference it is given, so it is trivially unit-testable headless.
#
# Lifecycle rule (the spec in design/gdd/stargate-planetary-runs.md): an OPEN
# Stargate is a free two-way portal both directions, unlimited crossings,
# UNTIL it closes — and it closes on the terminal world/story condition
# (GameState.scrubber_repaired), NOT on the player having crossed back once.
# This mirrors the rule PlanetGate + the gate_two_way smoke test assert; this
# module is the player-facing API for it.

# ── Destinations ────────────────────────────────────────────────────────────
# A destination is an address the player can dial. The Stargate slice ships
# with the lime planet; future destinations append to DESTINATIONS.
const DEST_LIME_PLANET: String = "lime_planet"

# Each destination carries the scene + spawn it routes to and the quest step
# the player must be on (or past) for the dial to be valid. The gate room's
# PlanetGate "to_planet" instance reads the SAME target_scene/target_spawn so
# GateTravel's dial and PlanetGate's overlap trigger agree.
const DESTINATIONS: Dictionary = {
	DEST_LIME_PLANET: {
		"label": "Lime Planet",
		"target_scene": "res://scenes/planet.tscn",
		"target_spawn": "FromShipGate",
		"quest_step": "QUEST_MINE_LIME",
	},
}

# ── Persistent-open lifecycle ────────────────────────────────────────────────
# The gate is OPEN from the first successful dial until the terminal condition
# closes it. The window is NOT closed by a single return crossing — that was
# the bug. This function is the canonical "is the gate open right now" check
# for the player-facing dialing UI.
static func is_gate_open(game_state: Node) -> bool:
	if game_state == null:
		return false
	# The gate opens once a destination has been dialed (the dial flag).
	if not bool(game_state.get("lime_planet_dialed")):
		return false
	# It closes on the terminal world/story condition, NOT on first return.
	if bool(game_state.get("scrubber_repaired")):
		return false
	return true

# True when the player may dial `dest_id` right now. A dial is allowed when:
#   • the destination is registered,
#   • the player is on (or past) the destination's quest step,
#   • the gate is either already open for this destination OR not yet open
#     (so the first dial can fire), and
#   • the terminal condition has not closed the gate.
static func can_dial(game_state: Node, dest_id: String) -> bool:
	if game_state == null:
		return false
	if not DESTINATIONS.has(dest_id):
		return false
	if bool(game_state.get("scrubber_repaired")):
		return false
	var dest: Dictionary = DESTINATIONS[dest_id]
	var required_step: String = String(dest.get("quest_step", ""))
	# The dial is valid from the quest step onward (the open window). We do not
	# require the step to match exactly — once the gate is open the player can
	# re-dial / re-travel for the whole window.
	var current_step: String = String(game_state.get("quest_step", ""))
	if not _step_at_or_after(current_step, required_step, game_state):
		return false
	return true

# Re-dial of an already-open gate is a no-op dial (the gate is already locked).
# Returns true so the UI can treat "dial" uniformly.
static func is_dial_open(game_state: Node, dest_id: String) -> bool:
	if game_state == null or not DESTINATIONS.has(dest_id):
		return false
	if dest_id != DEST_LIME_PLANET:
		return false
	return bool(game_state.get("lime_planet_dialed")) and not bool(game_state.get("scrubber_repaired"))

# ── Dialing interface ───────────────────────────────────────────────────────
# Run the dial sequence on the owning gate room and mark the destination
# dialed. The gate room owns the visual dial (ring spin + chevrons + kawoosh)
# via its dial_and_open(); this module owns the lifecycle bookkeeping around
# it. Awaitable so a UI can wait for the dial to finish.
static func dial(game_state: Node, gate_room: Node, dest_id: String, with_sfx: bool = true) -> bool:
	if game_state == null or gate_room == null:
		return false
	if not can_dial(game_state, dest_id):
		return false
	# If already open for this destination, the re-dial is a no-op success.
	if is_dial_open(game_state, dest_id):
		return true
	# Mark the destination dialed BEFORE the visual sequence so the lifecycle
	# reads "open" the instant the dial begins (matches the spec: the gate is
	# open from the dial, not from the kawoosh).
	match dest_id:
		DEST_LIME_PLANET:
			game_state.set("lime_planet_dialed", true)
		_:
			return false
	# Run the visual dial on the gate room if it exposes dial_and_open.
	if gate_room.has_method("dial_and_open"):
		await gate_room.call("dial_and_open", with_sfx)
	return true

# ── Available destinations for the current state ───────────────────────────
# Returns the list of destination ids the player can dial right now. The UI
# renders this as the dialing menu.
static func available_destinations(game_state: Node) -> Array[String]:
	var out: Array[String] = []
	if game_state == null:
		return out
	for dest_id in DESTINATIONS.keys():
		if can_dial(game_state, String(dest_id)):
			out.append(String(dest_id))
	return out

# The label for a destination id (for the UI). Empty for unknown ids.
static func destination_label(dest_id: String) -> String:
	if not DESTINATIONS.has(dest_id):
		return ""
	return String(DESTINATIONS[dest_id].get("label", ""))

# ── Crossing counter (telemetry / UI) ────────────────────────────────────────
# The gate is free two-way with unlimited crossings; we still count them for
# UI flavor (e.g. "you have crossed 3 times"). The count is per-destination and
# persisted on GameState so a save round-trip preserves it.
static func crossing_count(game_state: Node, dest_id: String) -> int:
	if game_state == null or not DESTINATIONS.has(dest_id):
		return 0
	var key: String = "gate_crossings_" + dest_id
	if game_state.has_method("get_state"):
		return int(game_state.call("get_state", key, 0))
	return int(game_state.get(key)) if game_state.get(key) != null else 0

static func increment_crossing_count(game_state: Node, dest_id: String) -> void:
	if game_state == null or not DESTINATIONS.has(dest_id):
		return
	var key: String = "gate_crossings_" + dest_id
	var cur: int = crossing_count(game_state, dest_id)
	if game_state.has_method("set_state"):
		game_state.call("set_state", key, cur + 1)
	else:
		game_state.set(key, cur + 1)

# ── Helpers ──────────────────────────────────────────────────────────────────
# Compare two quest steps by their position in the GameState quest ordering.
# Returns true when `current` is at or after `required` in the ordering. We
# read the ordering from GameState's QUEST_* constants so this stays in sync
# with the real quest state machine without a hardcoded list here.
static func _step_at_or_after(current: String, required: String, game_state: Node) -> bool:
	if current == required:
		return true
	if required.is_empty():
		return true
	# Build the ordering from GameState's QUEST_* constants. We walk the
	# property list so the ordering stays in sync with GameState without a
	# hardcoded copy here.
	var order: Array[String] = []
	if game_state != null:
		for prop in game_state.get_property_list():
			var n: String = String(prop.get("name", ""))
			if n.begins_with("QUEST_"):
				order.append(String(game_state.get(n)))
	# If either step is missing from the ordering, fall back to equality only
	# (already checked above) — a future/unknown step is treated as not-yet.
	var ci: int = order.find(current)
	var ri: int = order.find(required)
	if ci < 0 or ri < 0:
		return false
	return ci >= ri