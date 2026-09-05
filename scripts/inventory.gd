extends Node

# Canonical inventory store — the SINGLE source of truth for every item the
# player carries, held as `id -> count`. There are no item booleans anywhere
# else: kino remote, kino orbs, fuses, lime, rations all live here as counts.
# Item metadata (name, icon, category, stack rules) is data (data/items.json).
#
# Registered with SaveManager as "inventory" so the pool persists. GameState
# exposes thin resource shims (resource_count/has_resource/add_resource/
# spend_resource) and the acquire/consume helpers that route through here;
# old saves (which stored kino_acquired / *_fuse_found / kino_orbs / a
# `resources` dict on GameState) are migrated into this pool by
# GameState.deserialize before this system's own block loads.

signal changed
signal item_changed(id: String, count: int)
# Loadout changed: `slot` is the affected slot ("head"/"torso"/"back"/"legs");
# `item_id` is the now-equipped item there, or "" when the slot was cleared.
# Character mount + equipment UI listen to this.
signal equipment_changed(slot: String, item_id: String)
# Hotbar wield: `index` is 0–3, `item_id` is the newly active item (may be "").
signal wield_changed(index: int, item_id: String)

const ITEMS_PATH: String = "res://data/items.json"

# The four equipment slots, in canonical display order. Equipment item defs in
# data/items.json carry `category: "equipment"` + `slot: <one of these>`.
const EQUIP_SLOTS: Array[String] = ["head", "torso", "back", "legs"]
# Subnautica-style tool/weapon hotbar (HUD slots 1–4 / D-pad). Index 0 = tablet
# / kino remote; index 1 = sidearm; 2–3 reserved.
const WIELD_SLOT_COUNT: int = 4

# Ordered catalog (display order) + id->definition lookup.
var _catalog: Array = []
var _by_id: Dictionary = {}
# Canonical state: item id -> count (count > 0; zeroed entries are erased).
var _items: Dictionary = {}
# Canonical loadout: ONE collection, slot -> equipped item id. Slots are only
# present when filled (an absent key means the slot is empty). This is the
# single registry for "what the crew member is wearing" — no per-slot bools.
var _equipped: Dictionary = {}
# Hotbar assignments: fixed-length array of item ids ("" = empty frame).
var _wield_slots: Array[String] = ["", "", "", ""]
var _active_wield_index: int = 0
var _loaded: bool = false
var _registered: bool = false


func _ready() -> void:
	_ensure_loaded()
	_register()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if f == null:
		push_error("Inventory: cannot open %s" % ITEMS_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		push_error("Inventory: %s did not parse to an array" % ITEMS_PATH)
		return
	for entry in parsed:
		if not (entry is Dictionary):
			continue
		var def: Dictionary = entry
		var id: String = String(def.get("id", ""))
		if id == "":
			continue
		_catalog.append(def)
		_by_id[id] = def


func _register() -> void:
	if _registered:
		return
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "inventory", self)
		_registered = true


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# --- mutation ----------------------------------------------------------------

# Add `amount` of `id`. Non-stackable items (per the catalog) cap at 1.
# Returns the new count.
func add_item(id: String, amount: int = 1, _source: String = "") -> int:
	_ensure_loaded()
	if amount <= 0:
		return count(id)
	var def: Dictionary = _by_id.get(id, {})
	var stackable: bool = def.get("stackable", true) == true
	var cur: int = int(_items.get(id, 0))
	var next: int = (1 if not stackable else cur + amount)
	if next == cur:
		return cur
	_items[id] = next
	_emit(id, next)
	return next


# Remove `amount` of `id`, clamped at 0. Returns the new count. This is the
# consume path (e.g. fitting a fuse into the door, launching a Kino).
func remove_item(id: String, amount: int = 1, _reason: String = "") -> int:
	_ensure_loaded()
	var cur: int = int(_items.get(id, 0))
	if amount <= 0 or cur == 0:
		return cur
	var next: int = maxi(0, cur - amount)
	if next == 0:
		_items.erase(id)
	else:
		_items[id] = next
	_emit(id, next)
	return next


