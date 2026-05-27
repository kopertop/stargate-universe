class_name Co2Scrubber
extends Interactable

# Life-support CO2 scrubber for Episode 1 / "Air". In Phase D it's the open
# wall panel in the south corridor — Dr Rush has already slid the hatch when
# the player arrives, so the panel reads as exposed/under-repair. The scene
# itself is triggered by talking to Rush (scrubber_rush.gd), NOT this panel:
# before diagnosis, interacting the panel just points the player at him. After
# the off-world lime run, interacting it spends the lime and repairs.
#
# The three cartridge bars are a lime-charge gauge driven by
# GameState.scrubber_level (0%=3 red, 33%=1 green, 66%=2, 100%=3). Owns its own
# visual so the hatch can be drawn open and the bars recoloured per state.

const FRAME_SIZE: Vector3 = Vector3(1.5, 1.7, 0.12)
const HATCH_SIZE: Vector3 = Vector3(1.36, 1.56, 0.08)
const PANEL_Y: float = 1.3
const HATCH_SLIDE: float = 1.4
const BAR_GREEN: Color = Color(0.72, 0.92, 0.38)
const BAR_RED: Color = Color(1.0, 0.26, 0.16)

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

	# Warning strip + three cartridge bars (the lime-charge gauge).
	_box(Vector3(0.0, PANEL_Y + 0.62, 0.045), Vector3(1.1, 0.12, 0.04), _emis(Color(1.0, 0.40, 0.12), 2.6))
	var green_bars: int = GameState.scrubber_green_bars()
	var bar_x: Array[float] = [-0.42, 0.0, 0.42]
	for i in 3:
		var col: Color = BAR_GREEN if i < green_bars else BAR_RED
		_box(Vector3(bar_x[i], PANEL_Y - 0.1, 0.045), Vector3(0.24, 0.7, 0.04), _emis(col, 1.4))

	# Hatch: open whenever Rush has it pulled (the Phase D window) or once the
	# fault's been diagnosed; flush-closed otherwise.
	var hatch_open: bool = GameState.scrubber_diagnosed or (
		GameState.air_crisis_started and not GameState.breaches_sealed.is_empty()
	)
	var hatch: MeshInstance3D = MeshInstance3D.new()
	hatch.name = "Hatch"
	var hm: BoxMesh = BoxMesh.new()
	hm.size = HATCH_SIZE
	hatch.mesh = hm
	hatch.material_override = _mat(Color(0.34, 0.36, 0.40), 0.7, 0.35)
	hatch.position = Vector3(HATCH_SLIDE if hatch_open else 0.0, PANEL_Y, 0.09)
	add_child(hatch)

	# No nameplate until the scene reveals what it is.
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
		# The scene is Rush's — defer to him rather than self-diagnosing.
		GameState.add_log("Dr Rush is working the open panel. Talk to him.")
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

func _refresh_prompt() -> void:
	if GameState.scrubber_repaired:
		prompt = "CO2 scrubber repaired"
	elif not GameState.scrubber_diagnosed:
		prompt = "Examine the open panel"
	elif GameState.has_resource(GameState.AIR_LIME_RESOURCE, GameState.AIR_LIME_REQUIRED):
		prompt = "Repair CO2 scrubber"
	else:
		prompt = "CO2 scrubber needs lime"
