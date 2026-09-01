extends Node

# Kino system manager. Owns deployed kino tracking, kino scout/plan flags,
# kino orb acquire/consume, and the Kino Remote map UI state (pan/zoom/floor/marker).
# Extracted from GameState (the god object) as part of the P0 refactor.
# GameState keeps thin back-compat facades that proxy here.
#
# Note: the kino pilot/return batons (kino_pilot_mode, kino_return_position, etc.)
# are TRANSIENT cross-scene batons that stay on GameState because they're read
# by room.gd / gate_room.gd alongside other spawn batons. Only the persistent
# kino state lives here.
#
# Save contract: registers as "kino_system" via SaveManager.register_system.

signal deployed_kinos_changed()

const KINO_ORB_MAX: int = 3
const KINO_DEPLOYED_MAX: int = 3

# Kinos left DEPLOYED out in the world (not in inventory). FIFO, newest last,
# capped at KINO_DEPLOYED_MAX.
var deployed_kinos: Array = []

# Story flags.
var kino_scout_done: bool = false
var kino_plan_approved: bool = false
var away_party_briefed: bool = false

# Kino Remote map UI state — persisted so the player's preferred pan/zoom
# and any placed marker survives close + reopen and save + resume.
var kino_pan_x: float = 0.0
var kino_pan_y: float = 0.0
var kino_zoom: float = 1.0
var kino_active_floor: int = -1
var kino_marker: Dictionary = {}


func _ready() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "kino_system", self)


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _gs() -> Node:
	return _autoload_node("GameState")


func _inv() -> Node:
	return _autoload_node("Inventory")


func acquire_kino_orb() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	var held: int = int(inv.call("count", "kino_orb"))
	if held >= KINO_ORB_MAX:
		var gs: Node = _gs()
		if gs != null and gs.has_method("add_log"):
			gs.call("add_log", "Can't carry more than %d Kinos at once." % KINO_ORB_MAX)
		return
	held = int(inv.call("add_item", "kino_orb", 1, "the dispenser"))
	var gs: Node = _gs()
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Took a Kino from the dispenser. Carrying %d/%d." % [held, KINO_ORB_MAX])
	if gs != null and gs.has_method("advance_air_quest"):
		gs.call("advance_air_quest")


func consume_kino_orb() -> bool:
	var inv: Node = _inv()
	if inv == null or int(inv.call("count", "kino_orb")) <= 0:
		return false
	inv.call("remove_item", "kino_orb", 1, "launched")
	return true


func deploy_kino(scene_path: String, pos: Vector3) -> void:
	deployed_kinos.append({"scene": scene_path, "x": pos.x, "y": pos.y, "z": pos.z})
	while deployed_kinos.size() > KINO_DEPLOYED_MAX:
		deployed_kinos.pop_front()
	var gs: Node = _gs()
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Kino deployed (%d/%d tracked)." % [deployed_kinos.size(), KINO_DEPLOYED_MAX])
	deployed_kinos_changed.emit()


func deployed_kinos_in_scene(scene_path: String) -> Array:
	var out: Array = []
	for k in deployed_kinos:
		if String((k as Dictionary).get("scene", "")) == scene_path:
			out.append(Vector3(
				float((k as Dictionary).get("x", 0.0)),
				float((k as Dictionary).get("y", 0.0)),
				float((k as Dictionary).get("z", 0.0))))
	return out


func complete_kino_scout() -> void:
	if kino_scout_done:
		return
	kino_scout_done = true
	var gs: Node = _gs()
	if gs != null and gs.has_method("add_log"):
		gs.call("add_log", "Kino recon confirmed: breathable atmosphere, lime deposits near the gate.")
	if gs != null and gs.has_method("advance_air_quest"):
		gs.call("advance_air_quest")


func reset() -> void:
	deployed_kinos.clear()
	kino_scout_done = false
	kino_plan_approved = false
	away_party_briefed = false
	kino_pan_x = 0.0
	kino_pan_y = 0.0
	kino_zoom = 1.0
	kino_active_floor = -1
	kino_marker = {}


# --- Save / Load --------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"deployed_kinos": deployed_kinos.duplicate(true),
		"kino_scout_done": kino_scout_done,
		"kino_plan_approved": kino_plan_approved,
		"away_party_briefed": away_party_briefed,
		"kino_pan_x": kino_pan_x,
		"kino_pan_y": kino_pan_y,
		"kino_zoom": kino_zoom,
		"kino_active_floor": kino_active_floor,
		"kino_marker": kino_marker.duplicate(true),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	deployed_kinos.clear()
	var loaded_kinos: Variant = data.get("deployed_kinos", [])
	if loaded_kinos is Array:
		for k in loaded_kinos:
			if k is Dictionary:
				deployed_kinos.append({
					"scene": String((k as Dictionary).get("scene", "")),
					"x": float((k as Dictionary).get("x", 0.0)),
					"y": float((k as Dictionary).get("y", 0.0)),
					"z": float((k as Dictionary).get("z", 0.0)),
				})
	kino_scout_done = data.get("kino_scout_done", false) == true
	kino_plan_approved = data.get("kino_plan_approved", false) == true
	away_party_briefed = data.get("away_party_briefed", false) == true
	kino_pan_x = float(data.get("kino_pan_x", 0.0))
	kino_pan_y = float(data.get("kino_pan_y", 0.0))
	kino_zoom = float(data.get("kino_zoom", 1.0))
	kino_active_floor = int(data.get("kino_active_floor", -1))
	var marker_raw: Variant = data.get("kino_marker", {})
	kino_marker = marker_raw if marker_raw is Dictionary else {}