extends Node

# Data-driven quest runtime. Replaces the hand-maintained if-ladder that used
# to live in GameState. Loads ordered step definitions from data/quests.json
# and exposes the same surface the HUD / Kino map / in-world diamonds used to
# read off GameState (objective text, active step id, target anchor, label).
#
# Hybrid advance rule (issue #36):
#   A step is COMPLETE  ⟺  step.id ∈ completed_steps        (event)
#                       OR  _evaluate_predicate(step.complete_when) == true
#   active_step(quest) = first step, in order, that is NOT complete
#
# That keeps the system robust to save/reload + out-of-order events (today's
# strength of the predicate ladder) while still allowing scripted beats that
# don't map to a clean world-state flag to advance via complete_step().
#
# Predicates are NOT data — they read arbitrary world-state on GameState, so
# they stay in code. Adding a new predicate = adding a `match` arm here, then
# referencing it by string from data/quests.json. Same for the handful of
# steps with dynamic objective text (seal_breach today).
#
# Save-game contract: this autoload registers as the "quest_log" ISaveableSystem
# in SaveManager, so progress rides along with the rest of the snapshot. The
# step ids are intentionally identical to the old QUEST_* string constants —
# every reader that does `quest_step == GameState.QUEST_X` keeps working, and
# old saves with a top-level "quest_step" string survive migration because the
# active step is re-derived from world-state flags on load.

signal quest_step_changed(quest_id: String, step_id: String)
signal quest_completed(quest_id: String)

const QUESTS_PATH: String = "res://data/quests.json"

# Loaded definitions: quest_id -> { id, title, auto_start, tracked, steps[] }.
# Steps are stored as ordered Arrays so the active-step search is O(N) over a
# tiny N (18 for E1) — no need for index maps.
var _quests: Dictionary = {}

# Live progress: quest_id -> {
#   "started":         bool,
#   "completed_steps": Array[String],   # event-completed step ids
#   "active":          String,          # cached active step id (derived)
# }
var _progress: Dictionary = {}

# The single "tracked" quest the HUD displays. Set by the first quest with
# `tracked = true` in the JSON; reassignable later if we add quest-switching.
var _tracked_quest_id: String = ""

var _loaded: bool = false


func _ready() -> void:
	_ensure_initialized()
	# D5: start the post-E1 exploration quest when Episode 1 completes.
	# Connect after init so GameState is available; guard against double-connect.
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_signal("episode_completed"):
		if not gs.episode_completed.is_connected(_on_episode_completed):
			gs.episode_completed.connect(_on_episode_completed)


# Idempotent lazy init. Run from _ready for normal autoload boot AND from
# every public entry point so headless `-s` SceneTree tests work: in `-s`
# mode `_ready()` is deferred until a frame ticks (see
# feedback_godot_scenetree_script_gotchas memory), so a test that does
# `root.add_child(ql)` followed by `gs.advance_air_quest()` without
# awaiting a frame would otherwise hit an empty `_quests` dictionary.
var _initialized: bool = false
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_quests()
	# Autoload-tolerant: e1_flow / quest_waypoint / quest_log smoke tests
	# instantiate QuestLog directly under their SceneTree root with no
	# SaveManager registered, so register only when SaveManager exists.
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "quest_log", self)
	for quest_id in _quests.keys():
		var q: Dictionary = _quests[quest_id]
		if q.get("auto_start", false) == true:
			start_quest(quest_id)


# Same pattern as GameState._autoload_node: prefer the registered autoload,
# fall back to a same-named sibling so headless test scripts can wire their
# own GameState + QuestLog pair under the test's root.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# --- JSON load ---------------------------------------------------------------

