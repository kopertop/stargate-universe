extends Node

# Planet / gate-window system manager. Owns the active planet spec, the
# planets-dialed counter, the gate-window countdown, resource table building,
# planet scan profiles, and the run-start resource snapshot.
# Extracted from GameState (the god object) as part of the P0 refactor.
# GameState keeps thin back-compat facades that proxy here.
#
# Save contract: registers as "planet_system" via SaveManager.register_system.

signal gate_window_expired()

const PLANETS_PATH: String = "res://data/planets.json"
const AIR_LIME_WORLD_ID: String = "air_lime_world"
const PLANET_SEED_SALT: int = 2654435761
const AIR_LIME_RESOURCE: String = "lime"
const AIR_LIME_REQUIRED: int = 3
const PLANET_WINDOW_BASE: float = 600.0

# Active procedural-planet spec. Empty until a planet is dialed.
var active_planet_spec: Dictionary = {}

# Monotonic count of planets the gate has dialed this game.
var planets_dialed: int = 0

# Gate-window departure countdown.
var gate_window_active: bool = false
var gate_window_remaining: float = 0.0
# Per-run heat/hazard water drain rate (stamped at run start from the biome).
var gate_window_water_drain: float = 0.0
var _water_drain_accum: float = 0.0

# Snapshot of tracked-resource counts captured at run start.
var run_start_resources: Dictionary = {}

var _ftl_drop_game_time: float = -1.0


func _ready() -> void:
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "planet_system", self)


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _gs() -> Node:
	return _autoload_node("GameState")


# --- Gate window --------------------------------------------------------------

func start_gate_window(duration: float) -> bool:
	if gate_window_active:
		return false
	gate_window_active = true
	gate_window_remaining = duration
	gate_window_water_drain = PlanetGenerator.water_drain_for(active_planet_spec)
	_water_drain_accum = 0.0
	# Snapshot the crew's tracked-resource stock at run start.
	run_start_resources = {}
	var gs: Node = _gs()
	if gs != null and gs.has_method("tracked_resource_ids") and gs.has_method("resource_count"):
		for id in gs.call("tracked_resource_ids"):
			run_start_resources[id] = int(gs.call("resource_count", id))
	return true


func tick_gate_window(delta: float) -> void:
	_tick_heat_water_drain(delta)
	# Toxic / no-atmosphere biome: oxygen drains while on-surface.
	var gs: Node = _gs()
	if gs != null and gs.has_method("_tick_atmosphere_oxygen_drain"):
		if gs.call("_tick_atmosphere_oxygen_drain", delta):
			return
	gate_window_remaining = maxf(0.0, gate_window_remaining - delta)
	if gate_window_remaining <= 0.0:
		gate_window_active = false
		gate_window_expired.emit()


func _tick_heat_water_drain(delta: float) -> void:
	if gate_window_water_drain <= 0.0:
		return
	_water_drain_accum += gate_window_water_drain * delta
	var gs: Node = _gs()
	while _water_drain_accum >= 1.0:
		_water_drain_accum -= 1.0
		if gs != null and gs.has_method("resource_count") and gs.call("resource_count", "water") <= 0:
			_water_drain_accum = 0.0
			return
		if gs != null and gs.has_method("spend_resource"):
			gs.call("spend_resource", "water", 1, "the heat")


# --- Planet spec building -----------------------------------------------------

func build_next_planet_spec(name_hint: String = "", force_biome: String = "",
		force_seed: int = -1) -> Dictionary:
	planets_dialed += 1
	var run_seed: int = force_seed if force_seed >= 0 else _planet_run_seed(planets_dialed)
	var biome: String = force_biome
	if biome == "":
		var gs: Node = _gs()
		var flags: Dictionary = {}
		if gs != null and gs.has_method("biome_flags"):
			flags = gs.call("biome_flags")
		biome = PlanetGenerator.select_biome(run_seed, flags)
	var bp: Dictionary = PlanetGenerator.biome_params(biome)
	var hz: Variant = bp.get("hazard", {})
	var hazard_params: Dictionary = (hz as Dictionary).duplicate(true) if hz is Dictionary else {}
	var label: String = String(bp.get("label", biome.capitalize()))
	var planet_name: String = name_hint if name_hint != "" else "%s World" % label
	var gs: Node = _gs()
	var resource_table: Dictionary = {}
	if gs != null and gs.has_method("build_resource_table"):
		resource_table = gs.call("build_resource_table", run_seed)
	var spec: Dictionary = {
		"seed": run_seed,
		"biome": biome,
		"resource_table": resource_table,
		"hazard_params": hazard_params,
		"name": planet_name,
	}
	active_planet_spec = spec
	return spec


func _planet_run_seed(dial_index: int) -> int:
	return (dial_index * PLANET_SEED_SALT) & 0x7fffffff


func build_air_lime_spec() -> Dictionary:
	planets_dialed += 1
	var row: Dictionary = _load_planet_row(AIR_LIME_WORLD_ID)
	var atmo: Variant = row.get("atmosphere", {})
	var poi: Dictionary = {"water": 0, "ruin": 0, "ore": 0, "debris": 0}
	var spec: Dictionary = {
		"seed": int(row.get("seed", 104729)),
		"biome": "desert",
		"resource_table": {
			"lime_nodes": int(row.get("lime_nodes", 5)),
			"lime_per_node": int(row.get("lime_per_node", 1)),
			"lime_min_radius": float(row.get("lime_min_radius", 70.0)),
			"lime_max_radius": float(row.get("lime_max_radius", 200.0)),
			"lime_far_count": int(row.get("lime_far_count", 0)),
			"lime_far_min_radius": float(row.get("lime_far_min_radius", 380.0)),
			"lime_far_max_radius": float(row.get("lime_far_max_radius", 440.0)),
			"lime_far_arc": float(row.get("lime_far_arc", 0.7)),
			"poi_counts": poi if poi is Dictionary else {},
		},
		"hazard_params": atmo if atmo is Dictionary else {},
		"name": String(row.get("name", "Lime World")),
	}
	active_planet_spec = spec
	return spec


