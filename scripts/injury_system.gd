extends Node

# No-Death Knockout → Med-Bay Recovery Loop (issue #148).
#
# Wraps the existing GameState.knock_out() recovery beat with a structured
# injury registry: every knockout is tagged with a cause (enum) and a
# RECOVERABLE/FATAL tag, so the MedBay knows which injuries it can process
# and which are terminal (a FATAL injury still routes through knock_out but
# is never handed to the recovery loop — it ends the run outright).
#
# Lives as an autoload (InjurySystem) so scene scripts, hazard zones, and the
# MedBay can all reach one shared registry. Autoload-tolerant: headless
# `-s` SceneTree tests can instantiate this directly under their root and it
# resolves GameState by name, matching the pattern used by QuestLog.
#
# Save-game contract: registers as the "injury_system" ISaveableSystem so the
# injury registry rides along with the rest of the save snapshot.

# --- Causes (knockout origin) ----------------------------------------------
# FALL        — long drop / missed ledge (recoverable).
# IMPACT      — struck by debris / door / kinetic trap (recoverable).
# SUFFOCATION — oxygen depletion / toxic atmosphere (recoverable; the E1 case).
# HOSTILE     — alien defense fauna / hostile NPC (recoverable, mostly).
# DEPLOYMENT  — gate-window recall cut too close (recoverable; the window_closed case).
enum InjuryCause { FALL, IMPACT, SUFFOCATION, HOSTILE, DEPLOYMENT }

# --- Tag (outcome) ---------------------------------------------------------
# RECOVERABLE — MedBay can process it (time-based recovery → back on feet).
# FATAL       — run-ending; routed through knock_out() but never to MedBay.
enum InjuryTag { RECOVERABLE, FATAL }

# Severity ≥ this is fatal. Below it the injury is recoverable; the MedBay
# uses the severity (0.0–1.0) to scale recovery duration.
const FATAL_SEVERITY_THRESHOLD: float = 0.85

# Map of InjuryCause → string tag used by GameState.knock_out(cause). The
# existing data file (data/knockout_lines.json) keys its TJ line pools off
# these exact strings, so translating the enum to the legacy string keeps
# the wake-up line pick working without touching the data.
const CAUSE_STRINGS: Dictionary = {
	InjuryCause.FALL: "fall",
	InjuryCause.IMPACT: "trap",
	InjuryCause.SUFFOCATION: "asphyxiation",
	InjuryCause.HOSTILE: "alien_defense",
	InjuryCause.DEPLOYMENT: "window_closed",
}

signal injury_registered(cause: InjuryCause, tag: InjuryTag)
signal recovery_complete(character_id: String)

# character_id → Injury record:
#   {
#     "cause":      InjuryCause,
#     "tag":        InjuryTag,
#     "severity":   float,        # 0.0–1.0
#     "cause_str":  String,      # legacy tag for GameState.knock_out
#     "recovering": bool,        # true once MedBay accepted it
#     "recovered":  bool,        # true once MedBay finished it
#   }
var _injuries: Dictionary = {}

var _initialized: bool = false


func _ready() -> void:
	_ensure_initialized()


# Idempotent lazy init — autoloads AND headless `-s` test scripts both reach
# this on first public call. Mirrors QuestLog._ensure_initialized.
func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	var sm: Node = _autoload_node("SaveManager")
	if sm != null and sm.has_method("register_system"):
		sm.call("register_system", "injury_system", self)


