class_name KinoPageKinoControl
extends Node

# Handheld Kino fleet control. Available once you hold an orb or have a Kino
# deployed in the field. Lets you launch a new Kino and take control of ANY
# live Kino at any time — including ones left on the planet.
# The action list is rebuilt each refresh since the deployed set changes.

const KinoDroneScript: Script = preload("res://scripts/kino_drone.gd")
const KINO_LAUNCH_HEIGHT: float = 1.6   # spawn the orb above the player's hands

var _coordinator: Node
var _page: Control

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "KinoControl"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 12)
	parent.add_child(_page)
	_label(_page, "KINO CONTROL", 16, Color(0.55, 0.85, 1.0, 1.0))
	var desc: Label = _label(_page, "—", 14, Color(0.85, 0.92, 1.0, 0.95))
	desc.name = "KinoControlDesc"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(HSeparator.new())
	_label(_page, "  Kinos in hand:  —", 14, Color.WHITE).name = "KinoControlCount"
	var list: VBoxContainer = VBoxContainer.new()
	list.name = "KinoActionList"
	list.add_theme_constant_override("separation", 8)
	_page.add_child(list)
	return _page

func refresh() -> void:
	var desc: Label = _page.get_node_or_null("KinoControlDesc") as Label
	var count: Label = _page.get_node_or_null("KinoControlCount") as Label
	var list: VBoxContainer = _page.get_node_or_null("KinoActionList") as VBoxContainer
	if desc != null:
		desc.text = "Launch a Kino to scout, or take control of any Kino you've left out in the field — wherever it is."
	if count != null:
		count.text = "  Kinos in hand:  %d / %d" % [Inventory.count("kino_orb"), GameState.KINO_ORB_MAX]
	if list == null:
		return
	for c in list.get_children():
		c.queue_free()
	if Inventory.count("kino_orb") > 0:
		var launch: Button = _kino_action_button("LAUNCH NEW KINO", true)
		launch.pressed.connect(_on_launch_kino)
		list.add_child(launch)
	_label(list, "  Live Kinos:", 13, Color(0.55, 0.85, 1.0, 0.85))
	if GameState.deployed_kinos.is_empty():
		_label(list, "    (none deployed)", 13, Color(0.7, 0.75, 0.85, 0.8))
	else:
		for i in range(GameState.deployed_kinos.size()):
			var k: Dictionary = GameState.deployed_kinos[i]
			var loc: String = _scene_short_name(String(k.get("scene", "")))
			var b: Button = _kino_action_button("PILOT KINO %d  —  %s" % [i + 1, loc], false)
			b.pressed.connect(_on_pilot_deployed.bind(i))
			list.add_child(b)

func is_available() -> bool:
	return Inventory.count("kino_orb") > 0 or not GameState.deployed_kinos.is_empty()

# Spend a carried orb and dive into a fresh Kino, launched right where the player
# stands (Eli stays put, holding the remote). In the gate room the player flies
# it through the active Stargate to reach the planet.
func _on_launch_kino() -> void:
	if Inventory.count("kino_orb") <= 0:
		return
	if not GameState.consume_kino_orb():
		return
	Audio.play("res://sounds/menu_click.ogg")
	GameState.kino_pilot_mode = true
	_coordinator.call("_close")
	_possess_ship_kino()

# Take control of an already-deployed (live) Kino — from any scene. If it's in
# the current scene, possess it in place; otherwise warp to its scene and the
# scene spawns the controlled Kino at its tracked position. Either way the
# player's BODY is recorded so closing the remote returns there.
func _on_pilot_deployed(index: int) -> void:
	if index < 0 or index >= GameState.deployed_kinos.size():
		return
	var entry: Dictionary = GameState.deployed_kinos[index]
	var scene_path: String = String(entry.get("scene", ""))
	var pos: Vector3 = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0)))
	var same_scene: bool = scene_path == "" or scene_path == GameState.current_scene_path
	# Cross-scene control is supported for the planet (fly a Kino on the surface
	# from the ship). A Kino left elsewhere on the ship is retaken from its room.
	if not same_scene and scene_path != "res://scenes/planet.tscn":
		GameState.add_log("That Kino is in another section — go there to take control.")
		return
	Audio.play("res://sounds/menu_click.ogg")
	_record_body()
	GameState.deployed_kinos.remove_at(index)   # now the active, piloted Kino
	GameState.deployed_kinos_changed.emit()
	GameState.kino_pilot_mode = true
	_coordinator.call("_close")
	if same_scene:
		_possess_kino_here(pos, false)
	else:
		GameState.kino_pilot_target_scene = scene_path
		GameState.kino_pilot_target_pos = pos
		SceneRouter.change_to(scene_path, "")