func _load_quests() -> void:
	if _loaded:
		return
	var f: FileAccess = FileAccess.open(QUESTS_PATH, FileAccess.READ)
	if f == null:
		push_error("QuestLog: cannot open %s" % QUESTS_PATH)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		push_error("QuestLog: %s did not parse to an array" % QUESTS_PATH)
		return
	for entry in parsed:
		if not (entry is Dictionary):
			continue
		var qd: Dictionary = entry
		var quest_id: String = String(qd.get("id", ""))
		if quest_id == "":
			continue
		_quests[quest_id] = qd
		if qd.get("tracked", false) == true and _tracked_quest_id == "":
			_tracked_quest_id = quest_id
	_loaded = true


# --- Public API --------------------------------------------------------------

# Register a quest as started. Idempotent. A no-op if the id is unknown.
# Sets initial active step + emits quest_step_changed for the HUD.
func start_quest(quest_id: String) -> void:
	_ensure_initialized()
	if not _quests.has(quest_id):
		return
	if not _progress.has(quest_id):
		_progress[quest_id] = {
			"started": true,
			"completed_steps": [],
			"active": "",
		}
	(_progress[quest_id] as Dictionary)["started"] = true
	advance(quest_id)


# Hybrid advance: re-derive the active step. Call after any world-state
# mutation that could satisfy a predicate. `quest_id = ""` advances every
# started quest (useful at boot / after a save load).
func advance(quest_id: String = "") -> void:
	_ensure_initialized()
	if quest_id == "":
		for qid in _progress.keys():
			_advance_one(String(qid))
		return
	_advance_one(quest_id)


# Mark a specific step complete via the event channel. Idempotent. Use this
# for beats that don't have a clean world-state predicate — e.g. a scripted
# transition the player triggers on a one-shot interaction. Auto-advances.
func complete_step(quest_id: String, step_id: String) -> void:
	_ensure_initialized()
	if not _progress.has(quest_id):
		return
	var prog: Dictionary = _progress[quest_id]
	var done: Array = prog.get("completed_steps", [])
	if not done.has(step_id):
		done.append(step_id)
		prog["completed_steps"] = done
	advance(quest_id)


# Active step id of the tracked quest (or of the named one). "" if no
# quest is tracked / started.
func active_step_id(quest_id: String = "") -> String:
	_ensure_initialized()
	var qid: String = _resolve_quest_id(quest_id)
	if qid == "":
		return ""
	var prog: Dictionary = _progress.get(qid, {})
	return String(prog.get("active", ""))


# Full objective text for the active step. Dynamic via objective_fn when a
# step opts in, otherwise the static `objective` field.
func objective(quest_id: String = "") -> String:
	_ensure_initialized()
	var qid: String = _resolve_quest_id(quest_id)
	if qid == "":
		return ""
	var step: Dictionary = _active_step(qid)
	if step.is_empty():
		return ""
	var fn_key: String = String(step.get("objective_fn", ""))
	if fn_key != "":
		return _evaluate_objective_fn(fn_key)
	return String(step.get("objective", ""))


# Display title of the tracked quest (or of the named one). "" if no quest
# is tracked / known. Drives the WoW-style quest tracker header (#66).
func title(quest_id: String = "") -> String:
	_ensure_initialized()
	var qid: String = _resolve_quest_id(quest_id)
	if qid == "" or not _quests.has(qid):
		return ""
	return String((_quests[qid] as Dictionary).get("title", ""))


# Id of the quest the HUD currently tracks. "" until a tracked quest loads.
func tracked_quest_id() -> String:
	_ensure_initialized()
	return _tracked_quest_id


# Anchor for the in-world quest diamond. {} when off-ship / hidden.
func target(quest_id: String = "") -> Dictionary:
	_ensure_initialized()
	var qid: String = _resolve_quest_id(quest_id)
	if qid == "":
		return {}
	var step: Dictionary = _active_step(qid)
	if step.is_empty():
		return {}
	var t: Variant = step.get("target", {})
	if t is Dictionary:
		return t
	return {}


