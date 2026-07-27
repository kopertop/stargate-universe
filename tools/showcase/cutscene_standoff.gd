extends Node3D

# E1 standoff cutscene — recorded with Movie Maker from the REAL control
# interface room: Rush at his console, Greer charges in and levels his pistol,
# Scott arrives to stand him down. Dialogue rendered as cinematic captions
# (the in-game dialog UI pauses the tree, so the cutscene drives the
# choreography directly through the same actor APIs).
#   godot --path . --write-movie out/raw/standoff.avi --fixed-fps 30 \
#     tools/showcase/cutscene_standoff.tscn

const FactoryRef: Script = preload("res://scripts/character_factory.gd")

var _t: float = 0.0
var _events: Array = []
var _cam: Camera3D
var _caption: Label
var _speaker: Label
var _card: Label
var _overlay: ColorRect
var _rush: Node3D
var _greer: Node3D
var _scott: Node3D
var _cam_from: Transform3D
var _cam_to: Transform3D
var _cam_t0: float = 0.0
var _cam_dur: float = 0.0
var _walkers: Array = []   # [node, target, speed]


func _ready() -> void:
	var room: Node = (load("res://scenes/room.tscn") as PackedScene).instantiate()
	# Boot the room as the control interface room with no quest side effects.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("reset")
		gs.set("next_room_id", "control_interface_room")
	add_child(room)
	# Cinematic: hide the gameplay HUD and the player avatar.
	var hud_layer: Node = _find_named(room, "HUDLayer")
	if hud_layer != null and hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	var player: Node = _find_named(room, "Player")
	if player != null and player is Node3D:
		(player as Node3D).position = Vector3(0, -50, 0)   # out of shot
	_build_actors()
	_build_overlay()
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true
	_script_events()


func _process(delta: float) -> void:
	_t += delta
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var ev: Array = _events.pop_front()
		(ev[1] as Callable).call()
	if _cam_dur > 0.0:
		var a: float = clampf((_t - _cam_t0) / _cam_dur, 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)
		_cam.global_transform = _cam_from.interpolate_with(_cam_to, a)
	# Simple deterministic walkers (Movie Maker fixed steps).
	for w in _walkers:
		var node: Node3D = w[0]
		var target: Vector3 = w[1]
		var speed: float = w[2]
		var to_go: Vector3 = target - node.position
		to_go.y = 0.0
		if to_go.length() > 0.08:
			node.position += to_go.normalized() * minf(speed * delta, to_go.length())
			node.rotation.y = atan2(-to_go.normalized().x, -to_go.normalized().z) + PI
	_walkers = _walkers.filter(func(w: Array) -> bool:
		var d: Vector3 = (w[1] as Vector3) - (w[0] as Node3D).position
		d.y = 0.0
		return d.length() > 0.08)


# Spawn our own cinematic actors (independent of the room's quest NPCs, which
# we hide so the stage is clean).
func _build_actors() -> void:
	for hide_name in ["DrRush", "SgtGreer", "ColonelYoung", "StandoffGreer", "StandoffScott"]:
		var n: Node = _find_named(self, hide_name)
		if n != null and n is Node3D:
			(n as Node3D).visible = false
			if n.has_method("set"):
				n.set("enabled", false)
	_rush = _spawn("Dr Rush", Vector3(8.4, 0.0, -0.4), PI * 0.5)
	_mc(_rush).call("play_clip", "idle_arms_folded")
	_greer = _spawn("Sgt Greer", Vector3(1.6, 0.0, 3.2), -PI * 0.4)
	_greer.visible = false
	_scott = _spawn("Lt Scott", Vector3(0.6, 0.0, 4.6), -PI * 0.4)
	_scott.visible = false


func _spawn(character_name: String, pos: Vector3, yaw: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	add_child(holder)
	var mc: Node3D = FactoryRef.build_modular(character_name)
	mc.rotation.y = PI
	holder.add_child(mc)
	FactoryRef.dress_modular(mc, character_name, FactoryRef.CTX_SHIP)
	holder.set_meta("mc", mc)
	return holder


func _mc(holder: Node3D) -> Node3D:
	return holder.get_meta("mc")


func _build_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.02, 0.03, 0.05, 1.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 40)
	layer.add_child(_card)
	_speaker = Label.new()
	_speaker.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_speaker.offset_top = -130.0
	_speaker.offset_bottom = -100.0
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.add_theme_font_size_override("font_size", 20)
	_speaker.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	_speaker.add_theme_color_override("font_outline_color", Color.BLACK)
	_speaker.add_theme_constant_override("outline_size", 8)
	layer.add_child(_speaker)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -100.0
	_caption.offset_bottom = -42.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 25)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(_caption)
	# Cinematic letterbox bars.
	for top in [true, false]:
		var bar: ColorRect = ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.offset_bottom = 64.0
		else:
			bar.offset_top = -64.0
		layer.add_child(bar)
		layer.move_child(bar, 0)