# Record the player's body (scene + transform) so [E] returns control there.
func _record_body() -> void:
	GameState.kino_return_scene = GameState.current_scene_path
	GameState.kino_return_room_id = GameState.current_room_id
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		GameState.kino_return_position = player.global_position
		GameState.kino_return_yaw = player.rotation.y

# Launch a ship-mode Kino at the player's position. Records the body + possesses
# the current scene; the drone flies through the gate to reach the planet.
# Falls back to a direct planet warp if there's no live scene/player.
func _possess_ship_kino() -> void:
	var scene: Node = get_tree().current_scene
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if scene == null or player == null:
		SceneRouter.change_to("res://scenes/planet.tscn", "")
		return
	_record_body()
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var spawn: Vector3 = player.global_position + fwd * 0.8 + Vector3.UP * KINO_LAUNCH_HEIGHT
	_possess_kino_here(spawn, true)

# Spawn + possess a Kino in the CURRENT scene at `spawn_pos`. If a player body is
# present (the gate room), it STAYS PUT holding the remote (input locked, hands-
# in-front pose). The drone takes the camera. `in_ship` enables gate-crossing.
func _possess_kino_here(spawn_pos: Vector3, in_ship: bool) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		if player.has_method("set_input_locked"):
			player.call("set_input_locked", true)
		if player.has_method("set_pose_override"):
			player.call("set_pose_override", "holding-both")
		_attach_remote_prop(player)
	var hud_layer: Node = scene.get_node_or_null("HUDLayer")
	if hud_layer is CanvasLayer:
		(hud_layer as CanvasLayer).visible = false
	var drone: CharacterBody3D = KinoDroneScript.new()
	drone.name = "KinoDrone"
	drone.set("launch_in_ship", in_ship)
	# NOT in group "player": the body (if any) is still the player.
	if player != null:
		drone.rotation.y = player.rotation.y
	scene.add_child(drone)
	drone.global_position = spawn_pos

# A small "Kino remote" prop parented to Eli so the player (looking back) and
# onlookers see him gripping the controller while he pilots the Kino.
func _attach_remote_prop(player: Node3D) -> void:
	if player.get_node_or_null("KinoRemoteProp") != null:
		return
	var prop: Node3D = Node3D.new()
	prop.name = "KinoRemoteProp"
	# Between the hands, forward of the chest. +X rotation tilts +Y toward +Z
	# (Godot right-hand rule) — i.e. the screen face tips up and BACK toward
	# Eli, so the player looking down sees the screen but a front-on camera
	# sees the back of the device. Height depends on the body: the modular
	# avatar's hands sit ~1.0 m up; the legacy chibi's at ~0.7 m.
	if player.get("_mc") != null:
		prop.position = Vector3(0.0, 1.02, -0.45)
	else:
		prop.position = Vector3(0.0, 0.72, -0.42)
	prop.rotation_degrees = Vector3(45.0, 0.0, 0.0)
	player.add_child(prop)

	# Landscape orientation: long axis on X (wider than deep), so the device
	# reads as a 2-handed tablet/remote rather than a portrait phone.
	var body_mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.30, 0.05, 0.20)
	body_mesh.mesh = box
	body_mesh.material_override = _remote_mat(Color(0.10, 0.12, 0.16), false)
	prop.add_child(body_mesh)

	var screen: MeshInstance3D = MeshInstance3D.new()
	var sbox: BoxMesh = BoxMesh.new()
	sbox.size = Vector3(0.22, 0.02, 0.15)
	screen.mesh = sbox
	screen.position = Vector3(0.0, 0.035, 0.0)
	screen.material_override = _remote_mat(Color(0.45, 0.80, 1.0), true)
	prop.add_child(screen)

func _remote_mat(col: Color, glow: bool) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	if glow:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.2
	else:
		m.metallic = 0.4
		m.roughness = 0.5
	return m

# Friendly label for a deployed Kino's scene path.
func _scene_short_name(scene_path: String) -> String:
	if scene_path.ends_with("planet.tscn"):
		return "Planet"
	if scene_path.ends_with("gate_room.tscn"):
		return "Gate Room"
	if scene_path.ends_with("room.tscn"):
		return "Ship"
	return scene_path.get_file().get_basename().capitalize()

func _kino_action_button(text: String, primary: bool) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", _coordinator.call("_button_stylebox", primary))
	b.add_theme_stylebox_override("hover", _coordinator.call("_button_stylebox_hover"))
	b.add_theme_stylebox_override("pressed", _coordinator.call("_button_stylebox", true))
	Audio.attach_ui_hover(b)
	return b

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l