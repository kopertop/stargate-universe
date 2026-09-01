extends Node
class_name EquipmentSystem

# Equipment system (#32, #72-75). Five-slot gear loadout with stat modifiers.
#
# Slots: helmet, vest, backpack, pants, boots.
# Each slot holds at most one gear piece at a time. Equipping a piece into an
# occupied slot performs a clean swap (the previous piece is returned to the
# caller's inventory pool — the system is loadout-agnostic about storage).
#
# Stat modifiers are applied additively across all equipped pieces. The system
# tracks a base_stats dictionary (the character's naked stats) and computes
# derived_stats = base + sum(equipped piece stats) on every equip/unequip.
#
# This system is data-driven via scripts/data/equipment.gd (#73). It does NOT
# touch the existing Inventory autoload or character_panel.gd — those manage
# the legacy 4-slot cosmetic loadout. This is the gameplay-facing gear layer
# with real stat effects, designed to coexist until a migration consolidates
# the two.
#
# The 3D rendering is delegated to EquipmentSocket (#72), which this system
# owns one instance of (created on _ready or injected via setup()).
#
# Signals let UI panels (#74) and gameplay systems react to loadout changes.

signal equipment_changed(slot: String, item_id: String)
signal stats_recomputed(derived: Dictionary)

# Canonical slot list in display order (paper-doll top → bottom).
const SLOTS: Array[String] = ["helmet", "vest", "backpack", "pants", "boots"]

# Base stats that every character starts with before gear modifiers.
const DEFAULT_BASE_STATS: Dictionary = {
	"max_health": 100.0,
	"max_oxygen": 100.0,
	"armor": 0.0,
	"carry_capacity": 10.0,
	"move_speed": 8.0,
	"sprint_multiplier": 1.7,
}

# slot → equipped item id (absent key = empty slot). ONE registry, no per-slot
# bools (collection-fork policy).
var _equipped: Dictionary = {}
# Base stats (naked character). Overridable via set_base_stats().
var _base_stats: Dictionary = {}
# EquipmentSocket instance for 3D rendering (null in headless/no-model contexts).
var _socket: Node3D = null
# EquipmentDefs reference (loaded lazily).
var _defs: RefCounted = null


func _ready() -> void:
	_init_base_stats()
	# Attempt to create the socket layer if a model root is provided via setup().
	# In headless tests the socket may be null — all logic still works.

func _init_base_stats() -> void:
	_base_stats = DEFAULT_BASE_STATS.duplicate()


# Inject a model root to enable 3D gear rendering. Creates an EquipmentSocket
# and wires it to the model. Pass null to disable 3D rendering (headless-safe).
func setup(model_root: Node3D) -> void:
	if model_root == null:
		_socket = null
		return
	_socket = EquipmentSocket.new()
	_socket.name = "EquipmentSocket"
	_socket.setup(model_root)
	if model_root.get_tree() != null:
		model_root.add_child(_socket)


# --- equip / unequip ---------------------------------------------------------

# Equip `item_id` into its declared slot. Returns false if the item is unknown
# or not equippable. On a clean swap, emits equipment_changed for the slot with
# the new id. The caller is responsible for pool management (adding the
# previous item back, removing the new item from inventory).
func equip(item_id: String) -> bool:
	var def: Dictionary = _definition(item_id)
	if def.is_empty():
		return false
	var slot: String = String(def.get("slot", ""))
	if slot == "" or not SLOTS.has(slot):
		return false
	var prev_id: String = String(_equipped.get(slot, ""))
	_equipped[slot] = item_id
	equipment_changed.emit(slot, item_id)
	_remount_gear(slot, item_id)
	_recompute_stats()
	return true


# Equip `item_id` and return the previously-equipped item id ("" if the slot
# was empty). The caller handles pool accounting.
func equip_swap(item_id: String) -> String:
	var def: Dictionary = _definition(item_id)
	if def.is_empty():
		return ""
	var slot: String = String(def.get("slot", ""))
	if slot == "" or not SLOTS.has(slot):
		return ""
	var prev_id: String = String(_equipped.get(slot, ""))
	_equipped[slot] = item_id
	equipment_changed.emit(slot, item_id)
	_remount_gear(slot, item_id)
	_recompute_stats()
	return prev_id


# Clear `slot`, returning the previously-equipped item id ("" if already empty).
func unequip(slot: String) -> String:
	if not _equipped.has(slot):
		return ""
	var prev_id: String = String(_equipped[slot])
	_equipped.erase(slot)
	equipment_changed.emit(slot, "")
	if _socket != null:
		_socket.detach(slot)
	_recompute_stats()
	return prev_id


# Unequip all slots. Returns a Dictionary of {slot: item_id} that were cleared.
func unequip_all() -> Dictionary:
	var result: Dictionary = {}
	for slot in SLOTS:
		if _equipped.has(slot):
			result[slot] = String(_equipped[slot])
	_equipped.clear()
	if _socket != null:
		for slot in SLOTS:
			_socket.detach(slot)
	equipment_changed.emit("all", "")
	_recompute_stats()
	return result


# --- queries -----------------------------------------------------------------

# Item id currently equipped in `slot`, or "" if empty.
func equipped_in(slot: String) -> String:
	return String(_equipped.get(slot, ""))


# True if `item_id` is equipped in any slot.
func is_equipped(item_id: String) -> bool:
	for slot in _equipped:
		if String(_equipped[slot]) == item_id:
			return true
	return false


# Full loadout as a fresh slot → item_id dict (filled slots only).
func equipped_items() -> Dictionary:
	return _equipped.duplicate()


# True if `slot` is filled.
func slot_filled(slot: String) -> bool:
	return _equipped.has(slot)