func _load_planet_row(id: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(PLANETS_PATH, FileAccess.READ)
	if f == null:
		push_error("planet_system.gd: cannot open %s" % PLANETS_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		push_error("planet_system.gd: %s did not parse to an array" % PLANETS_PATH)
		return {}
	for entry in parsed:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == id:
			return entry as Dictionary
	return {}


func planet_scan_profile(spec: Dictionary = {}) -> Dictionary:
	var s: Dictionary = spec if (spec is Dictionary and not spec.is_empty()) else active_planet_spec
	var biome: String = String(s.get("biome", "desert"))
	var bp: Dictionary = PlanetGenerator.biome_params(biome)
	var hz: Dictionary = bp.get("hazard", {}) if bp.get("hazard", {}) is Dictionary else {}
	var breathable: bool = PlanetGenerator.breathable_for(s)
	var hazard_type: String = String(hz.get("type", "none"))
	var resources: Array = []
	var rt: Variant = s.get("resource_table", {})
	if rt is Dictionary and (rt as Dictionary).get("clusters", null) is Array:
		for c in (rt as Dictionary)["clusters"]:
			if c is Dictionary:
				var gs: Node = _gs()
				if gs != null and gs.has_method("resource_label"):
					resources.append(gs.call("resource_label", String((c as Dictionary).get("type", ""))))
				else:
					resources.append(String((c as Dictionary).get("type", "").capitalize()))
	if resources.is_empty():
		resources.append("Lime")
	return {
		"biome": biome,
		"label": String(bp.get("label", biome.capitalize())),
		"breathable": breathable,
		"composition": "BREATHABLE" if breathable else String(hz.get("toxins", "TOXIC")),
		"temperature_c": int(hz.get("temperature_c", 20)),
		"temperature_note": _temp_note(int(hz.get("temperature_c", 20))),
		"radiation": String(hz.get("radiation", "LOW")),
		"toxins": String(hz.get("toxins", "NONE")) if not breathable else "NONE",
		"hazard": hazard_type.to_upper() if hazard_type != "none" else "NONE",
		"gate_window": PlanetGenerator.gate_window_for(s),
		"resources": resources,
	}


func _temp_note(temp_c: int) -> String:
	if temp_c >= 40:
		return "HOT"
	if temp_c >= 28:
		return "WARM"
	if temp_c <= 0:
		return "COLD"
	return ""


func run_target_resource() -> String:
	var spec: Dictionary = active_planet_spec
	var rt: Variant = spec.get("resource_table", {})
	if rt is Dictionary:
		var clusters: Variant = (rt as Dictionary).get("clusters", [])
		if clusters is Array and not (clusters as Array).is_empty():
			var first: Variant = (clusters as Array)[0]
			if first is Dictionary:
				var t: String = String((first as Dictionary).get("type", ""))
				if t != "":
					return t
	return AIR_LIME_RESOURCE


func reconcile_run_resources_on_knockout() -> void:
	if run_start_resources.is_empty():
		return
	var gs: Node = _gs()
	if gs == null:
		return
	var inv: Node = _autoload_node("Inventory")
	if inv == null:
		return
	var target: String = run_target_resource()
	if not gs.has_method("tracked_resource_ids"):
		return
	for id in gs.call("tracked_resource_ids"):
		if not run_start_resources.has(id):
			continue
		var start_count: int = int(run_start_resources[id])
		var current: int = int(gs.call("resource_count", id))
		var gathered: int = maxi(0, current - start_count)
		var keep: int = start_count
		if id == target:
			keep = start_count + mini(gathered, 1)  # KNOCKOUT_TARGET_BANK
		if keep != current:
			inv.call("set_count", id, keep)
			if gs.has_method("_emit_resource_changed"):
				gs.call("_emit_resource_changed", id, keep)
			elif gs.has_signal("resource_changed"):
				gs.resource_changed.emit(id, keep)


func reset() -> void:
	active_planet_spec = {}
	planets_dialed = 0
	gate_window_active = false
	gate_window_remaining = 0.0
	gate_window_water_drain = 0.0
	_water_drain_accum = 0.0
	run_start_resources = {}
	_ftl_drop_game_time = -1.0


# --- Save / Load --------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"active_planet_spec": active_planet_spec.duplicate(true),
		"planets_dialed": planets_dialed,
		"gate_window_active": gate_window_active,
		"gate_window_remaining": gate_window_remaining,
		"gate_window_water_drain": gate_window_water_drain,
		"run_start_resources": run_start_resources.duplicate(true),
		"ftl_drop_game_time": _ftl_drop_game_time,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	var saved_spec: Variant = data.get("active_planet_spec", {})
	active_planet_spec = (saved_spec as Dictionary).duplicate(true) if saved_spec is Dictionary else {}
	planets_dialed = int(data.get("planets_dialed", 0))
	gate_window_active = data.get("gate_window_active", false) == true
	gate_window_remaining = float(data.get("gate_window_remaining", 0.0))
	gate_window_water_drain = float(data.get("gate_window_water_drain", 0.0))
	_water_drain_accum = 0.0
	run_start_resources = {}
	var saved_run_res: Variant = data.get("run_start_resources", {})
	if saved_run_res is Dictionary:
		for k in (saved_run_res as Dictionary).keys():
			run_start_resources[String(k)] = int((saved_run_res as Dictionary)[k])
	_ftl_drop_game_time = float(data.get("ftl_drop_game_time", -1.0))