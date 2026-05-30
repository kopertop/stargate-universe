extends Node

# @no-save: derived projection — every item count is read live from its
# canonical GameState field (kino_acquired / *_fuse_found / resources dict /
# kino_orbs). Nothing here is independent state, so there is nothing to
# serialize and old saves migrate for free (the counts come from whatever
# GameState already restored).
#
# Data-driven inventory model + the single enumerable surface the Kino Remote
# inventory page renders from. Item metadata (name, icon, description, stack
# rules, category) lives in data/items.json; this autoload loads that catalog
# and resolves each item's CURRENT count from GameState.
#
# Why a projection rather than its own store (issue #41): kino_acquired, the
# fuse bools, and the `resources` dict are read + written + asserted across the
# codebase and the test suites. Re-homing all of that into one store is the
# full #41 migration; this layer fixes the user-visible bug (looted items not
# showing) and delivers the real catalog + slot-grid UI WITHOUT churning tested
# gameplay state. Consumers (the UI) iterate entries() generically and never
# name an item — so a new catalog row + one `count()` arm is all a new item
# needs, and nothing can silently fail to render (the bug this replaces).

signal changed

const ITEMS_PATH: String = "res://data/items.json"

# Ordered catalog: Array of definition dictionaries, in display order.
var _catalog: Array = []
# id -> definition, for O(1) lookup.
var _by_id: Dictionary = {}
var _loaded: bool = false
var _connected: bool = false


func _ready() -> void:
	_ensure_loaded()
	_connect_state()


# Idempotent lazy init so headless `-s` SceneTree tests (where _ready is
# deferred until a frame ticks) still get a populated catalog the moment they
# call any public method. Mirrors QuestLog._ensure_initialized.
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


# Re-emit a single `changed` whenever any backing GameState source moves, so
# an open inventory page can refresh live. Autoload-tolerant: smoke tests wire
# their own GameState sibling under the test root with no signals guaranteed.
func _connect_state() -> void:
	if _connected:
		return
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return
	_connected = true
	if gs.has_signal("kino_changed") and not gs.is_connected("kino_changed", _on_state_changed):
		gs.connect("kino_changed", _on_state_changed)
	if gs.has_signal("resource_changed") and not gs.is_connected("resource_changed", _on_state_changed):
		gs.connect("resource_changed", _on_state_changed)
	if gs.has_signal("item_changed") and not gs.is_connected("item_changed", _on_state_changed):
		gs.connect("item_changed", _on_state_changed)


func _on_state_changed(_a: Variant = null, _b: Variant = null) -> void:
	changed.emit()


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# --- Public API --------------------------------------------------------------

# Current count the player is carrying of `id`, read from its canonical
# GameState source. Unknown ids → 0.
func count(id: String) -> int:
	_ensure_loaded()
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return 0
	match id:
		"kino_remote":
			return 1 if gs.get("kino_acquired") == true else 0
		"kino_orb":
			return int(gs.get("kino_orbs"))
		"small_fuse":
			# Spent the moment it's fitted into the jammed door panel — i.e. once
			# breach_a is sealed (shuttle_door_panel.gd consumes it there). Held
			# only between looting it and sealing the breach.
			if gs.get("small_fuse_found") != true:
				return 0
			var sealed: Variant = gs.get("breaches_sealed")
			if sealed is Array and (sealed as Array).has("breach_a"):
				return 0
			return 1
		"large_fuse":
			return 1 if gs.get("large_fuse_found") == true else 0
		_:
			# Stackable resources (lime, rations, future types) live in the
			# GameState resources pool.
			if gs.has_method("resource_count"):
				return int(gs.call("resource_count", id))
			return 0


func has(id: String, amount: int = 1) -> bool:
	return count(id) >= amount


func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(id, {})


# The single enumerable surface the UI renders. Returns catalog-ordered
# [{ id, def, count }] for every item with count > 0 and show_in_inventory.
# Consumers iterate this and NEVER name a specific item — a new item appears
# automatically once it has a catalog row and a count() source.
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


# Catalog accessor for tests / tooling.
func catalog_ids() -> Array:
	_ensure_loaded()
	var ids: Array = []
	for def in _catalog:
		ids.append(String(def.get("id", "")))
	return ids