# Number of filled slots.
func filled_count() -> int:
	return _equipped.size()


# The EquipmentDefs definition for `item_id`, or {} if unknown.
func _definition(item_id: String) -> Dictionary:
	_ensure_defs()
	if _defs != null:
		return _defs.call("by_id", item_id)
	return {}


# Lazy-load EquipmentDefs. Uses load() so a freshly-added class_name doesn't
# parse-error in the same run (same pattern as equipment_mount.gd test).
func _ensure_defs() -> void:
	if _defs != null:
		return
	var script: Script = load("res://scripts/data/equipment.gd")
	if script != null:
		_defs = script.new()


# --- stat modifiers ----------------------------------------------------------

# Set the base (naked) stats. Merges with DEFAULT_BASE_STATS so unspecified
# fields keep their defaults.
func set_base_stats(stats: Dictionary) -> void:
	_base_stats = DEFAULT_BASE_STATS.duplicate()
	for key in stats:
		_base_stats[key] = stats[key]
	_recompute_stats()


# Current base stats (naked, before gear modifiers).
func base_stats() -> Dictionary:
	return _base_stats.duplicate()


# Derived stats = base + sum of all equipped pieces' stat modifiers.
# Recomputed on every equip/unequip and emitted via stats_recomputed.
func derived_stats() -> Dictionary:
	return _recompute_and_get(false)


func _recompute_stats() -> Dictionary:
	return _recompute_and_get(true)


func _recompute_and_get(emit_signal: bool) -> Dictionary:
	var derived: Dictionary = _base_stats.duplicate()
	for slot in _equipped:
		var item_id: String = String(_equipped[slot])
		var def: Dictionary = _definition(item_id)
		var stats: Variant = def.get("stats", null)
		if stats is Dictionary:
			for key in stats:
				var base_val: float = float(derived.get(key, 0.0))
				derived[key] = base_val + float((stats as Dictionary)[key])
	if emit_signal:
		stats_recomputed.emit(derived)
	return derived


# Sum a specific stat across the loadout (base + modifiers).
func stat(key: String) -> float:
	var d: Dictionary = derived_stats()
	return float(d.get(key, 0.0))


# The modifier contribution from gear only (derived - base) for a stat.
func stat_modifier(key: String) -> float:
	var d: Dictionary = derived_stats()
	var b: Dictionary = _base_stats
	return float(d.get(key, 0.0)) - float(b.get(key, 0.0))


# True if ANY equipped piece declares a truthy boolean effect flag.
func has_effect(flag: String) -> bool:
	for slot in _equipped:
		var def: Dictionary = _definition(String(_equipped[slot]))
		var fx: Variant = def.get("effects", null)
		if fx is Dictionary and (fx as Dictionary).get(flag, false) == true:
			return true
	return false


# --- 3D rendering ------------------------------------------------------------

# Re-mount the 3D gear for `slot` via the socket layer. No-op if no socket.
func _remount_gear(slot: String, item_id: String) -> void:
	if _socket == null:
		return
	_socket.detach(slot)
	if item_id == "":
		return
	var def: Dictionary = _definition(item_id)
	if def.is_empty():
		return
	var gear: Node3D = _build_gear(def)
	if gear != null:
		_socket.attach(slot, gear)


# Instantiate the gear visual: the def's `model` GLB if it loads, otherwise a
# small procedural placeholder so equipping is visible/testable without art.
func _build_gear(def: Dictionary) -> Node3D:
	var model_path: String = String(def.get("model", ""))
	if model_path != "" and ResourceLoader.exists(model_path):
		var packed: PackedScene = load(model_path) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				return inst as Node3D
			inst.queue_free()
	return _placeholder_gear(def)


# Procedural fallback gear: a small colored box sized per slot.
func _placeholder_gear(def: Dictionary) -> Node3D:
	var slot: String = String(def.get("slot", ""))
	var box: BoxMesh = BoxMesh.new()
	var size: Vector3 = Vector3(0.22, 0.18, 0.22)
	match slot:
		"helmet":
			size = Vector3(0.2, 0.18, 0.2)
		"vest":
			size = Vector3(0.34, 0.34, 0.22)
		"backpack":
			size = Vector3(0.28, 0.34, 0.16)
		"pants":
			size = Vector3(0.3, 0.28, 0.26)
		"boots":
			size = Vector3(0.18, 0.14, 0.28)
	box.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = box
	mi.name = "GearPlaceholder"
	mi.set_meta("equip_placeholder", true)
	return mi


# --- save / load -------------------------------------------------------------

func serialize() -> Dictionary:
	return {"equipped": _equipped.duplicate(), "base_stats": _base_stats.duplicate()}


func deserialize(data: Dictionary, _version: int) -> void:
	_equipped.clear()
	var eq: Variant = data.get("equipped", {})
	if eq is Dictionary:
		for slot in (eq as Dictionary).keys():
			var item_id: String = String((eq as Dictionary)[slot])
			if item_id != "" and _definition(item_id) != {}:
				_equipped[String(slot)] = item_id
	var bs: Variant = data.get("base_stats", {})
	if bs is Dictionary and not (bs as Dictionary).is_empty():
		_base_stats = DEFAULT_BASE_STATS.duplicate()
		for key in bs:
			_base_stats[key] = (bs as Dictionary)[key]
	# Remount all gear + recompute stats
	if _socket != null:
		for slot in _equipped:
			_remount_gear(String(slot), String(_equipped[slot]))
	_recompute_stats()


func reset() -> void:
	if _socket != null:
		for slot in SLOTS:
			_socket.detach(slot)
	_equipped.clear()
	_init_base_stats()
	equipment_changed.emit("all", "")
	_recompute_stats()