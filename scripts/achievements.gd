extends Node

# Achievements & progress tracking autoload.
#
# Data-driven: achievement definitions live in data/achievements.json so designers
# can add/retitle/reorder without touching code. Each achievement has:
#   id          — stable string id (used in save files, never rename)
#   title       — player-facing name
#   description — one-line flavour text
#   category    — "story" | "exploration" | "crafting" | "combat" (for grouping in a future UI)
#   hidden      — if true, the description stays "???" until unlocked (spoiler-safe)
#
# Unlock detection is HYBRID:
#   • Signal-driven: listens to GameState.quest_step_changed, episode_completed,
#     room_discovered, kino_changed, etc. and evaluates predicate functions.
#   • Direct: gameplay code can call Achievements.unlock("id") for one-shot scripted
#     beats that don't map to a clean world-state signal (e.g. returning from a planet).
#
# Predicate evaluation: each achievement has an optional check Callable stored in
# _checkers[id] that reads live GameState/NPCState/Inventory world-state and returns
# bool. Called on every relevant signal. This mirrors the QuestLog hybrid pattern.
#
# Save integration: registered as the "achievements" ISaveableSystem in SaveManager.
# Saves store { unlocked: Array[String], notified: Array[String] } so the player
# sees each achievement notification exactly once per playthrough, even across
# save/load cycles.

signal achievement_unlocked(id: String, title: String, description: String)
signal progress_changed(unlocked_count: int, total_count: int, percentage: float)

const ACHIEVEMENTS_PATH: String = "res://data/achievements.json"

# Loaded definitions: id -> { id, title, description, category, hidden }
var _definitions: Dictionary = {}
# Ordered id list (for stable iteration / display order).
var _ordered_ids: Array[String] = []
# Unlocked achievement ids.
var _unlocked: Dictionary = {}  # id -> true
# Ids whose notification toast has already been shown (so a save/load cycle
# doesn't re-toast everything). Cleared only by reset().
var _notified: Dictionary = {}  # id -> true

# Predicate callables: id -> Callable -> bool. Populated in _ready from the
# _register_checkers() method below. Each checker reads live world-state.
var _checkers: Dictionary = {}

var _initialized: bool = false


func _ready() -> void:
	_ensure_initialized()
	# Register with SaveManager (autoload-tolerant for headless -s tests).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "achievements", self)
	# Connect to GameState signals for predicate-driven unlocks.
	var gs: Node = _autoload_node("GameState")
	if gs != null:
		if gs.has_signal("quest_step_changed") and not gs.quest_step_changed.is_connected(_on_quest_step_changed):
			gs.quest_step_changed.connect(_on_quest_step_changed)
		if gs.has_signal("episode_completed") and not gs.episode_completed.is_connected(_on_episode_completed):
			gs.episode_completed.connect(_on_episode_completed)
		if gs.has_signal("room_discovered") and not gs.room_discovered.is_connected(_on_room_discovered):
			gs.room_discovered.connect(_on_room_discovered)
		if gs.has_signal("kino_changed") and not gs.kino_changed.is_connected(_on_kino_changed):
			gs.kino_changed.connect(_on_kino_changed)


# Idempotent lazy init — same pattern as QuestLog. Ensures headless -s tests
# that instantiate Achievements directly (no _ready frame yet) still load defs.
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_definitions()
	_register_checkers()


