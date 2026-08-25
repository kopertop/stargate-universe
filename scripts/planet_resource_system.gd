class_name PlanetResourceSystem
extends RefCounted

# Resource scarcity targeting, tracked display, priority targeting (nearest
# first), resource depletion, and inventory integration (issue #149).
#
# A pure helper layering OVER the existing GameState tracked-resource registry
# (TRACKED_RESOURCES: water, food, parts, lime) and the Inventory autoload pool.
# It does NOT own canonical state — it queries GameState/Inventory via the
# SceneTree root and returns render-ready data + targeting decisions. Safe to
# instantiate in headless tests; statics work without an instance.
#
# The existing systems already own:
#   * GameState.TRACKED_RESOURCES             — the ONE registry (id, label,
#                                               low_threshold, default_amount).
#   * GameState.resource_scarcity()           — deficit-ranked array.
#   * GameState.build_resource_table(seed)    — scarcest guaranteed + 1-2 extras.
#   * GameState.add_resource(id, amount, src) — routes through Inventory pool.
# This system adds the CONSUMER-FACING surface:
#   * tracked_display_rows()  — HUD/compass render-ready rows (low flag, order).
#   * priority_targets()      — nearest-first deposit targeting across types,
#                               scarcest type first so the compass highlights
#                               the most-needed deposit closest to the player.
#   * depletion tracking      — per-instance set of depleted deposit node names
#                               so a returning run doesn't re-target a spent node.
#   * grant() / inventory_count() — thin Inventory integration seams so callers
#                               don't each re-derive the autoload lookup.
#
# Headless-safe: reaches GameState/Inventory via Engine.get_main_loop().root,
# the same pattern used by hazard_zone.gd / injury_system.gd. Returns empty
# defaults when the autoloads are absent so a bare `-s` script doesn't crash.

signal depletion_changed(deposit_name: String)

# Per-instance depletion set: deposit node names that have been mined out.
# Survives for the lifetime of this RefCounted (one per planet run / scene).
var _depleted: Dictionary = {}


# --- Tracked display --------------------------------------------------------

# Render-ready rows for the HUD / compass scarcity panel. One row per tracked
# resource, in REGISTRY order (water, food, parts, lime) — the display order is
# stable; scarcity ranking is a separate query (priority_targets). Each row:
#   { id, label, amount, threshold, deficit, low }
# `low` is true when amount <= threshold (the crew is below safe stock).
# Returns an empty array when GameState is absent (headless safety).
static func tracked_display_rows() -> Array:
	var gs: Node = _game_state()
	if gs == null:
		return []
	var scarcity: Array = gs.call("resource_scarcity")
	var rows: Array = []
	# scarcity() is already deficit-sorted, but the DISPLAY order is registry
	# order — re-derive from tracked_resource_ids() so the panel is stable.
	var ids: Array = gs.call("tracked_resource_ids")
	for id in ids:
		var sid: String = String(id)
		var row: Dictionary = _find_scarcity_row(scarcity, sid)
		if row.is_empty():
			continue
		rows.append({
			"id": sid,
			"label": String(row.get("label", sid.capitalize())),
			"amount": int(row.get("amount", 0)),
			"threshold": int(row.get("threshold", 0)),
			"deficit": int(row.get("deficit", 0)),
			"low": int(row.get("amount", 0)) <= int(row.get("threshold", 0)),
		})
	return rows


# The scarcest tracked resource id (deepest deficit). "" when none tracked.
static func scarcest_id() -> String:
	var gs: Node = _game_state()
	if gs == null:
		return ""
	var ranked: Array = gs.call("resource_scarcity")
	if ranked.is_empty():
		return ""
	return String((ranked[0] as Dictionary).get("id", ""))


# --- Priority targeting (nearest first) -------------------------------------