# Same autoload-tolerant lookup as GameState._autoload_node.
func _autoload_node(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


func _gs() -> Node:
	return _autoload_node("GameState")


# --- Public API ------------------------------------------------------------

# Register a knockout injury for `character_id`. `severity` is 0.0–1.0; at or
# above FATAL_SEVERITY_THRESHOLD the injury is FATAL (run-ending), otherwise
# RECOVERABLE. Routes the player through GameState.knock_out(cause_str) so the
# existing infirmary / resource-reconcile / heal-to-full beat fires unchanged.
# Returns the InjuryTag so callers (MedBay, HUD) can branch on recoverable vs
# fatal without re-deriving.
func register_injury(character_id: String, cause: InjuryCause, severity: float) -> InjuryTag:
	_ensure_initialized()
	var clamped: float = clampf(severity, 0.0, 1.0)
	var tag: InjuryTag = InjuryTag.FATAL if clamped >= FATAL_SEVERITY_THRESHOLD else InjuryTag.RECOVERABLE
	var cause_str: String = CAUSE_STRINGS.get(cause, "generic")
	_injuries[character_id] = {
		"cause": cause,
		"tag": tag,
		"severity": clamped,
		"cause_str": cause_str,
		"recovering": false,
		"recovered": false,
	}
	injury_registered.emit(cause, tag)
	# Delegate the actual downed beat to the existing GameState path so the
	# infirmary routing, resource forfeit, and heal-to-full all still fire.
	var gs: Node = _gs()
	if gs != null and gs.has_method("knock_out"):
		gs.call("knock_out", cause_str)
	return tag


# Attempt to begin recovery for `character_id`. Only RECOVERABLE injuries that
# haven't already been recovered (and aren't currently recovering) are eligible.
# The MedBay calls this when it accepts a patient. Returns true if recovery was
# armed (or was already armed); false if the injury is FATAL, missing, or done.
func attempt_recovery(character_id: String) -> bool:
	_ensure_initialized()
	if not _injuries.has(character_id):
		return false
	var rec: Dictionary = _injuries[character_id]
	var tag: int = int(rec.get("tag", InjuryTag.FATAL))
	if tag == InjuryTag.FATAL:
		return false
	if bool(rec.get("recovered", false)):
		return false
	# Mark as armed — the MedBay drives the time-based countdown; we just
	# gate eligibility and signal completion when it tells us it's done.
	rec["recovering"] = true
	_injuries[character_id] = rec
	return true


# Called by the MedBay when its time-based recovery countdown elapses for
# `character_id`. Flips the injury to recovered and emits recovery_complete.
# No-op (returns false) for FATAL or already-recovered injuries.
func complete_recovery(character_id: String) -> bool:
	_ensure_initialized()
	if not _injuries.has(character_id):
		return false
	var rec: Dictionary = _injuries[character_id]
	var tag: int = int(rec.get("tag", InjuryTag.FATAL))
	if tag == InjuryTag.FATAL:
		return false
	if bool(rec.get("recovered", false)):
		return false
	rec["recovered"] = true
	rec["recovering"] = false
	_injuries[character_id] = rec
	recovery_complete.emit(character_id)
	return true


# --- Read accessors --------------------------------------------------------

func has_injury(character_id: String) -> bool:
	return _injuries.has(character_id)


func injury(character_id: String) -> Dictionary:
	return _injuries.get(character_id, {})


func injury_tag(character_id: String) -> InjuryTag:
	if not _injuries.has(character_id):
		return InjuryTag.FATAL
	return int((_injuries[character_id] as Dictionary).get("tag", InjuryTag.FATAL)) as InjuryTag


func is_recoverable(character_id: String) -> bool:
	return injury_tag(character_id) == InjuryTag.RECOVERABLE


func is_fatal(character_id: String) -> bool:
	return injury_tag(character_id) == InjuryTag.FATAL


func is_recovered(character_id: String) -> bool:
	if not _injuries.has(character_id):
		return false
	return bool((_injuries[character_id] as Dictionary).get("recovered", false))


func is_recovering(character_id: String) -> bool:
	if not _injuries.has(character_id):
		return false
	return bool((_injuries[character_id] as Dictionary).get("recovering", false))


func clear(character_id: String) -> void:
	_injuries.erase(character_id)


func clear_all() -> void:
	_injuries.clear()


# --- Save round-trip -------------------------------------------------------

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for cid in _injuries.keys():
		var rec: Dictionary = _injuries[cid]
		out[cid] = {
			"cause": int(rec.get("cause", 0)),
			"tag": int(rec.get("tag", 0)),
			"severity": float(rec.get("severity", 0.0)),
			"cause_str": String(rec.get("cause_str", "")),
			"recovering": bool(rec.get("recovering", false)),
			"recovered": bool(rec.get("recovered", false)),
		}
	return {"injuries": out}


func deserialize(data: Dictionary, _version: int) -> void:
	_injuries.clear()
	var saved: Variant = data.get("injuries", {})
	if not (saved is Dictionary):
		return
	for cid in (saved as Dictionary).keys():
		var entry: Variant = (saved as Dictionary)[cid]
		if not (entry is Dictionary):
			continue
		var rec: Dictionary = entry
		_injuries[String(cid)] = {
			"cause": int(rec.get("cause", 0)),
			"tag": int(rec.get("tag", 0)),
			"severity": float(rec.get("severity", 0.0)),
			"cause_str": String(rec.get("cause_str", "")),
			"recovering": bool(rec.get("recovering", false)),
			"recovered": bool(rec.get("recovered", false)),
		}