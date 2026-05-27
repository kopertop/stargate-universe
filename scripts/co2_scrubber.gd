class_name Co2Scrubber
extends Interactable

# Life-support CO2 scrubber for Episode 1 / "Air". Phase D presents it as a
# CLOSED wall panel in the south corridor: Rush has tracked the fault here but
# the bank is sealed behind a maintenance hatch. The first interaction plays
# the reveal scene (Rush slides the hatch open, the crew confirm only lime will
# fix it, Destiny drops from FTL, Brody radios that the gate dialed itself).
# After the off-world lime run, a later interaction spends the lime and repairs.
#
# Owns its own visual (recessed frame + sliding hatch + scrubber internals) so
# it can animate the hatch open during the scene — same self-contained pattern
# as shuttle_crate.gd.

const FRAME_SIZE: Vector3 = Vector3(1.5, 1.7, 0.12)
const HATCH_SIZE: Vector3 = Vector3(1.36, 1.56, 0.08)
const PANEL_Y: float = 1.3
# How far the hatch slides along +X to clear the opening.
const HATCH_SLIDE: float = 1.4

# Reveal-scene beat timings (seconds).
const HATCH_OPEN_TIME: float = 0.9
const LINE_GAP_LONG: float = 3.0
const LINE_GAP_SHORT: float = 1.9
const FTL_BEAT: float = 1.6
const RADIO_CLICK_GAP: float = 0.4
const RADIO_LINE_GAP: float = 3.0

var _hatch: MeshInstance3D = null
var _scene_playing: bool = false

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_build_visual()
	_refresh_prompt()

func _build_visual() -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.5, 1.8, 0.6)
	cs.shape = box
	cs.position = Vector3(0.0, PANEL_Y, 0.0)
	add_child(cs)

	# Recessed frame set into the wall (front face toward +Z, the room side).
	_box(Vector3(0.0, PANEL_Y, 0.0), FRAME_SIZE, _mat(Color(0.10, 0.11, 0.13), 0.6, 0.4))

	# Scrubber internals behind the hatch — only seen once it slides aside.
	var warning: StandardMaterial3D = _emis(Color(1.0, 0.40, 0.12), 2.6)
	var lime: StandardMaterial3D = _emis(Color(0.72, 0.92, 0.38), 0.9)
	_box(Vector3(0.0, PANEL_Y + 0.62, 0.045), Vector3(1.1, 0.12, 0.04), warning)
	_box(Vector3(-0.42, PANEL_Y - 0.1, 0.045), Vector3(0.24, 0.7, 0.04), lime)
	_box(Vector3(0.0, PANEL_Y - 0.1, 0.045), Vector3(0.24, 0.7, 0.04), lime)
	_box(Vector3(0.42, PANEL_Y - 0.1, 0.045), Vector3(0.24, 0.7, 0.04), lime)

	# Sliding hatch cover. Closed until the reveal scene (or already open if the
	# scene has played — e.g. the player returns later to fit the lime).
	_hatch = MeshInstance3D.new()
	_hatch.name = "Hatch"
	var hm: BoxMesh = BoxMesh.new()
	hm.size = HATCH_SIZE
	_hatch.mesh = hm
	_hatch.material_override = _mat(Color(0.34, 0.36, 0.40), 0.7, 0.35)
	var open: bool = GameState.scrubber_diagnosed
	_hatch.position = Vector3(HATCH_SLIDE if open else 0.0, PANEL_Y, 0.09)
	add_child(_hatch)

	var status_col: Color = Color(0.30, 0.9, 0.5) if GameState.scrubber_repaired else Color(1.0, 0.30, 0.12)
	_box(Vector3(0.55, PANEL_Y + 0.66, 0.12), Vector3(0.12, 0.12, 0.04), _emis(status_col, 3.0))

	# No nameplate until Rush opens it: the panel is an anonymous bulkhead hatch
	# until the reveal scene tells the player it's life support.
	if GameState.scrubber_diagnosed:
		var label: Label3D = Label3D.new()
		label.name = "Label"
		label.text = "LIFE SUPPORT"
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 6
		label.shaded = false
		label.modulate = Color(0.75, 0.95, 1.0, 1.0)
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		label.position = Vector3(0.0, PANEL_Y + 1.05, 0.0)
		add_child(label)