# Given a viewer world position and a list of deposit descriptors, return them
# sorted by NEAREST first, with the scarcest resource type's deposits FIRST
# (a tie-break group: all scarcest-type deposits by distance, then the next
# type's deposits by distance, etc.). Each deposit entry:
#   { "type": String, "node": String, "position": Vector3 }
# Returns a fresh sorted array; the input is not mutated. Deposits whose node
# name is in this instance's depletion set are EXCLUDED (already mined out).
#
# The scarcest type is resolved once at call time from GameState.resource_scarcity()
# so a run retargets as the crew's needs shift. When the scarcest type has no
# deposits in the list, its group is simply empty and the next type leads.
func priority_targets(viewer_pos: Vector3, deposits: Array) -> Array:
	var scarcest: String = scarcest_id()
	# Group by type, preserving only non-depleted deposits.
	var by_type: Dictionary = {}
	for d in deposits:
		if not (d is Dictionary):
			continue
		var entry: Dictionary = d
		var node_name: String = String(entry.get("node", ""))
		if is_depleted(node_name):
			continue
		var type: String = String(entry.get("type", ""))
		var pos: Variant = entry.get("position", null)
		if not (pos is Vector3):
			continue
		var dist: float = _planar_dist(viewer_pos, pos)
		if not by_type.has(type):
			by_type[type] = []
		(by_type[type] as Array).append({
			"type": type,
			"node": node_name,
			"position": pos,
			"distance": dist,
		})
	# Order types: scarcest first, then the rest in registry order.
	var type_order: Array = _type_priority_order(scarcest)
	var out: Array = []
	for type in type_order:
		if not by_type.has(type):
			continue
		var group: Array = by_type[type]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["distance"]) < float(b["distance"]))
		for entry in group:
			out.append(entry)
	return out


# The type ordering for priority_targets: scarcest first, then the remaining
# tracked resources in registry order. Non-tracked types append at the end in
# the order they first appear in the deposits.
func _type_priority_order(scarcest: String) -> Array:
	var gs: Node = _game_state()
	var registry: Array = gs.call("tracked_resource_ids") if gs != null else []
	var order: Array = []
	if scarcest != "":
		order.append(scarcest)
	for id in registry:
		var sid: String = String(id)
		if sid != scarcest:
			order.append(sid)
	return order


# --- Depletion tracking -----------------------------------------------------

# Mark a deposit node as mined out. Idempotent. Emits depletion_changed.
func register_depletion(deposit_name: String) -> void:
	if deposit_name == "" or _depleted.has(deposit_name):
		return
	_depleted[deposit_name] = true
	depletion_changed.emit(deposit_name)


# True if `deposit_name` has been registered as depleted.
func is_depleted(deposit_name: String) -> bool:
	return _depleted.has(deposit_name)


# Number of deposits currently tracked as depleted.
func depleted_count() -> int:
	return _depleted.size()


# Clear all depletion records (e.g. on a fresh planet run).
func clear_depletions() -> void:
	_depleted.clear()


# --- Inventory integration --------------------------------------------------

# Grant `amount` of `resource_type` to the Inventory pool. Returns the new
# count, or -1 when Inventory is absent. Routes through Inventory.add_item
# directly (returns the new count int) rather than GameState.add_resource
# (which returns a bool), so the return value is the post-grant count.
# `source` is the audit label passed to Inventory.
static func grant(resource_type: String, amount: int, source: String = "planet") -> int:
	var inv: Node = _inventory()
	if inv == null:
		return -1
	return int(inv.call("add_item", resource_type, amount, source))


# Current Inventory count for `id`. 0 when Inventory is absent.
static func inventory_count(id: String) -> int:
	var inv: Node = _inventory()
	if inv == null:
		return 0
	return int(inv.call("count", id))


# True when the crew is low on `id` (amount <= low_threshold from the registry).
static func is_low(id: String) -> bool:
	var gs: Node = _game_state()
	if gs == null:
		return false
	return int(gs.call("resource_deficit", id)) > 0


# --- Helpers ----------------------------------------------------------------

static func _game_state() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("GameState")


static func _inventory() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("Inventory")


static func _find_scarcity_row(scarcity: Array, id: String) -> Dictionary:
	for row in scarcity:
		if row is Dictionary and String((row as Dictionary).get("id", "")) == id:
			return row
	return {}


# Planar (XZ) distance — the planet surface is walked in 2D; height doesn't
# make a deposit "further" in the targeting sense.
static func _planar_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()