func _at(t: float, fn: Callable) -> void:
	_events.append([t, fn])


func _line(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_caption.text = "\"%s\"" % text


func _script_events() -> void:
	_card.text = "DESTINY — CONTROL INTERFACE ROOM\nEpisode 1: Air"
	# Establishing shot: slow push-in on Rush at the console.
	_at(2.5, func() -> void:
		_overlay.visible = false
		_card.visible = false
		_move_cam(Vector3(4.2, 2.0, 3.6), _rush.position + Vector3(0, 1.25, 0),
			Vector3(6.2, 1.5, 1.6), _rush.position + Vector3(0, 1.25, 0), 4.5))
	_at(4.0, func() -> void: _line("Dr Rush", "I don't have time for this. Go be useful somewhere else."))
	# Greer charges in — camera pulls wide so the charge crosses the frame.
	_at(7.0, func() -> void:
		_greer.visible = true
		_walkers.append([_greer, Vector3(6.6, 0.0, 0.6), 3.2])
		_mc(_greer).call("play_clip", "rifle_walk")
		_move_cam(Vector3(6.2, 1.5, 1.6), _rush.position + Vector3(0, 1.25, 0),
			Vector3(4.6, 1.8, 5.0), Vector3(5.4, 1.0, 0.8), 1.8))
	_at(7.2, func() -> void: _line("Sgt Greer", "Step away from the console. NOW."))
	_at(9.8, func() -> void:
		_mc(_greer).call("set_sidearm", true, true)
		_mc(_greer).call("play_clip", "pistol_aim")
		_mc(_rush).call("play_clip", "talk"))
	# Over-the-shoulder two-shot: Greer aiming, Rush unmoved.
	_at(10.2, func() -> void:
		_move_cam(Vector3(4.6, 1.8, 5.0), Vector3(5.4, 1.0, 0.8),
			Vector3(5.2, 1.55, 2.4), Vector3(7.6, 1.2, -0.2), 2.0)
		_line("Dr Rush", "Sergeant. Pointing that at me won't recalculate the CO2 scrubbers."))
	# Scott runs in behind them.
	_at(13.5, func() -> void:
		_scott.visible = true
		_walkers.append([_scott, Vector3(5.0, 0.0, 1.8), 4.0])
		_mc(_scott).call("play_clip", "run")
		_move_cam(Vector3(5.2, 1.55, 2.4), Vector3(7.6, 1.2, -0.2),
			Vector3(8.2, 1.8, 3.2), Vector3(4.6, 1.1, 1.8), 2.2)
		_line("Lt Scott", "GREER! Stand down — that's an ORDER!"))
	_at(16.0, func() -> void:
		_mc(_scott).call("play_clip", "talk"))
	# Stand-down: pistol back to the holster.
	_at(17.5, func() -> void:
		_mc(_greer).call("set_sidearm", true, false)
		_mc(_greer).call("play_clip", "idle")
		_line("Sgt Greer", "...This isn't over."))
	_at(20.0, func() -> void:
		_mc(_rush).call("play_clip", "idle_arms_folded")
		_move_cam(Vector3(8.2, 1.8, 3.2), Vector3(4.6, 1.1, 1.8),
			Vector3(3.8, 2.3, 4.8), Vector3(6.4, 1.1, 0.4), 4.0)
		_line("Dr Rush", "If we don't fix the air... none of this will matter."))
	_at(24.5, func() -> void:
		_overlay.visible = true
		_card.visible = true
		_speaker.text = ""
		_caption.text = ""
		_card.text = "STARGATE UNIVERSE")
	_at(27.0, func() -> void: get_tree().quit())


func _move_cam(from_pos: Vector3, from_look: Vector3, to_pos: Vector3, to_look: Vector3, dur: float) -> void:
	_cam.position = from_pos
	_cam.look_at(from_look, Vector3.UP)
	_cam_from = _cam.global_transform
	_cam.position = to_pos
	_cam.look_at(to_look, Vector3.UP)
	_cam_to = _cam.global_transform
	_cam.global_transform = _cam_from
	_cam_t0 = _t
	_cam_dur = dur


func _find_named(node: Node, target: String) -> Node:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == target:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