# Anchor for a specific step id, regardless of which step is active. Used
# by the quest_waypoint smoke test which asserts static target wiring for
# steps the player may not currently be on. Returns {} when the step id
# isn't found in any registered quest.
func target_for_step(step_id: String) -> Dictionary:
	_ensure_initialized()
	if step_id == "":
		return {}
	for qid in _quests.keys():
		var q: Dictionary = _quests[qid]
		for s in (q.get("steps", []) as Array):
			if s is Dictionary and String((s as Dictionary).get("id", "")) == step_id:
				var t: Variant = (s as Dictionary).get("target", {})
				if t is Dictionary:
					return t
				return {}
	return {}


# Short HUD label for a step id (or the active step when key=="").
func label(step_id: String = "") -> String:
	_ensure_initialized()
	# Without a step id, return the active tracked step's label.
	if step_id == "":
		var step: Dictionary = _active_step(_tracked_quest_id)
		if step.is_empty():
			return ""
		return String(step.get("label", ""))
	# Otherwise search every quest for a matching id.
	for qid in _quests.keys():
		var q: Dictionary = _quests[qid]
		var steps: Array = q.get("steps", [])
		for s in steps:
			if s is Dictionary and String((s as Dictionary).get("id", "")) == step_id:
				return String((s as Dictionary).get("label", step_id))
	return step_id


# True when the quest's active step is its terminal step (or all steps done).
func is_complete(quest_id: String) -> bool:
	if not _quests.has(quest_id):
		return false
	var step: Dictionary = _active_step(quest_id)
	if step.is_empty():
		return false
	return step.get("terminal", false) == true


# All started, non-complete quest ids — the multi-quest tracker (#66) iterates
# this to render N quests under the minimap. Follows the one-registry pattern
# (collection-fork lint): a single pass over `_progress`, no per-quest bools.
# Order is insertion order of `_progress` (auto_start order), which is stable
# across save/load because deserialize() preserves the saved quest order.
func active_quests() -> Array[String]:
	_ensure_initialized()
	var out: Array[String] = []
	for qid in _progress.keys():
		var prog: Dictionary = _progress[qid]
		if prog.get("started", false) == true and not is_complete(String(qid)):
			out.append(String(qid))
	return out


# --- Internals ---------------------------------------------------------------

func _resolve_quest_id(quest_id: String) -> String:
	if quest_id != "":
		return quest_id
	return _tracked_quest_id


func _active_step(quest_id: String) -> Dictionary:
	if not _quests.has(quest_id):
		return {}
	var prog: Dictionary = _progress.get(quest_id, {})
	var active_id: String = String(prog.get("active", ""))
	if active_id == "":
		return {}
	for s in (_quests[quest_id] as Dictionary).get("steps", []):
		if s is Dictionary and String((s as Dictionary).get("id", "")) == active_id:
			return s
	return {}


func _advance_one(quest_id: String) -> void:
	if not _quests.has(quest_id) or not _progress.has(quest_id):
		return
	var quest: Dictionary = _quests[quest_id]
	var prog: Dictionary = _progress[quest_id]
	var done: Array = prog.get("completed_steps", [])
	var steps: Array = quest.get("steps", [])
	var new_active: String = ""
	for s in steps:
		if not (s is Dictionary):
			continue
		var step: Dictionary = s
		var sid: String = String(step.get("id", ""))
		if sid == "":
			continue
		if done.has(sid):
			continue
		# Terminal steps stay active once reached — they have no predicate.
		if step.get("terminal", false) == true:
			new_active = sid
			break
		var predicate_key: String = String(step.get("complete_when", ""))
		if predicate_key != "" and _evaluate_predicate(predicate_key):
			# Predicate satisfied → fold into completed_steps so future
			# advances don't re-evaluate. Keeps re-derive cheap + makes the
			# save snapshot a complete record of progress.
			if not done.has(sid):
				done.append(sid)
				prog["completed_steps"] = done
			continue
		new_active = sid
		break
	# All steps done with no terminal marker? Fall through to last step.
	if new_active == "" and not steps.is_empty():
		var last: Variant = steps.back()
		if last is Dictionary:
			new_active = String((last as Dictionary).get("id", ""))
	var prev_active: String = String(prog.get("active", ""))
	prog["active"] = new_active
	if new_active != prev_active:
		quest_step_changed.emit(quest_id, new_active)
		if is_complete(quest_id):
			quest_completed.emit(quest_id)


