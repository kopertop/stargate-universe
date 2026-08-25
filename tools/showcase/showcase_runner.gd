extends Node3D

# Crew & Gear showcase reel — recorded with Godot Movie Maker:
#   godot --path . --write-movie out/raw/showcase.avi --fixed-fps 30 \
#     tools/showcase/showcase.tscn
#
# Acts (all text in-engine; time accumulated from _process delta because
# Movie Maker runs deterministic fixed steps):
#   1. title card
#   2. crew lineup dolly (ship duty dress)
#   3. live outfit hot-swapping on one character
#   4. gear: slung rifle -> draw -> aim; pistol; helmet
#   5. animation reel (walk/jog/sprint/talk/sit/repair/dance)
#   6. end card

const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const ModularScript: Script = preload("res://scripts/modular_character.gd")

const CREW: Array = ["Eli", "Dr Rush", "Lt Scott", "Sgt Greer", "Dr Park", "Chloe Armstrong"]
const ANIM_REEL: Array = [
	["walk", "Walk"], ["jog", "Jog"], ["sprint", "Sprint"],
	["talk", "Talking"], ["idle_arms_folded", "Arms folded (Rush mode)"],
	["sit_enter", "Take a seat"], ["sit_talk", "Seated conversation"],
	["repair", "Repairing the ship"], ["dance", "...and morale upkeep"],
]
const SWAP_REEL: Array = [
	[["Body", "Male_Ranger_Body"], "chest: Ranger tunic"],
	[["Legs", "Male_Peasant_Legs"], "legs: Peasant trousers"],
	[["Body", "Male_Peasant_Body"], "chest: Peasant shirt"],
	[["Feet", "Male_Ranger_Feet_Boots"], "feet: Ranger boots"],
	[["Hair", "Hair_Beard"], "hair: beard"],
	[["Body", "Male_Ranger_Body"], "chest: back to Ranger"],
]

var _t: float = 0.0
var _events: Array = []   # [time, Callable] sorted; fired once
var _cam: Camera3D
var _caption: Label
var _card: Label
var _overlay: ColorRect
var _crew_nodes: Array = []
var _crew_tags: Array = []
var _hero: Node3D = null
var _cam_from: Transform3D
var _cam_to: Transform3D
var _cam_t0: float = 0.0
var _cam_dur: float = 0.0


func _ready() -> void:
	_build_stage()
	_build_overlay()
	_build_cast()
	_script_events()


func _process(delta: float) -> void:
	_t += delta
	while not _events.is_empty() and _t >= float(_events[0][0]):
		var ev: Array = _events.pop_front()
		(ev[1] as Callable).call()
	# Camera tween (manual — Movie Maker prefers deterministic per-frame math).
	if _cam_dur > 0.0:
		var a: float = clampf((_t - _cam_t0) / _cam_dur, 0.0, 1.0)
		a = a * a * (3.0 - 2.0 * a)   # smoothstep
		_cam.global_transform = _cam_from.interpolate_with(_cam_to, a)


# ------------------------------- staging --------------------------------------

func _build_stage() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.16)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.7, -0.4, 0.0)
	sun.light_energy = 1.15
	add_child(sun)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.5, 0.0)
	fill.light_energy = 0.45
	add_child(fill)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.17, 0.19, 0.23)
	floor_mesh.material_override = fmat
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.position = Vector3(0, 1.4, 6.0)
	_cam.current = true


func _build_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.04, 0.05, 0.08, 1.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 44)
	layer.add_child(_card)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -90.0
	_caption.offset_bottom = -40.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(_caption)


func _build_cast() -> void:
	for i in range(CREW.size()):
		var c: Node3D = FactoryRef.build_modular(CREW[i])
		c.position = Vector3(i * 1.5 - 3.75, 0.0, 0.0)
		c.rotation.y = 0.12
		add_child(c)
		FactoryRef.dress_modular(c, CREW[i], FactoryRef.CTX_SHIP)
		c.call("play_clip", "idle")
		_crew_nodes.append(c)
		var tag: Label3D = Label3D.new()
		tag.text = CREW[i]
		tag.position = Vector3(c.position.x, 2.05, 0.0)
		tag.pixel_size = 0.0030
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.outline_size = 8
		add_child(tag)
		_crew_tags.append(tag)
	# Hero for the swap/gear/anim acts, off to the side until needed.
	_hero = FactoryRef.build_modular("Lt Scott")
	_hero.name = "Hero"
	_hero.position = Vector3(0.0, 0.0, 8.0)
	add_child(_hero)
	FactoryRef.dress_modular(_hero, "Lt Scott", FactoryRef.CTX_MISSION)


