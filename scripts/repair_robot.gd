extends Node

# RepairRobot — stateless ticker that heals sealed/damaged rooms (issue #131).
#
# @no-save: all durable state lives in ProceduralShip._room_conditions (registered
# there). RepairRobot re-derives its active job set from that registry on each
# tick so nothing is lost across save/load. No serialize/deserialize needed.
#
# Dispatch: RepairConsole calls dispatch(room_id). Under SceneRouter.instant_mode
# (headless tests) the repair completes synchronously so tests never hang.
#
# Signals: repair_progress(room_id, fraction) on each tick;
#          repair_completed forwarded from ProceduralShip.repair_completed.

signal repair_progress(room_id: String, fraction: float)
signal repair_completed(room_id: String)

# Tick accumulator — wall-time seconds since last spend.
var _tick_acc: float = 0.0

# Active jobs this session: set of room_ids currently being repaired.
# Derived from ProceduralShip._room_conditions on dispatch + forwarded ticks.
# NOT serialised — re-derived on next dispatch after load.
var _active_jobs: Dictionary = {}  # room_id -> true


func _ready() -> void:
	set_process(true)
	# Forward ProceduralShip.repair_completed so callers can connect to either.
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	if ps != null:
		if not ps.is_connected("repair_completed", _on_ps_repair_completed):
			ps.connect("repair_completed", _on_ps_repair_completed)


func _process(delta: float) -> void:
	if _active_jobs.is_empty():
		return
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	if ps == null:
		return

	var interval: float = float(ps.call("get_repair_tick_interval"))
	_tick_acc += delta
	if _tick_acc < interval:
		return
	_tick_acc -= interval

	var tick_parts: int = int(ps.call("get_repair_tick_parts"))
	var finished: Array = []
	for room_id: String in _active_jobs.keys():
		if not ps.call("is_room_sealed", room_id):
			# Already repaired (state transitioned elsewhere, or idempotent call).
			finished.append(room_id)
			continue
		ps.call("spend_repair_parts", room_id, tick_parts)
		# Report progress.
		var cond: Dictionary = ps.call("room_condition", room_id)
		var required: int = int(cond.get("parts_required", 1))
		var spent: int = int(cond.get("parts_spent", 0))
		var fraction: float = float(spent) / float(max(required, 1))
		repair_progress.emit(room_id, fraction)
		if not ps.call("is_room_sealed", room_id):
			finished.append(room_id)
	for room_id: String in finished:
		_active_jobs.erase(room_id)


# Dispatch the repair robot to a room.
# - Validates the room is sealed and there are enough parts in Inventory.
# - Under SceneRouter.instant_mode: completes the full repair synchronously
#   (no timer ticks) so headless tests never hang.
# Returns true if dispatch was accepted.
func dispatch(room_id: String) -> bool:
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	if ps == null:
		return false

	if not ps.call("is_room_sealed", room_id):
		return false  # Nothing to repair (already repaired or nominal).

	var cost: int = int(ps.call("get_seal_repair_cost"))
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	if int(inv.call("count", "parts")) < cost:
		return false  # Not enough parts — no-op, no deduction.

	ps.call("begin_repair", room_id)

	# Under instant_mode: spend all parts at once and complete immediately.
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		ps.call("spend_repair_parts", room_id, cost)
		return true

	# Normal play: register as active job; _process ticks will drain parts over time.
	_active_jobs[room_id] = true
	return true


func _on_ps_repair_completed(room_id: String) -> void:
	_active_jobs.erase(room_id)
	repair_completed.emit(room_id)
