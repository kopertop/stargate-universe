class_name ConduitJunction
extends Interactable

# Ancient conduit junction interactable for the E2 "Light" power-restoration
# puzzle sequence. A single interactable advances through four stages:
#   Stage 0 (LOCATE) — "Examine conduit junction" → sets junction_located
#   Stage 1 (REPAIR) — "Repair conduit junction"  → sets junction_repaired
#   Stage 2 (ROUTE)  — "Route power to critical rooms" → sets power_routed
#   Stage 3 (DONE)   — disabled, prompt = "Power distribution complete."
#
# The first interact also sets engineering_found if not already set, so the
# player discovering the junction in the aft storage hall flags engineering
# discovery too.
#
# PowerGrid integration: the REPAIR stage calls PowerGrid.repair_generator()
# to restore generator output. The ROUTE stage calls repair_generator() again
# plus clears overrides/section damage on critical rooms so power flows to
# gate_room and control_interface_room.

enum Stage { LOCATE, REPAIR, ROUTE, DONE }

const PROMPTS: Array[String] = [
	"Examine conduit junction",
	"Repair conduit junction",
	"Route power to critical rooms",
	"Power distribution complete.",
]

var _stage: int = Stage.LOCATE


func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_sync_stage()


# Re-derive prompt + enabled from _stage. Called from _ready and by tests
# that create bare .new() instances (no tree → _ready does not fire).
func _sync_stage() -> void:
	if _stage >= Stage.DONE:
		enabled = false
		prompt = PROMPTS[Stage.DONE]
	else:
		enabled = true
		prompt = PROMPTS[_stage]


func _on_interact(_by: Node) -> void:
	match _stage:
		Stage.LOCATE:
			# First discovery: flag engineering found + junction located.
			if not GameState.engineering_found:
				GameState.mark_engineering_found()
			GameState.mark_junction_located()
			_stage = Stage.REPAIR
		Stage.REPAIR:
			GameState.mark_junction_repaired()
			_stage = Stage.ROUTE
		Stage.ROUTE:
			GameState.mark_power_routed()
			_stage = Stage.DONE
		Stage.DONE:
			# No-op: puzzle already complete.
			pass
	_sync_stage()