# ------------------------------- the script -----------------------------------

func _at(t: float, fn: Callable) -> void:
	_events.append([t, fn])


func _script_events() -> void:
	# Act 1: title (0-3s)
	_card.text = "STARGATE UNIVERSE\nModular Crew System"
	_at(3.0, func() -> void:
		_overlay.visible = false
		_card.visible = false
		_say("One body system. Every outfit, every weapon, swappable in code."))
	# Act 2: lineup dolly (3-12s)
	_at(3.0, func() -> void:
		_move_cam(Vector3(-4.5, 1.5, 4.2), Vector3(-3.75, 1.0, 0.0),
			Vector3(4.5, 1.5, 4.2), Vector3(3.75, 1.0, 0.0), 8.5))
	_at(6.0, func() -> void: _say("The crew of Destiny — ship duty dress"))
	# Act 3: hot-swap (12-24s)
	_at(12.0, func() -> void:
		for n in _crew_nodes:
			n.visible = false
		for tag in _crew_tags:
			tag.visible = false
		_hero.position = Vector3(0.0, 0.0, 0.0)
		_hero.rotation.y = 0.35
		_hero.call("play_clip", "idle")
		_snap_cam(Vector3(0.8, 1.4, 3.0), Vector3(0.0, 1.05, 0.0))
		_say("Live gear hot-swapping"))
	for i in range(SWAP_REEL.size()):
		var swap: Array = SWAP_REEL[i]
		_at(13.5 + i * 1.7, func() -> void:
			_hero.call("set_slot", swap[0][0], swap[0][1])
			_say(swap[1]))
	# Act 4: gear (24-36s)
	_at(24.0, func() -> void:
		_hero.call("set_rifle", true, false)
		_hero.call("play_clip", "walk")
		_move_cam(Vector3(0.8, 1.4, 3.0), Vector3(0.0, 1.05, 0.0),
			Vector3(-1.6, 1.5, -2.6), Vector3(0.0, 1.1, 0.0), 3.0)
		_say("Rifle slung on the back..."))
	_at(28.0, func() -> void:
		_hero.call("play_clip", "rifle_draw")
		_snap_cam(Vector3(1.8, 1.45, 2.6), Vector3(0.0, 1.2, 0.0))
		_say("...drawn..."))
	_at(30.5, func() -> void:
		_hero.call("set_rifle", true, true)
		_hero.call("play_clip", "rifle_aim")
		_say("...and aimed. Bone-mounted, animation-true."))
	_at(33.5, func() -> void:
		_hero.call("set_rifle", false)
		_hero.call("set_sidearm", true, true)
		_hero.call("set_helmet", true)
		_hero.call("play_clip", "pistol_aim")
		_say("Sidearm + helmet — every mount is a bone snap point"))
	# Act 5: animation reel (36-54s)
	_at(36.5, func() -> void:
		_hero.call("set_sidearm", false)
		_hero.call("set_helmet", false)
		_move_cam(Vector3(1.8, 1.45, 2.6), Vector3(0.0, 1.2, 0.0),
			Vector3(0.0, 1.5, 3.4), Vector3(0.0, 1.0, 0.0), 2.0))
	for i in range(ANIM_REEL.size()):
		var entry: Array = ANIM_REEL[i]
		_at(37.0 + i * 2.0, func() -> void:
			_hero.call("play_clip", entry[0])
			_say("41 shared clips: %s" % entry[1]))
	# Act 6: end card (55-58s)
	_at(55.0, func() -> void:
		_overlay.visible = true
		_card.visible = true
		_caption.text = ""
		_card.text = "Quaternius Universal rig\n+ Mixamo + UAL libraries\n\nSTARGATE UNIVERSE")
	_at(58.0, func() -> void: get_tree().quit())


func _say(text: String) -> void:
	_caption.text = text


func _snap_cam(pos: Vector3, look: Vector3) -> void:
	_cam_dur = 0.0
	_cam.position = pos
	_cam.look_at(look, Vector3.UP)


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
