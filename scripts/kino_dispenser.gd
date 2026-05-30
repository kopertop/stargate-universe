class_name KinoDispenser
extends Interactable

# Barrel-shaped Kino dispenser in Eli's quarters (Phase E). Each interact pulls
# a Kino orb; supply is unlimited but the player caps at GameState.KINO_ORB_MAX.
# Owns its own visual (barrel body + glowing rim) and clips like other props.

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	add_to_group("kino_dispenser")
	_build_visual()
	_refresh_prompt()

func _build_visual() -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.9, 1.5, 0.9)
	cs.shape = box
	cs.position = Vector3(0.0, 0.75, 0.0)
	add_child(cs)

	var body: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.38
	cyl.bottom_radius = 0.42
	cyl.height = 1.0
	body.mesh = cyl
	body.material_override = _mat(Color(0.28, 0.30, 0.36), 0.6, 0.4)
	body.position = Vector3(0.0, 0.5, 0.0)
	add_child(body)

	var rim: MeshInstance3D = MeshInstance3D.new()
	var rc: CylinderMesh = CylinderMesh.new()
	rc.top_radius = 0.30
	rc.bottom_radius = 0.30
	rc.height = 0.14
	rim.mesh = rc
	rim.material_override = _emis(Color(0.55, 0.85, 1.0), 2.6)
	rim.position = Vector3(0.0, 1.06, 0.0)
	add_child(rim)

	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = "KINO DISPENSER"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.75, 0.95, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, 1.5, 0.0)
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

func _on_interact(_by: Node) -> void:
	GameState.acquire_kino_orb()
	_refresh_prompt()

func _refresh_prompt() -> void:
	if GameState.kino_orbs >= GameState.KINO_ORB_MAX:
		prompt = "Kinos full (%d/%d)" % [GameState.kino_orbs, GameState.KINO_ORB_MAX]
	else:
		prompt = "Take a Kino (%d/%d)" % [GameState.kino_orbs, GameState.KINO_ORB_MAX]