# Read arbitrary world-state on GameState. Adding a new predicate = adding
# an arm here + referencing the key from data/quests.json.
#
# Looking GameState up by name (rather than the bare autoload global)
# keeps this evaluator autoload-tolerant: -s SceneTree test scripts can
# instantiate GameState as a same-named sibling under their tree root
# (see tests/smoke/e1_flow.gd) without the predicate code blowing up on
# an unbound global identifier.
func _evaluate_predicate(key: String) -> bool:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return false
	match key:
		"met_scott":
			return gs.met_scott
		"met_rush":
			return gs.met_rush
		"eli_quarters_visited":
			return gs.eli_quarters_visited
		"kino_acquired":
			return Inventory.has("kino_remote")
		"air_crisis_started":
			return gs.air_crisis_started
		"control_room_returned":
			return gs.control_room_returned
		"life_support_diagnosed":
			return gs.life_support_diagnosed
		"any_breach_sealed":
			return not (gs.breaches_sealed as Array).is_empty()
		"scrubber_diagnosed":
			return gs.scrubber_diagnosed
		"ftl_drop_triggered":
			return gs.ftl_drop_triggered
		"reported_to_gate":
			return gs.reported_to_gate
		"has_kino_orb_or_scouted":
			# fetch_kino completes once the player either picks up a Kino orb
			# (kino_orbs > 0) OR has already done the scout (kino_scout_done).
			# The second branch keeps the step from re-activating after the
			# Kino is launched into the gate (orbs goes back to 0 mid-scout).
			return Inventory.count("kino_orb") > 0 or gs.kino_scout_done
		"kino_scout_done":
			return gs.kino_scout_done
		"lime_planet_dialed":
			return gs.lime_planet_dialed
		"has_required_lime":
			return gs.has_resource(gs.AIR_LIME_RESOURCE, gs.AIR_LIME_REQUIRED)
		"returned_from_lime_planet":
			return gs.returned_from_lime_planet
		"scrubber_repaired_or_episode_complete":
			# Old ladder had a defensive `if episode_complete or scrubber_repaired`
			# early-exit. Preserve the same semantics here so the final step's
			# completion never gates on the wrong flag combination.
			return gs.scrubber_repaired or gs.episode_complete
		"floor_unlocked_beyond_2":
			# D5: true once any floor >= 3 is unlocked via ProceduralShip.
			var ps: Node = _autoload_node("ProceduralShip")
			if ps == null:
				return false
			# Check floors 3..10 for any that are unlocked.
			for fn: int in range(3, 11):
				if ps.call("is_floor_unlocked", fn):
					return true
			return false
		"engineering_found":
			return gs.get("engineering_found") == true
		"junction_located":
			return gs.get("junction_located") == true
		"junction_repaired":
			return gs.get("junction_repaired") == true
		"power_routed":
			return gs.get("power_routed") == true
		"nebula_trap_detected":
			return gs.get("nebula_trap_detected") == true
		"power_conservation_started":
			return gs.get("power_conservation_started") == true
		"planet_resources_collected":
			return gs.get("planet_resources_collected") == true
		"nebula_escape_complete":
			return gs.get("nebula_escape_complete") == true
		_:
			push_warning("QuestLog: unknown predicate '%s'" % key)
			return false


