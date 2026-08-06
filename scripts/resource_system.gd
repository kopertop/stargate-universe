extends Node

# Resource system manager. Owns tracked resource definitions, resource
# scarcity/deficit calculations, and resource table building.
# Extracted from GameState as part of the P0 refactor.
# GameState keeps thin facades so existing callers work without changes.

const AIR_LIME_RESOURCE: String = "lime"
const TRACKED_RESOURCES: Array[Dictionary] = [
	{"id": "water", "label": "Water", "low_threshold": 10, "default_amount": 4},
	{"id": "food", "label": "Food", "low_threshold": 10, "default_amount": 6},
	{"id": "parts", "label": "Ship Parts", "low_threshold": 6, "default_amount": 2},
	{"id": "lime", "label": "Lime", "low_threshold": 3, "default_amount": 0},
]


func _ready() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "resource_system", self)


func serialize() -> Dictionary:
	# Resources are stored in Inventory; SaveManager serializes that
	# separately.  Nothing extra to persist here.
	return {}


func deserialize(_data: Dictionary, _version: int) -> void:
	# Resources are restored via Inventory.deserialize; nothing to do here.
	pass


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _gs() -> Node:
	return _autoload_node("GameState")


func _inv() -> Node:
	return _autoload_node("Inventory")


func resource_count(type: String) -> int:
	var inv: Node = _inv()
	return 0 if inv == null else int(inv.call("count", type))


func add_resource(type: String, amount: int, source: String = "") -> bool:
	if amount <= 0:
		return false
	var inv: Node = _inv()
	if inv == null:
		return false
	var gs: Node = _gs()
	var next_amount: int = int(inv.call("add_item", type, amount, source))
	var source_suffix: String = "" if source == "" else " from " + source
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Collected %d %s%s. Total: %d." % [amount, type, source_suffix, next_amount])
	if gs != null and gs.has_method("_emit_resource_changed"):
		gs.call("_emit_resource_changed", type, next_amount)
	if gs != null and gs.has_method("advance_air_quest"):
		gs.call("advance_air_quest")
	return true


func has_resource(type: String, amount: int) -> bool:
	return resource_count(type) >= amount


func spend_resource(type: String, amount: int, reason: String = "") -> bool:
	if amount <= 0:
		return true
	var gs: Node = _gs()
	var current: int = resource_count(type)
	if current < amount:
		if gs != null and gs.has_method("add_log"):
			gs.call("add_log", "Need %d %s for %s. Current: %d." % [amount, type, reason, current])
		return false
	var inv: Node = _inv()
	if inv != null:
		inv.call("remove_item", type, amount, reason)
	var reason_suffix: String = "" if reason == "" else " for " + reason
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Spent %d %s%s. Remaining: %d." % [amount, type, reason_suffix, resource_count(type)])
	if gs != null and gs.has_method("_emit_resource_changed"):
		gs.call("_emit_resource_changed", type, resource_count(type))
	if gs != null and gs.has_method("advance_air_quest"):
		gs.call("advance_air_quest")
	return true


func seed_default_resources() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	for row in TRACKED_RESOURCES:
		inv.call("set_count", String(row["id"]), int(row.get("default_amount", 0)))


func tracked_resource_ids() -> Array:
	var ids: Array = []
	for row in TRACKED_RESOURCES:
		ids.append(String(row["id"]))
	return ids


func resource_deficit(id: String) -> int:
	for row in TRACKED_RESOURCES:
		if String(row["id"]) == id:
			return maxi(0, int(row.get("low_threshold", 0)) - resource_count(id))
	return 0


func resource_scarcity() -> Array:
	var rows: Array = []
	var order: int = 0
	for row in TRACKED_RESOURCES:
		var id: String = String(row["id"])
		var amount: int = resource_count(id)
		var threshold: int = int(row.get("low_threshold", 0))
		rows.append({"id": id, "label": String(row.get("label", id.capitalize())),
			"amount": amount, "threshold": threshold,
			"deficit": maxi(0, threshold - amount), "_order": order})
		order += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["deficit"]) != int(b["deficit"]):
			return int(a["deficit"]) > int(b["deficit"])
		return int(a["_order"]) < int(b["_order"]))
	for r in rows:
		(r as Dictionary).erase("_order")
	return rows


func build_resource_table(seed: int) -> Dictionary:
	var ps: Node = _autoload_node("PlanetSystem")
	if ps != null:
		return ps.call("_build_resource_table_from_scarcity", resource_scarcity(), seed)
	return {}


func resource_label(id: String) -> String:
	for row in TRACKED_RESOURCES:
		if String(row["id"]) == id:
			return String(row.get("label", id.capitalize()))
	if id == AIR_LIME_RESOURCE:
		return "Lime"
	return id.capitalize()