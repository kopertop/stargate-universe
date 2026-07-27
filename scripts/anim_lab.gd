extends Node3D
## Animation Lab — a visual catalogue of every shared crew_body clip on the
## Quaternius modular rig, so animations can be reviewed/selected (and new ones
## auditioned) without grepping the manifest or guessing.
##
## Run it: open scenes/anim_lab.tscn and press F6 (Play Scene), or
##   /Applications/Godot.app/Contents/MacOS/Godot res://scenes/anim_lab.tscn
##
## Controls:
##   [G] grid view — every clip looping side-by-side, each labelled
##   [F] focus view — one large actor; [Left]/[Right] (or [Up]/[Down]) step clips
##   [Space] (focus) replay the current clip from the top
## The current/selected clip name shows in the on-screen HUD and prints to stdout
## (handy for copy-pasting the exact string into play_clip("...")).

const CF: Script = preload("res://scripts/character_factory.gd")
const COLS: int = 6
const SPACING: float = 2.6
# Who to dress the demo bodies as — a generic crewman so only the POSE differs.
const DEMO_NAME: String = "Crewman"

var _clips: PackedStringArray = PackedStringArray()
var _grid_actors: Array[Node3D] = []
var _focus_actor: Node3D = null
var _focus_idx: int = 0
var _focus_mode: bool = false

var _cam: Camera3D
var _hud: Label
var _grid_root: Node3D
var _focus_root: Node3D


func _ready() -> void:
	_build_environment()
	_build_hud()
	# The clip library loads in a ModularCharacter's _ready(), so probe a throwaway
	# body for the authoritative clip list rather than hard-coding the manifest.
	var probe: Node3D = CF.build_modular(DEMO_NAME)
	add_child(probe)
	await get_tree().process_frame
	await get_tree().process_frame
	if probe.has_method("clip_names"):
		_clips = probe.call("clip_names")
	probe.queue_free()
	var as_list: Array = Array(_clips)
	as_list.sort()
	_clips = PackedStringArray(as_list)
	print("[anim_lab] %d clips: %s" % [_clips.size(), ", ".join(_clips)])

	_build_grid()
	_build_focus()
	# Default to the FOCUS view — one large, clearly-readable actor (the grid of 40+
	# clips is only an index). [G] switches to the grid, [F] back to focus.
	_set_focus_mode(true)


func _build_environment() -> void:
	var we: WorldEnvironment = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.74, 0.82)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.5
	add_child(sun)

	# A neutral floor grid so feet/contact read.
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var pm: PlaneMesh = PlaneMesh.new()
	pm.size = Vector2(80.0, 80.0)
	floor_mi.mesh = pm
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.20)
	floor_mi.material_override = fmat
	add_child(floor_mi)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.make_current()


func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(18.0, 14.0)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)


# One looping actor per clip, laid out in a grid with a billboard name tag.
func _build_grid() -> void:
	_grid_root = Node3D.new()
	_grid_root.name = "Grid"
	add_child(_grid_root)
	for i in _clips.size():
		var clip: String = _clips[i]
		var col: int = i % COLS
		var row: int = i / COLS
		var x: float = (float(col) - float(COLS - 1) * 0.5) * SPACING
		var z: float = -float(row) * SPACING
		var holder: Node3D = Node3D.new()
		holder.position = Vector3(x, 0.0, z)
		holder.rotation.y = 0.0   # face +Z toward the camera (which sits at +Z)
		_grid_root.add_child(holder)
		var body: Node3D = CF.build_modular(DEMO_NAME)
		holder.add_child(body)
		# Dress the body or it renders as just floating eyes (no body/clothing mesh).
		CF.dress_modular(body, DEMO_NAME, CF.CTX_SHIP)
		_grid_actors.append(body)
		_play(body, clip)
		var tag: Label3D = Label3D.new()
		tag.text = clip
		tag.pixel_size = 0.006
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color(0.85, 0.92, 1.0)
		tag.outline_size = 6
		tag.position = Vector3(0.0, 2.15, 0.0)
		holder.add_child(tag)


func _build_focus() -> void:
	_focus_root = Node3D.new()
	_focus_root.name = "Focus"
	add_child(_focus_root)
	var holder: Node3D = Node3D.new()
	holder.rotation.y = 0.0   # face +Z toward the focus camera
	_focus_root.add_child(holder)
	_focus_actor = CF.build_modular(DEMO_NAME)
	holder.add_child(_focus_actor)
	CF.dress_modular(_focus_actor, DEMO_NAME, CF.CTX_SHIP)


func _play(body: Node3D, clip: String) -> void:
	if body == null:
		return
	# Loop everything in the lab so even one-shots (wave, hit, death) keep cycling.
	if body.has_method("play_clip_looped"):
		body.call("play_clip_looped", clip)
	elif body.has_method("play_clip"):
		body.call("play_clip", clip)


func _set_focus_mode(on: bool) -> void:
	_focus_mode = on
	if _grid_root != null:
		_grid_root.visible = not on
	if _focus_root != null:
		_focus_root.visible = on
	if on:
		_play(_focus_actor, _focus_clip())
		_cam.global_position = Vector3(0.0, 1.4, 4.2)
		_cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	else:
		_layout_camera_grid()
	_update_hud()


# Frame the whole grid from the front, elevated.
func _layout_camera_grid() -> void:
	var rows: int = int(ceil(float(_clips.size()) / float(COLS)))
	var depth: float = float(rows) * SPACING
	# Low + close so the bodies read as figures, looking down the rows (front rows
	# big, back rows recede). Use the interactive focus view ([F]) to inspect one
	# clip large; this overview is the index.
	_cam.global_position = Vector3(0.0, 4.0, 9.5)
	_cam.look_at(Vector3(0.0, 1.0, -depth * 0.55), Vector3.UP)


func _focus_clip() -> String:
	if _clips.is_empty():
		return ""
	return _clips[_focus_idx % _clips.size()]


func _update_hud() -> void:
	if _hud == null:
		return
	if _focus_mode:
		_hud.text = "ANIMATION LAB — FOCUS\nclip: %s  (%d/%d)\n[Left]/[Right] step  [Space] replay  [G] grid" % \
			[_focus_clip(), _focus_idx % maxi(1, _clips.size()) + 1, _clips.size()]
	else:
		_hud.text = "ANIMATION LAB — GRID  (%d clips)\n[F] focus one actor  •  each label = the play_clip(\"name\") string" % _clips.size()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).keycode
	match k:
		KEY_G:
			_set_focus_mode(false)
		KEY_F:
			_set_focus_mode(true)
		KEY_RIGHT, KEY_UP:
			if _focus_mode and not _clips.is_empty():
				_focus_idx = (_focus_idx + 1) % _clips.size()
				_play(_focus_actor, _focus_clip())
				print("[anim_lab] focus clip: ", _focus_clip())
				_update_hud()
		KEY_LEFT, KEY_DOWN:
			if _focus_mode and not _clips.is_empty():
				_focus_idx = (_focus_idx - 1 + _clips.size()) % _clips.size()
				_play(_focus_actor, _focus_clip())
				print("[anim_lab] focus clip: ", _focus_clip())
				_update_hud()
		KEY_SPACE:
			if _focus_mode:
				_play(_focus_actor, _focus_clip())
