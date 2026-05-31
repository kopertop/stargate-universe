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

const ITEMS_PATH: String = "res://data/items.json"

# Ordered catalog (display order) + id->definition lookup.
var _catalog: Array = []
var _by_id: Dictionary = {}
# Canonical state: item id -> count (count > 0; zeroed entries are erased).
var _items: Dictionary = {}
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


# --- save / load -------------------------------------------------------------

func serialize() -> Dictionary:
	return {"items": _items.duplicate()}


func deserialize(data: Dictionary, _version: int) -> void:
	_ensure_loaded()
	# Only own the state when our block is present. Old saves have no
	# "inventory" block — GameState.deserialize has already seeded _items from
	# the legacy fields by the time we run, so leave that seed intact.
	if not data.has("items"):
		return
	_items.clear()
	var items: Variant = data.get("items", {})
	if items is Dictionary:
		for k in (items as Dictionary).keys():
			var c: int = int((items as Dictionary)[k])
			if c > 0:
				_items[String(k)] = c
	changed.emit()


func reset() -> void:
	_ensure_loaded()
	_items.clear()
	changed.emit()
