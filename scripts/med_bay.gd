extends Node

# @no-save: Recovery state is ephemeral — restored from InjurySystem on load.

# Med-Bay recovery loop (issue #148). The companion to InjurySystem: once a
# recoverable injury is registered, the MedBay accepts the patient, runs a
# time-based recovery countdown scaled by injury severity, emits TJ dialog
# lines during the recovery, and on completion flips the InjurySystem record
# to recovered (emitting recovery_complete).
#
# Lives as an autoload (MedBay) so the infirmary scene and HUD can reach one
# shared processor. Autoload-tolerant: headless `-s` SceneTree tests can
# instantiate this directly under their root and it resolves InjurySystem by
# name, matching the pattern used by QuestLog.
#
# Recovery duration model (issue #148 spec): injury severity → recovery
# duration. A minor knock (severity 0.1) is a quick once-over; a near-fatal
# hit (severity 0.84) is a long stay. Base + per-severity scaling, clamped to
# a sane ceiling so the loop never stalls the game.

signal recovery_started(character_id: String)
signal recovery_finished(character_id: String)

# Recovery duration (seconds) = BASE + severity * PER_SEVERITY, clamped to MAX.
# At severity 0.0 → 8 s; at 0.5 → 23 s; at 0.84 → 33.6 s; ceiling 40 s.
const RECOVERY_BASE_SECONDS: float = 8.0
const RECOVERY_PER_SEVERITY: float = 30.0
const RECOVERY_MAX_SECONDS: float = 40.0

# TJ's bedside dialog during recovery. Picked semi-randomly per tick so a
# long stay isn't one repeated line. Issue #148 calls these out explicitly.
const TJ_LINES: Array[String] = [
	"Can you move your fingers?",
	"We'll get it in a sling.",
	"Are you okay?",
	"Easy. Breathe. You're back aboard Destiny.",
	"Hold still — I need to check that.",
	"You gave us a scare, but you'll mend.",
]

# Interval between TJ lines (seconds). Keeps the bedside chatter from spamming.
const TJ_LINE_INTERVAL: float = 5.0

# character_id → live recovery state:
#   { "remaining": float, "line_timer": float, "duration": float }
var _recoveries: Dictionary = {}

var _initialized: bool = false


func _ready() -> void:
	set_process(false)  # Only tick when recoveries are active — see begin_recovery.
	_ensure_initialized()


func _process(delta: float) -> void:
	if _recoveries.is_empty():
		return
	var done_ids: Array[String] = []
	for cid in _recoveries.keys():
		var state: Dictionary = _recoveries[cid]
		var remaining: float = float(state.get("remaining", 0.0)) - delta
		state["remaining"] = remaining
		var line_timer: float = float(state.get("line_timer", 0.0)) - delta
		state["line_timer"] = line_timer
		_recoveries[cid] = state
		if line_timer <= 0.0:
			_emit_tj_line(cid)
			state["line_timer"] = TJ_LINE_INTERVAL
			_recoveries[cid] = state
		if remaining <= 0.0:
			done_ids.append(String(cid))
	for cid in done_ids:
		_finish_recovery(cid)


# Idempotent lazy init — autoloads AND headless `-s` test scripts both reach
# this on first public call. Mirrors InjurySystem._ensure_initialized.
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true


# Same autoload-tolerant lookup as GameState._autoload_node.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _injury_system() -> Node:
	return _autoload_node("InjurySystem")


func _gs() -> Node:
	return _autoload_node("GameState")


# --- Public API ------------------------------------------------------------

# Begin recovery for `character_id`. Only succeeds if the InjurySystem has a
# RECOVERABLE injury for this character that isn't already recovering/done.
# Returns true if recovery was started (or was already in progress); false if
# the injury is FATAL, missing, already recovered, or recovery is already running.
func begin_recovery(character_id: String) -> bool:
	_ensure_initialized()
	var isys: Node = _injury_system()
	if isys == null:
		return false
	# Already recovering here — idempotent.
	if _recoveries.has(character_id):
		return true
	# Must be a registered, recoverable injury not yet recovered.
	if not isys.call("has_injury", character_id):
		return false
	if not isys.call("is_recoverable", character_id):
		return false
	if isys.call("is_recovered", character_id):
		return false
	# Arm the injury as recovering in the InjurySystem.
	if not isys.call("attempt_recovery", character_id):
		return false
	var rec: Dictionary = isys.call("injury", character_id)
	var severity: float = float(rec.get("severity", 0.0))
	var duration: float = clampf(
		RECOVERY_BASE_SECONDS + severity * RECOVERY_PER_SEVERITY,
		RECOVERY_BASE_SECONDS,
		RECOVERY_MAX_SECONDS
	)
	_recoveries[character_id] = {
		"remaining": duration,
		"line_timer": 0.0,  # fire a line immediately
		"duration": duration,
	}
	set_process(true)
	recovery_started.emit(character_id)
	# Emit the opening TJ line right away.
	_emit_tj_line(character_id)
	_recoveries[character_id]["line_timer"] = TJ_LINE_INTERVAL
	return true


# Force-finish a recovery (e.g. instant_mode tests, debug skip). Flips the
# InjurySystem record to recovered and clears the live state. Returns false
# if there's no active recovery for this character.
func finish_now(character_id: String) -> bool:
	if not _recoveries.has(character_id):
		return false
	_finish_recovery(character_id)
	return true


# Cancel an in-progress recovery without marking it recovered (e.g. player
# leaves the infirmary early). Clears local state only; the InjurySystem
# record keeps its recovering flag so a later return can resume.
func cancel_recovery(character_id: String) -> void:
	_recoveries.erase(character_id)
	if _recoveries.is_empty():
		set_process(false)


# Recovery duration (seconds) the MedBay would use for a given severity.
# Exposed so HUD/tests can show the countdown without beginning recovery.
func recovery_duration(severity: float) -> float:
	return clampf(
		RECOVERY_BASE_SECONDS + severity * RECOVERY_PER_SEVERITY,
		RECOVERY_BASE_SECONDS,
		RECOVERY_MAX_SECONDS
	)


# Remaining seconds for an active recovery, or -1.0 if none.
func remaining_seconds(character_id: String) -> float:
	if not _recoveries.has(character_id):
		return -1.0
	return float((_recoveries[character_id] as Dictionary).get("remaining", 0.0))


# True if a recovery countdown is currently ticking for this character.
func is_recovering(character_id: String) -> bool:
	return _recoveries.has(character_id)


func clear_all() -> void:
	_recoveries.clear()
	set_process(false)


# --- Internals -------------------------------------------------------------

func _finish_recovery(character_id: String) -> void:
	_recoveries.erase(character_id)
	if _recoveries.is_empty():
		set_process(false)
	var isys: Node = _injury_system()
	if isys != null and isys.has_method("complete_recovery"):
		isys.call("complete_recovery", character_id)
	recovery_finished.emit(character_id)


# Emit a TJ bedside line via GameState.narrative_added (the narrative channel
# that drives the HUD Chat panel) + dialogue_shown (the sci-fi dialog panel).
# Falls back to a plain print in headless contexts where GameState is absent.
func _emit_tj_line(character_id: String) -> void:
	var line: String = TJ_LINES[randi() % TJ_LINES.size()]
	var gs: Node = _gs()
	if gs != null and gs.has_method("say"):
		# say(speaker, text) emits narrative_added("TJ", line) → HUD Chat panel.
		gs.call("say", "TJ", line)
	if gs != null and gs.has_signal("dialogue_shown"):
		gs.call("emit_signal", "dialogue_shown", "TJ", line)
	else:
		print("TJ: %s" % line)