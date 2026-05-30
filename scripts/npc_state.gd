extends Node

# Per-NPC persisted state. Keyed by NPC node name (a stable id as long as
# the scene's NPC nodes aren't renamed in the editor — rare). Each entry
# captures dialogue progress (_line_index), the auto_greet completion
# flag, and current position/yaw so resume restores both conversation
# state AND in-world placement (relevant once an NPC has finished
# walking up to the player).
#
# npc.gd hooks: _ready() calls NPCState.restore_or_register(self); any
# mutation that advances state (line advance, met flag flip, auto_greet
# finish) calls NPCState.update(self).
#
# Registered as the "npc_state" ISaveableSystem, so the dict rides along
# in the SaveManager snapshot.

var _states: Dictionary = {}


func _ready() -> void:
	SaveManager.register_system("npc_state", self)


# Called from npc.gd._ready(). If we have stored state for this NPC,
# apply it and return true; otherwise capture initial values and return
# false. Caller can branch on the return when it needs to know whether
# the NPC is fresh-spawned vs. resumed.
func restore_or_register(npc: Node) -> bool:
	var id: String = npc.name
	if not _states.has(id):
		update(npc)
		return false
	if npc.has_method("apply_save_state"):
		npc.call("apply_save_state", _states[id])
	return true


func update(npc: Node) -> void:
	if not npc.has_method("get_save_state"):
		return
	var snapshot: Variant = npc.call("get_save_state")
	if snapshot is Dictionary:
		_states[npc.name] = snapshot


func reset() -> void:
	_states.clear()


func serialize() -> Dictionary:
	return {"npcs": _states.duplicate(true)}


func deserialize(data: Dictionary, _version: int) -> void:
	_states.clear()
	var raw: Variant = data.get("npcs", {})
	if raw is Dictionary:
		for key in (raw as Dictionary).keys():
			var v: Variant = (raw as Dictionary)[key]
			if v is Dictionary:
				_states[String(key)] = (v as Dictionary).duplicate(true)
