extends Npc

# Dr Rush during the E1 cold-open standoff (#136). The FIRST meeting plays as
# a real cutscene — letterbox, Space-advanced captions, the charge/aim/
# stand-down choreography under the StandoffCamera — instead of a WoW dialog
# window: the standoff offers no real choices, it's a scene that happens TO
# the player. Repeat talks AND instant_mode (headless suites) route through
# the classic dialog path, so the e1 tests keep exercising the same tree.

# Wired by room.gd to its cinematic runner; receives this NPC's dialogue tree.
var standoff_runner: Callable = Callable()


func _on_interact(by: Node) -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	var instant: bool = sr != null and bool(sr.get("instant_mode"))
	if instant or _has_met() or not standoff_runner.is_valid():
		super(by)
		return
	# Mirror the dialog path's first-meet bookkeeping: the met flag flips
	# synchronously BEFORE the scene plays (the playthrough asserts this
	# contract right after interact()). Rush deliberately does NOT turn from
	# his console — everyone is yelling at his back, which IS the scene.
	if _line_index == 0:
		_handle_first_meet()
	_line_index += 1
	_notify_npc_state_update()
	standoff_runner.call(dialogue_tree)