func _load_definitions() -> void:
	var f: FileAccess = FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.READ)
	if f == null:
		push_error("Achievements: cannot open %s" % ACHIEVEMENTS_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		push_error("Achievements: %s did not parse to an array" % ACHIEVEMENTS_PATH)
		return
	for entry in parsed:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var aid: String = String(d.get("id", ""))
		if aid == "":
			continue
		_definitions[aid] = d
		_ordered_ids.append(aid)


# --- Checker registration ----------------------------------------------------
# Each checker reads live world-state from GameState / NPCState / Inventory.
# Checkers are CALLED (not data) because they read arbitrary world state — same
# design rationale as QuestLog's predicate ladder.

func _register_checkers() -> void:
	_checkers["first_gate_dial"] = Callable(self, "_check_first_gate_dial")
	_checkers["first_planet"] = Callable(self, "_check_first_planet")
	_checkers["sealed_breach"] = Callable(self, "_check_sealed_breach")
	_checkers["crew_met"] = Callable(self, "_check_crew_met")
	_checkers["episode_air"] = Callable(self, "_check_episode_air")
	_checkers["explorer_10"] = Callable(self, "_check_explorer_10")
	_checkers["kino_master"] = Callable(self, "_check_kino_master")
	_checkers["lime_miner"] = Callable(self, "_check_lime_miner")
	_checkers["scrubber_repair"] = Callable(self, "_check_scrubber_repair")
	_checkers["gate_runner"] = Callable(self, "_check_gate_runner")
	_checkers["room_catalog"] = Callable(self, "_check_room_catalog")
	_checkers["power_restored"] = Callable(self, "_check_power_restored")


# --- Checkers ----------------------------------------------------------------

func _check_first_gate_dial() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and int(gs.get("planets_dialed")) >= 1


func _check_first_planet() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("returned_from_lime_planet") == true


func _check_sealed_breach() -> bool:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return false
	var sealed: Array = gs.get("breaches_sealed")
	return not sealed.is_empty()


func _check_crew_met() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("met_scott") == true and gs.get("met_rush") == true


func _check_episode_air() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("episode_complete") == true


func _check_explorer_10() -> bool:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return false
	var rooms: Array = gs.get("rooms_discovered")
	return rooms.size() >= 10


func _check_kino_master() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("kino_scout_done") == true


func _check_lime_miner() -> bool:
	var inv: Node = _autoload_node("Inventory")
	if inv == null:
		return false
	return inv.call("count", "lime") > 0


func _check_scrubber_repair() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("scrubber_repaired") == true


func _check_gate_runner() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("returned_from_lime_planet") == true and int(gs.get("planets_dialed")) >= 1


func _check_room_catalog() -> bool:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return false
	var rooms: Array = gs.get("rooms_discovered")
	return rooms.size() >= 20


func _check_power_restored() -> bool:
	var gs: Node = _autoload_node("GameState")
	return gs != null and gs.get("elevator_repaired") == true


# --- Signal handlers ---------------------------------------------------------

func _on_quest_step_changed(_step: String) -> void:
	_evaluate_all()


func _on_episode_completed() -> void:
	_evaluate_all()


func _on_room_discovered(_room_id: String) -> void:
	_evaluate_all()


func _on_kino_changed(_acquired: bool) -> void:
	_evaluate_all()


# Evaluate every checker and unlock any newly-satisfied achievements.
func _evaluate_all() -> void:
	_ensure_initialized()
	for aid in _ordered_ids:
		if _unlocked.has(aid):
			continue
		if not _checkers.has(aid):
			continue
		var checker: Callable = _checkers[aid]
		if checker.call():
			_do_unlock(aid)


# --- Public API --------------------------------------------------------------

# Direct unlock for scripted beats. Idempotent. Returns true if this call
# actually unlocked it (false = already unlocked or unknown id).
func unlock(aid: String) -> bool:
	_ensure_initialized()
	if _unlocked.has(aid):
		return false
	if not _definitions.has(aid):
		push_warning("Achievements: unknown id '%s'" % aid)
		return false
	_do_unlock(aid)
	return true


func _do_unlock(aid: String) -> void:
	_unlocked[aid] = true
	var d: Dictionary = _definitions.get(aid, {})
	var title: String = String(d.get("title", aid))
	var desc: String = String(d.get("description", ""))
	achievement_unlocked.emit(aid, title, desc)
	_emit_progress()


# True if the achievement is unlocked.
func is_unlocked(aid: String) -> bool:
	return _unlocked.has(aid)


# Number of unlocked achievements.
func unlocked_count() -> int:
	return _unlocked.size()


# Total number of defined achievements.
func total_count() -> int:
	return _ordered_ids.size()


# Progress as a 0..100 float.
func progress_percentage() -> float:
	var total: int = total_count()
	if total == 0:
		return 0.0
	return float(unlocked_count()) / float(total) * 100.0


# "5/12" style string for UI display.
func progress_text() -> String:
	return "%d/%d" % [unlocked_count(), total_count()]


# Returns the full definition dict for an achievement id, or {} if unknown.
# Description is masked ("???") for hidden + locked achievements so the HUD can
# safely display it without spoiler leaks.
func get_definition(aid: String) -> Dictionary:
	if not _definitions.has(aid):
		return {}
	var d: Dictionary = _definitions[aid].duplicate(true)
	if d.get("hidden", false) == true and not _unlocked.has(aid):
		d["description"] = "???"
	return d


# Returns all definitions (ordered), with hidden descriptions masked for
# locked achievements. For the achievements list UI.
func all_definitions() -> Array[Dictionary]:
	_ensure_initialized()
	var out: Array[Dictionary] = []
	for aid in _ordered_ids:
		out.append(get_definition(aid))
	return out


# True if the notification toast has been shown for this achievement.
func is_notified(aid: String) -> bool:
	return _notified.has(aid)


# Mark that the notification toast was shown. Called by the HUD after the toast
# finishes its animation so a save/load cycle doesn't re-toast.
func mark_notified(aid: String) -> void:
	_notified[aid] = true


# Returns achievements that are unlocked but not yet notified (toast pending).
# The HUD calls this on _ready to show any toasts that fired during a save/load.
func pending_notifications() -> Array[String]:
	var out: Array[String] = []
	for aid in _unlocked.keys():
		if not _notified.has(aid):
			out.append(String(aid))
	return out


# Reset to clean state — called on New Game via GameState.reset() consumers.
func reset() -> void:
	_unlocked.clear()
	_notified.clear()
	_emit_progress()


# --- Save integration (ISaveableSystem) --------------------------------------

func serialize() -> Dictionary:
	return {
		"unlocked": _unlocked.keys().duplicate(),
		"notified": _notified.keys().duplicate(),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_unlocked.clear()
	_notified.clear()
	var raw_unlocked: Variant = data.get("unlocked", [])
	if raw_unlocked is Array:
		for id in (raw_unlocked as Array):
			_unlocked[String(id)] = true
	var raw_notified: Variant = data.get("notified", [])
	if raw_notified is Array:
		for id in (raw_notified as Array):
			_notified[String(id)] = true
	_emit_progress()


# --- Helpers -----------------------------------------------------------------

func _emit_progress() -> void:
	progress_changed.emit(unlocked_count(), total_count(), progress_percentage())


func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)