extends Node

# EpisodeManager — data-driven multi-episode progression system.
#
# Loads episode definitions from data/episodes.json and tracks which episode
# is active, which are completed, and transitions to the next episode when
# the current one's completion predicate is satisfied. Each episode links to
# a quest chain in data/quests.json via its `quest_id`.
#
# Single source of truth for episode progression. GameState's
# `current_episode` / `episode_complete` vars are kept in sync for backward
# compatibility; the `episode_completed` signal on GameState is re-emitted
# by EpisodeManager so existing listeners (EpisodeWrap, SaveManager,
# QuestLog) keep working.
#
# Save contract: registers as the "episode_manager" ISaveableSystem in
# SaveManager. Serializes the current episode id + the set of completed
# episode ids.

signal episode_started(episode_id: String)
signal episode_completed(episode_id: String)
signal all_episodes_completed()

const EPISODES_PATH: String = "res://data/episodes.json"

# Loaded definitions: episode_id -> { id, title, quest_id, auto_start,
# completion_predicate, next_episode_id }.
var _episodes: Dictionary = {}

# Ordered list of episode ids (preserves JSON array order for numbering).
var _episode_order: Array[String] = []

# The currently active episode id. "" before the first episode starts.
var _current_episode_id: String = ""

# Set of completed episode ids.
var _completed_episodes: Array[String] = []

var _loaded: bool = false
var _initialized: bool = false
# Re-entrancy guard: set while complete_episode() is emitting the legacy
# GameState.episode_completed signal so _on_game_state_episode_completed
# doesn't double-complete the next episode.
var _completing: bool = false


func _ready() -> void:
	_ensure_initialized()
	# Register with SaveManager (autoload-tolerant for -s SceneTree tests).
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "episode_manager", self)
	# Listen for GameState's legacy episode_completed signal so any code
	# path that still fires it (e.g. complete_episode_air) is caught here
	# and routed through the general-purpose system.
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_signal("episode_completed"):
		if not gs.episode_completed.is_connected(_on_game_state_episode_completed):
			gs.episode_completed.connect(_on_game_state_episode_completed)


# Idempotent lazy init. Run from _ready AND from every public entry point
# so headless `-s` SceneTree tests work without awaiting a frame.
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_episodes()
	# Auto-start the first episode if none is active (fresh game).
	if _current_episode_id == "" and not _episode_order.is_empty():
		var first_id: String = _episode_order[0]
		var ep: Dictionary = _episodes[first_id]
		if ep.get("auto_start", false) == true:
			_start_episode_internal(first_id)


# Same pattern as GameState._autoload_node / QuestLog._autoload_node.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# --- JSON load ---------------------------------------------------------------

