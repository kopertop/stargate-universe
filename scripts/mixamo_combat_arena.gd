extends Node3D

# Mixamo combat arena bootstrap: enable combat look, keep HUD optional.

const _DEMO_CAPTURE: Script = preload("res://scripts/demo_capture.gd")


func _ready() -> void:
	var player: Node = get_node_or_null("Player")
	var view: Node = get_node_or_null("View")
	if view != null and view.has_method("set_combat_look"):
		view.call("set_combat_look", true)
	elif view != null and "combat_look" in view:
		view.set("combat_look", true)
	if player != null and player.has_method("set_input_locked"):
		player.call("set_input_locked", false)
	# Movie Maker / capture demos must not steal the host OS cursor.
	if bool(_DEMO_CAPTURE.is_demo_capture(get_tree())):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Subtle bed for arena play (same MusicDirector as ship rooms).
	var md: Node = get_node_or_null("/root/MusicDirector")
	if md != null and md.has_method("set_mood"):
		md.call("set_mood", "ship_calm", 0.5)