# Force `id` to an exact count (used for the kino_orbs `= N` assignment path
# and save migration). Negative clamps to 0.
func set_count(id: String, n: int) -> void:
	_ensure_loaded()
	var v: int = maxi(0, n)
	var cur: int = int(_items.get(id, 0))
	if v == cur:
		return
	if v == 0:
		_items.erase(id)
	else:
		_items[id] = v
	_emit(id, v)


func _emit(id: String, n: int) -> void:
	item_changed.emit(id, n)
	changed.emit()


# --- queries -----------------------------------------------------------------

func count(id: String) -> int:
	_ensure_loaded()
	return int(_items.get(id, 0))


func has(id: String, amount: int = 1) -> bool:
	return count(id) >= amount


func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})


# The single enumerable surface the UI renders: catalog-ordered
# [{ id, def, count }] for every held item with show_in_inventory. Consumers
# iterate this and never name a specific item.
func entries() -> Array:
	_ensure_loaded()
	var out: Array = []
	for def in _catalog:
		if def.get("show_in_inventory", true) != true:
			continue
		var id: String = String(def.get("id", ""))
		var c: int = count(id)
		if c > 0:
			out.append({"id": id, "def": def, "count": c})
	return out


func catalog_ids() -> Array:
	_ensure_loaded()
	var ids: Array = []
	for def in _catalog:
		ids.append(String(def.get("id", "")))
	return ids


# --- equipment ---------------------------------------------------------------
#
# The loadout is ONE `_equipped` dict (slot -> item id) behind this API. The
# inventory pool (`_items`) and the loadout are kept consistent: equipping an
# item removes one from the pool; unequipping (or swapping it out) returns one.

# True if `id` is an equipment item (category == "equipment") with a valid slot.
func is_equippable(id: String) -> bool:
	_ensure_loaded()
	var def: Dictionary = _by_id.get(id, {})
	if String(def.get("category", "")) != "equipment":
		return false
	return EQUIP_SLOTS.has(String(def.get("slot", "")))


# Slot an equippable item belongs to ("" if not equippable).
func slot_of(id: String) -> String:
	_ensure_loaded()
	if not is_equippable(id):
		return ""
	return String((_by_id.get(id, {}) as Dictionary).get("slot", ""))


# Equip `id` into its declared slot. The item must be an equipment item the
# player currently holds (count > 0). Whatever already occupies the slot is
# returned to the inventory pool first (clean swap). Removes one of `id` from
# the pool and records it in `_equipped`. Emits `equipment_changed`. Returns
# true on success, false if the item is not equippable or not held.
func equip(id: String) -> bool:
	_ensure_loaded()
	if not is_equippable(id):
		return false
	if count(id) <= 0:
		return false
	var slot: String = slot_of(id)
	# Already equipped in this slot — nothing to do.
	if String(_equipped.get(slot, "")) == id:
		return true
	# Return the currently-equipped item (if any) to the pool.
	var prev: String = String(_equipped.get(slot, ""))
	if prev != "":
		add_item(prev, 1, "unequipped (swap)")
	# Consume one of the new item from the pool and seat it.
	remove_item(id, 1, "equipped")
	_equipped[slot] = id
	equipment_changed.emit(slot, id)
	return true


# Clear `slot`, returning the equipped item (if any) to the inventory pool.
# Emits `equipment_changed(slot, "")`. No-op on an already-empty slot.
func unequip(slot: String) -> void:
	_ensure_loaded()
	if not _equipped.has(slot):
		return
	var id: String = String(_equipped[slot])
	_equipped.erase(slot)
	if id != "":
		add_item(id, 1, "unequipped")
	equipment_changed.emit(slot, "")


# Item id currently equipped in `slot`, or "" if the slot is empty.
func equipped_in(slot: String) -> String:
	_ensure_loaded()
	return String(_equipped.get(slot, ""))


# True if `id` is equipped in any slot.
func is_equipped(id: String) -> bool:
	_ensure_loaded()
	for slot in _equipped:
		if String(_equipped[slot]) == id:
			return true
	return false