func _load_episodes() -> void:
	if _loaded:
		return
	_loaded = true
	var f: FileAccess = FileAccess.open(EPISODES_PATH, FileAccess.READ)
	if f == null:
		push_error("EpisodeManager: cannot open %s" % EPISODES_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		push_error("EpisodeManager: %s did not parse to an array" % EPISODES_PATH)
		return
	for entry in parsed:
		if not (entry is Dictionary):
			continue
		var ed: Dictionary = entry
		var ep_id: String = String(ed.get("id", ""))
		if ep_id == "":
			continue
		_episodes[ep_id] = ed
		_episode_order.append(ep_id)


# --- Public API --------------------------------------------------------------

# The currently active episode id. "" before the first episode starts.
func current_episode_id() -> String:
	_ensure_initialized()
	return _current_episode_id


# Human-readable title of the current episode. "" if none is active.
func current_episode_title() -> String:
	_ensure_initialized()
	if _current_episode_id == "" or not _episodes.has(_current_episode_id):
		return ""
	return String((_episodes[_current_episode_id] as Dictionary).get("title", ""))


# 1-based episode number of the current episode. 0 if none is active.
func current_episode_number() -> int:
	_ensure_initialized()
	if _current_episode_id == "":
		return 0
	return _episode_order.find(_current_episode_id) + 1


# Total number of defined episodes.
func total_episodes() -> int:
	_ensure_initialized()
	return _episode_order.size()


# True if the named episode has been completed.
func is_episode_complete(episode_id: String) -> bool:
	return _completed_episodes.has(episode_id)


# Start an episode by id. Sets it as current, starts its quest chain via
# QuestLog, and emits episode_started. Idempotent — re-starting an already
# active episode is a no-op. An unknown id is a safe no-op.
func start_episode(episode_id: String) -> void:
	_ensure_initialized()
	_start_episode_internal(episode_id)


# Internal start — does NOT call _ensure_initialized (callers do that).
func _start_episode_internal(episode_id: String) -> void:
	if episode_id == "":
		return
	if not _episodes.has(episode_id):
		return
	if _current_episode_id == episode_id:
		return  # already active
	_current_episode_id = episode_id
	# Sync GameState's legacy vars. Note: episode_complete is NOT reset
	# here — it's a one-shot "has an episode been completed" flag that
	# stays true until reset(). The original complete_episode_air() set
	# it to true and never cleared it mid-game.
	var gs: Node = _autoload_node("GameState")
	if gs != null:
		gs.set("current_episode", episode_id)
	# Start the quest chain for this episode via QuestLog.
	var ep: Dictionary = _episodes[episode_id]
	var quest_id: String = String(ep.get("quest_id", ""))
	if quest_id != "":
		var ql: Node = _autoload_node("QuestLog")
		if ql != null and ql.has_method("start_quest"):
			ql.call("start_quest", quest_id)
			# Track this quest in QuestLog's HUD tracker. The _tracked_quest_id
			# field is set directly (QuestLog has no setter method).
			ql.set("_tracked_quest_id", quest_id)
	episode_started.emit(episode_id)


# Complete an episode by id. Marks it done, emits episode_completed, fires
# the GameState legacy signal, and auto-starts the next episode if one
# exists. If this was the last episode, emits all_episodes_completed.
# Idempotent — completing an already-completed episode is a no-op.
func complete_episode(episode_id: String) -> void:
	_ensure_initialized()
	if episode_id == "":
		return
	if not _episodes.has(episode_id):
		return
	if _completed_episodes.has(episode_id):
		return
	_completed_episodes.append(episode_id)
	# Sync GameState's legacy vars.
	var gs: Node = _autoload_node("GameState")
	if gs != null:
		gs.set("episode_complete", true)
		gs.set("current_episode", episode_id)
		# Re-emit the legacy signal so EpisodeWrap / SaveManager / QuestLog
		# listeners that still connect to GameState.episode_completed fire.
		if gs.has_signal("episode_completed"):
			# Guard against re-entrancy: _on_game_state_episode_completed
			# listens to this signal and would try to complete the next
			# episode. Set the guard so it no-ops.
			_completing = true
			gs.emit_signal("episode_completed")
			_completing = false
	episode_completed.emit(episode_id)
	# Auto-start the next episode if one is defined.
	var next_id: String = next_episode_id_for(episode_id)
	if next_id != "":
		_start_episode_internal(next_id)
	else:
		all_episodes_completed.emit()


# Returns the next episode id after the given episode, or "" if none.
func next_episode_id_for(episode_id: String) -> String:
	_ensure_initialized()
	if not _episodes.has(episode_id):
		return ""
	var ep: Dictionary = _episodes[episode_id]
	return String(ep.get("next_episode_id", ""))


# Returns the next episode id after the CURRENT episode, or "" if none.
func next_episode_id() -> String:
	_ensure_initialized()
	return next_episode_id_for(_current_episode_id)


# Evaluate the completion predicate for the given episode against
# GameState world-state. Returns true if the predicate is satisfied.
func check_completion(episode_id: String) -> bool:
	_ensure_initialized()
	if not _episodes.has(episode_id):
		return false
	if _completed_episodes.has(episode_id):
		return true
	var ep: Dictionary = _episodes[episode_id]
	var predicate: String = String(ep.get("completion_predicate", ""))
	if predicate == "":
		return false
	return _evaluate_predicate(predicate)


# Evaluate the current episode's completion predicate and complete the
# episode if it's satisfied. This is the main polling entry point —
# GameState.check_episode_complete() delegates here.
func check_current_episode_complete() -> void:
	_ensure_initialized()
	if _current_episode_id == "":
		return
	if _completed_episodes.has(_current_episode_id):
		return
	if check_completion(_current_episode_id):
		complete_episode(_current_episode_id)


# Evaluate a completion predicate string against GameState world-state.
# Adding a new predicate = adding a `match` arm here. Same pattern as
# QuestLog._evaluate_predicate.
func _evaluate_predicate(key: String) -> bool:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return false
	match key:
		"scrubber_repaired":
			return gs.scrubber_repaired
		"floor_unlocked_beyond_2":
			# D5: true once any floor >= 3 is unlocked via ProceduralShip.
			var ps: Node = _autoload_node("ProceduralShip")
			if ps == null:
				return false
			for fn: int in range(3, 11):
				if ps.call("is_floor_unlocked", fn):
					return true
			return false
		"water_system_online":
			# Placeholder for E3 — not yet implemented.
			return false
		"darkness_resolved":
			# Placeholder for E4 — not yet implemented.
			return false
		"earth_contact_made":
			# Placeholder for E5 — not yet implemented.
			return false
		"all_life_missions_done":
			# E6: true when all three personal story missions are completed.
			# Check both GameState mirror vars and LifeMissions autoload.
			var all_done: bool = gs.tj_mission_done and gs.camille_mission_done and gs.greer_mission_done
			if not all_done:
				var lm: Node = _autoload_node("LifeMissions")
				if lm != null and lm.has_method("all_missions_done"):
					all_done = lm.call("all_missions_done")
			return all_done
		_:
			push_warning("EpisodeManager: unknown predicate '%s'" % key)
			return false


# Callback for GameState's legacy episode_completed signal. When GameState
# fires episode_completed (e.g. from complete_episode_air fallback path or
# any other code that still emits the signal directly), we route it through
# the general-purpose system by marking the current episode complete.
# The _completing guard prevents re-entrancy when complete_episode() itself
# fires the GameState signal.
func _on_game_state_episode_completed() -> void:
	if _completing:
		return
	_ensure_initialized()
	if _current_episode_id == "":
		return
	if _completed_episodes.has(_current_episode_id):
		return
	# The legacy signal fired — mark the current episode complete.
	# Don't re-emit GameState.episode_completed (it already fired).
	_completed_episodes.append(_current_episode_id)
	episode_completed.emit(_current_episode_id)
	var next_id: String = next_episode_id_for(_current_episode_id)
	if next_id != "":
		_start_episode_internal(next_id)
	else:
		all_episodes_completed.emit()


# --- Save round-trip (ISaveableSystem) ---------------------------------------

func serialize() -> Dictionary:
	return {
		"current_episode_id": _current_episode_id,
		"completed_episodes": _completed_episodes.duplicate(),
	}


func deserialize(data: Dictionary, _version: int) -> void:
	_completed_episodes.clear()
	var saved_completed: Variant = data.get("completed_episodes", [])
	if saved_completed is Array:
		for ep_id in saved_completed:
			_completed_episodes.append(String(ep_id))
	var saved_current: String = String(data.get("current_episode_id", ""))
	if saved_current != "" and _episodes.has(saved_current):
		_current_episode_id = saved_current
	else:
		# Fresh save or old save without episode_manager block: auto-start
		# the first episode (or none if already completed all).
		_current_episode_id = ""
		if not _episode_order.is_empty():
			var first_id: String = _episode_order[0]
			if not _completed_episodes.has(first_id):
				var ep: Dictionary = _episodes[first_id]
				if ep.get("auto_start", false) == true:
					_current_episode_id = first_id
	# Sync GameState's legacy vars.
	var gs: Node = _autoload_node("GameState")
	if gs != null:
		gs.set("current_episode", _current_episode_id)
		gs.set("episode_complete", not _completed_episodes.is_empty())


# Wipe state so a fresh game starts at episode 1. Called from
# GameState.reset() (which calls EpisodeManager.reset() if present).
func reset() -> void:
	_ensure_initialized()
	_completed_episodes.clear()
	_current_episode_id = ""
	# Auto-start the first episode if it has auto_start.
	if not _episode_order.is_empty():
		var first_id: String = _episode_order[0]
		var ep: Dictionary = _episodes[first_id]
		if ep.get("auto_start", false) == true:
			_start_episode_internal(first_id)
	# Sync GameState's legacy vars.
	var gs: Node = _autoload_node("GameState")
	if gs != null:
		gs.set("current_episode", _current_episode_id)
		gs.set("episode_complete", false)