func _mat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	return m

func _emis(col: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _on_interact(_by: Node) -> void:
	if GameState.scrubber_repaired:
		GameState.add_log("CO2 scrubber is stable. The cartridge bed is cycling clean air.")
		return
	if not GameState.scrubber_diagnosed:
		_play_reveal_scene()
		return
	if GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
		GameState.repair_scrubber_with_lime()
	else:
		GameState.add_log("The scrubber needs %d lime. Current lime: %d." % [
			GameState.AIR_LIME_REQUIRED,
			GameState.resource_count(GameState.AIR_LIME_RESOURCE),
		])
		GameState.advance_air_quest()
	_refresh_prompt()

# Phase D reveal: Rush slides the hatch open, the crew confirm only lime will
# fix the bank, Destiny drops from FTL, and Brody radios that the gate dialed
# itself. The player keeps control throughout, so every await is guarded by
# is_inside_tree() in case they walk out a door mid-scene (the scene simply
# doesn't complete and replays on return). Skipped wholesale in instant_mode.
func _play_reveal_scene() -> void:
	if _scene_playing:
		return
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		GameState.complete_scrubber_scene()
		_refresh_prompt()
		return
	_scene_playing = true
	_open_hatch()
	await get_tree().create_timer(HATCH_OPEN_TIME).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	GameState.dialogue_shown.emit("Dr Rush", "This stuff can't be salvaged — whatever it is. We'll have to replace it with something else.")
	GameState.add_log("Dr Rush: This stuff can't be salvaged. We'll have to replace it with something else.")
	await get_tree().create_timer(LINE_GAP_LONG).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	GameState.dialogue_shown.emit("Eli Wallace", "Like what?")
	await get_tree().create_timer(LINE_GAP_SHORT).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	GameState.dialogue_shown.emit("Dr Rush", "Lime might work. Did any come through with us when we dialed in?")
	await get_tree().create_timer(LINE_GAP_LONG).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	GameState.dialogue_shown.emit("Dr Park", "No — unfortunately, it didn't make it.")
	await get_tree().create_timer(LINE_GAP_LONG).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	# FTL drop beat: the deck lurches.
	Audio.play("res://sounds/flicker.ogg")
	GameState.add_log("Destiny lurches — the FTL drive cuts out. Stars snap back into the windows.")
	await get_tree().create_timer(FTL_BEAT).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	Audio.play("res://sounds/radio_click.ogg")
	await get_tree().create_timer(RADIO_CLICK_GAP).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	GameState.dialogue_shown.emit("Dr Brody", "Guys — the gate just dialed itself. You'll want to get up here.")
	GameState.add_log("Dr Brody (radio): the gate just dialed itself. Get up here.")
	await get_tree().create_timer(RADIO_LINE_GAP).timeout
	if not is_inside_tree():
		_scene_playing = false
		return
	Audio.play("res://sounds/radio_off.ogg")
	GameState.complete_scrubber_scene()
	_scene_playing = false
	_refresh_prompt()

func _open_hatch() -> void:
	if _hatch == null or not is_instance_valid(_hatch):
		return
	var t: Tween = create_tween()
	t.set_trans(Tween.TRANS_SINE)
	t.tween_property(_hatch, "position:x", HATCH_SLIDE, HATCH_OPEN_TIME)

func _refresh_prompt() -> void:
	if GameState.scrubber_repaired:
		prompt = "CO2 scrubber repaired"
	elif not GameState.scrubber_diagnosed:
		prompt = "Examine the wall panel"
	elif GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
		prompt = "Repair CO2 scrubber"
	else:
		prompt = "CO2 scrubber needs lime"