# The full loadout as a fresh `slot -> item id` dict (filled slots only).
func equipped_items() -> Dictionary:
	_ensure_loaded()
	return _equipped.duplicate()


# --- functional-effect hook seams (#75) --------------------------------------
#
# Equipment is COSMETIC-FIRST by design decision (#32/#75): equipping gear today
# only changes the character's look. These seams exist so a FOLLOW-UP issue can
# attach gameplay effects to gear WITHOUT a refactor — gameplay code can already
# ask the loadout "do I have atmosphere protection?" / "what's my carry-capacity
# modifier?" and get a correct (currently zero/false) answer that lights up the
# moment effect data is added to data/items.json. No effect is implemented here.
#
# Contract: an equipment def in data/items.json MAY carry an optional
# `effects` sub-object, e.g.
#     "effects": { "atmosphere_protection": true, "carry_capacity": 4 }
# When absent (the cosmetic-first default for every shipped item), the seams
# below report the no-effect baseline. The follow-up issue: (a) authors `effects`
# on the relevant defs, (b) wires the call sites flagged with TODO below
# into the systems that consume them (planet atmosphere gate, inventory
# capacity). The accumulation rules here (any-true / additive-sum) are the
# intended semantics; only the consumer wiring is deferred. (Issue #75 closed.)

# The raw `effects` dict declared on an item def (empty when none / not a def).
func _effects_of(item_id: String) -> Dictionary:
	var def: Dictionary = _by_id.get(item_id, {})
	var e: Variant = def.get("effects", null)
	return e if e is Dictionary else {}


# Sum a numeric `effects` field across the whole equipped loadout (additive
# stacking across slots). Returns `default` contribution when no gear declares
# the field. Generic accumulator the named seams below delegate to.
func equipped_effect_total(field: String, default: float = 0.0) -> float:
	_ensure_loaded()
	var total: float = default
	for slot in _equipped:
		var fx: Dictionary = _effects_of(String(_equipped[slot]))
		if fx.has(field):
			total += float(fx[field])
	return total


# True if ANY equipped item declares a truthy `effects` boolean `field`
# (any-true stacking — one protective piece is enough). Generic predicate the
# named seams below delegate to.
func equipped_effect_flag(field: String) -> bool:
	_ensure_loaded()
	for slot in _equipped:
		var fx: Dictionary = _effects_of(String(_equipped[slot]))
		if fx.get(field, false) == true:
			return true
	return false


# SEAM: head-slot helmet → off-world atmosphere protection (future hook).
# TODO: call from the planet atmosphere gate (planet.gd /
# atmo_readout.gd) so a protected crew member ignores a hostile-atmosphere
# debuff. Reports false today (no shipped def carries the effect — cosmetic).
func has_atmosphere_protection() -> bool:
	return equipped_effect_flag("atmosphere_protection")


# SEAM: back-slot pack → carry-capacity modifier (future hook).
# TODO: add this to the base pack size where carry limits are
# enforced (the inventory cap is presently unbounded, so this is inert until
# capacity is introduced). Reports 0 today (no shipped def carries the effect).
func carry_capacity_modifier() -> int:
	return int(equipped_effect_total("carry_capacity", 0.0))


# --- hotbar wield (weapons-tools) --------------------------------------------
#
# ONE registry (_wield_slots + _active_wield_index) for "what is in the player's
# hands." Distinct from wearable equipment (armor paper-doll). Items with
# `wieldable: true` in data/items.json may be assigned to a hotbar index.

func is_wieldable(id: String) -> bool:
	_ensure_loaded()
	var def: Dictionary = _by_id.get(id, {})
	return def.get("wieldable", false) == true


func wield_kind(id: String) -> String:
	_ensure_loaded()
	return String((_by_id.get(id, {}) as Dictionary).get("wield_kind", ""))


func is_interface_tool(id: String) -> bool:
	return wield_kind(id) == "interface"


func is_weapon(id: String) -> bool:
	return wield_kind(id) == "weapon"


func hotbar_item(index: int) -> String:
	if index < 0 or index >= WIELD_SLOT_COUNT:
		return ""
	return _wield_slots[index]


func active_wield_index() -> int:
	return _active_wield_index


