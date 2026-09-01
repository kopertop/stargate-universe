extends Node

# @no-save: composite container — delegates to InjurySystem (self-registers
# with SaveManager) and MedBay (@no-save). Holds no state of its own.
# HealthSystem — unified autoload that merges two health-related systems:
#   • InjurySystem — no-death knockout → injury registry
#   • MedBay       — med-bay recovery loop companion
#
# Each original script is instantiated as a named child so callers can reach
# them at /root/HealthSystem/InjurySystem and /root/HealthSystem/MedBay.
# Back-compat: _autoload_node("InjurySystem") callers try
# /root/HealthSystem/InjurySystem first, then fall back to /root/InjurySystem.

func _ready() -> void:
	_add_child_script("InjurySystem", "res://scripts/injury_system.gd")
	_add_child_script("MedBay", "res://scripts/med_bay.gd")

func _add_child_script(node_name: String, script_path: String) -> void:
	var script: GDScript = load(script_path)
	if script == null:
		push_warning("HealthSystem: could not load %s" % script_path)
		return
	var node: Node = Node.new()
	node.set_name(node_name)
	node.set_script(script)
	add_child(node)