# Dynamic objective text for the handful of steps whose copy depends on
# fine-grained world-state (currently just seal_breach's three sub-goals).
# Same autoload-tolerance pattern as _evaluate_predicate above.
func _evaluate_objective_fn(key: String) -> String:
	var gs: Node = _autoload_node("GameState")
	if gs == null:
		return ""
	match key:
		"seal_breach_objective":
			if not gs.door_panel_examined:
				return "A jammed shuttle door is venting atmosphere in the Shuttle Dock (far south). Get to the door panel and try it."
			if not Inventory.has("small_fuse"):
				return "The door panel's fuse is blown. Search the Shuttle Dock crates for a Small Fuse."
			return "Fit the Small Fuse into the door panel to force the jammed door shut."
		_:
			push_warning("QuestLog: unknown objective_fn '%s'" % key)
			return ""


# --- Save round-trip ---------------------------------------------------------
#
# Snapshot shape:
#   {
#     "tracked": "e1_air",
#     "quests": {
#       "e1_air": { "started": true, "completed_steps": [...] }
#     }
#   }
# Active is not persisted — it's re-derived from completed_steps +
# predicates on load (see deserialize → advance below). That keeps old
# saves compatible: a save with no "quests" block still hydrates by
# re-evaluating predicates against the loaded GameState flags.

func serialize() -> Dictionary:
	var quests_block: Dictionary = {}
	for qid in _progress.keys():
		var prog: Dictionary = _progress[qid]
		quests_block[qid] = {
			"started": prog.get("started", false),
			"completed_steps": (prog.get("completed_steps", []) as Array).duplicate(),
		}
	return {
		"tracked": _tracked_quest_id,
		"quests": quests_block,
	}


func deserialize(data: Dictionary, _version: int) -> void:
	# Wipe live progress first. auto_start re-seeds the started flag below.
	_progress.clear()
	var saved_tracked: String = String(data.get("tracked", ""))
	if saved_tracked != "":
		_tracked_quest_id = saved_tracked
	var quests_block: Variant = data.get("quests", {})
	if quests_block is Dictionary:
		for qid in (quests_block as Dictionary).keys():
			var entry: Variant = quests_block[qid]
			if not (entry is Dictionary):
				continue
			var saved_done: Variant = (entry as Dictionary).get("completed_steps", [])
			var done_list: Array = []
			if saved_done is Array:
				for s in saved_done:
					done_list.append(String(s))
			_progress[String(qid)] = {
				"started": (entry as Dictionary).get("started", true),
				"completed_steps": done_list,
				"active": "",
			}
	# Auto-start quests the save didn't record (handles old saves with no
	# "quests" block at all + future quests added after the save was written).
	for quest_id in _quests.keys():
		var q: Dictionary = _quests[quest_id]
		if q.get("auto_start", false) == true and not _progress.has(quest_id):
			_progress[quest_id] = {
				"started": true,
				"completed_steps": [],
				"active": "",
			}
	# Now re-derive active steps for every progress entry. This is the
	# old-save migration: completed_steps may be empty but predicate-based
	# advance will fold every satisfied step in.
	advance("")


# D5: fired by GameState.episode_completed when E1 finishes. Starts the
# post-E1 exploration quest and switches the HUD to track it.
func _on_episode_completed() -> void:
	start_quest("e2_explore")
	_tracked_quest_id = "e2_explore"
	advance("e2_explore")


# Wipe progress so a fresh game starts at step 1 of every auto_start quest.
# Called from GameState.reset().
func reset() -> void:
	_ensure_initialized()
	_progress.clear()
	# Re-wire the episode_completed listener in case GameState reconnects.
	var gs: Node = _autoload_node("GameState")
	if gs != null and gs.has_signal("episode_completed"):
		if not gs.episode_completed.is_connected(_on_episode_completed):
			gs.episode_completed.connect(_on_episode_completed)
	for quest_id in _quests.keys():
		var q: Dictionary = _quests[quest_id]
		if q.get("auto_start", false) == true:
			start_quest(quest_id)