func active_wield_id() -> String:
	return hotbar_item(_active_wield_index)


func assign_hotbar(index: int, item_id: String) -> void:
	if index < 0 or index >= WIELD_SLOT_COUNT:
		return
	if item_id != "" and not is_wieldable(item_id):
		return
	if item_id != "" and count(item_id) <= 0:
		return
	if _wield_slots[index] == item_id:
		return
	_wield_slots[index] = item_id
	if index == _active_wield_index:
		wield_changed.emit(_active_wield_index, item_id)


func select_wield(index: int) -> void:
	if index < 0 or index >= WIELD_SLOT_COUNT:
		return
	var id: String = _wield_slots[index]
	if id != "" and count(id) <= 0:
		_wield_slots[index] = ""
		id = ""
	_active_wield_index = index
	wield_changed.emit(index, id)


# Seed the opening hotbar after a new-game reset: tablet in slot 1 only.
# Called from GameState.seed_starter_tools().
func seed_starter_wield() -> void:
	_ensure_loaded()
	_wield_slots = ["", "", "", ""]
	if has("kino_remote"):
		_wield_slots[0] = "kino_remote"
	elif has("tablet"):
		_wield_slots[0] = "tablet"
	if has("sidearm"):
		_wield_slots[1] = "sidearm"
	_active_wield_index = 0
	wield_changed.emit(0, active_wield_id())


# Upgrade path: tablet → kino_remote keeps the same hotbar index.
func replace_hotbar_item(from_id: String, to_id: String) -> void:
	for i in WIELD_SLOT_COUNT:
		if _wield_slots[i] == from_id:
			_wield_slots[i] = to_id if (to_id != "" and has(to_id)) else ""
	if active_wield_id() == from_id or _wield_slots[_active_wield_index] == to_id:
		wield_changed.emit(_active_wield_index, active_wield_id())


# --- save / load -------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"items": _items.duplicate(),
		"equipped": _equipped.duplicate(),
		"wield_slots": _wield_slots.duplicate(),
		"active_wield": _active_wield_index,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_ensure_loaded()
	# Only own the state when our block is present. Old saves have no
	# "inventory" block — GameState.deserialize has already seeded _items from
	# the legacy fields by the time we run, so leave that seed intact.
	if not data.has("items") and not data.has("equipped"):
		return
	if data.has("items"):
		_items.clear()
		var items: Variant = data.get("items", {})
		if items is Dictionary:
			for k in (items as Dictionary).keys():
				var c: int = int((items as Dictionary)[k])
				if c > 0:
					_items[String(k)] = c
	# Loadout. Saves predating equipment have no "equipped" block; leave the
	# (empty) loadout untouched there. Only seat ids that are still equippable
	# into their declared slot (defends against renamed/removed catalog ids).
	if data.has("equipped"):
		_equipped.clear()
		var loadout: Variant = data.get("equipped", {})
		if loadout is Dictionary:
			for slot in (loadout as Dictionary).keys():
				var item_id: String = String((loadout as Dictionary)[slot])
				if item_id != "" and is_equippable(item_id) and slot_of(item_id) == String(slot):
					_equipped[String(slot)] = item_id
		for slot2 in _equipped:
			equipment_changed.emit(String(slot2), String(_equipped[slot2]))
	_wield_slots = ["", "", "", ""]
	if data.has("wield_slots"):
		var slots: Variant = data.get("wield_slots", [])
		if slots is Array:
			for i in mini(WIELD_SLOT_COUNT, (slots as Array).size()):
				var wid: String = String((slots as Array)[i])
				if wid != "" and is_wieldable(wid) and count(wid) > 0:
					_wield_slots[i] = wid
	_active_wield_index = clampi(int(data.get("active_wield", 0)), 0, WIELD_SLOT_COUNT - 1)
	wield_changed.emit(_active_wield_index, active_wield_id())
	changed.emit()


func reset() -> void:
	_ensure_loaded()
	_items.clear()
	_equipped.clear()
	_wield_slots = ["", "", "", ""]
	_active_wield_index = 0
	changed.emit()
	wield_changed.emit(0, "")
