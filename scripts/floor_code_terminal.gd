class_name FloorCodeTerminal
extends Interactable

# Collectible terminal that reveals the access code for a target floor.
# Spawned by room.gd in the floor_code_terminal_room for each locked floor.
# One interact marks the target floor's code as known on ProceduralShip,
# logs a discovery, and disables itself (one-shot).
#
# The terminal is seeded into a generated room of floor n-1 (or a base room
# for floor 2's code). Deterministic per target_floor so save/load restores
# correctly — the same room always holds the same terminal.

# Set by room.gd BEFORE add_child so _ready reads the correct target floor.
var target_floor: int = 0

# Stable POI key used for GameState.discovered_pois (one entry per floor code).
func _poi_key() -> String:
	return "floor_code_f%d" % target_floor


func _ready() -> void:
	super()
	# Interactable._ready sets collision_layer = 4.
	# Check if the code was already collected (e.g. loaded from save).
	var already_known: bool = ProceduralShip.is_floor_code_known(target_floor)
	if already_known:
		enabled = false
		prompt = "Floor %d access code — already retrieved" % target_floor
	else:
		prompt = "Examine terminal — Floor %d access data" % target_floor
	_build_visual()


# ── visual ────────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.16, 0.16, 0.20)
	housing_mat.metallic = 0.50
	housing_mat.roughness = 0.50

	var housing: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.60, 0.42)
	housing.mesh = housing_box
	housing.material_override = housing_mat
	housing.position = Vector3(0.0, 1.20, 0.0)
	add_child(housing)

	# Screen — amber if code not yet collected, green once enabled = false.
	var screen_col: Color = Color(0.22, 0.82, 0.46) if ProceduralShip.is_floor_code_known(target_floor) else Color(1.0, 0.72, 0.18)
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = screen_col
	screen_mat.emission_enabled = true
	screen_mat.emission = screen_col
	screen_mat.emission_energy_multiplier = 2.8

	var screen: MeshInstance3D = MeshInstance3D.new()
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = Vector3(0.04, 0.40, 0.30)
	screen.mesh = screen_box
	screen.material_override = screen_mat
	screen.position = Vector3(0.02, 1.20, 0.0)
	add_child(screen)

	var lbl: Label3D = Label3D.new()
	lbl.text = "DECK\nACCESS\nDATA"
	lbl.pixel_size = 0.0034
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 5
	lbl.shaded = false
	lbl.modulate = Color(0.92, 0.90, 0.78, 1.0)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.position = Vector3(0.05, 1.65, 0.0)
	add_child(lbl)


# ── interaction ───────────────────────────────────────────────────────────────

func _on_interact(_by: Node) -> void:
	if target_floor <= 1:
		return  # Floor 1 needs no code.

	ProceduralShip.mark_floor_code_known(target_floor)

	# Record discovery in GameState's POI registry (the ONE collection for POIs).
	var poi_key: String = _poi_key()
	if not GameState.discovered_pois.has(poi_key):
		GameState.discovered_pois[poi_key] = {
			"category": "floor_code",
			"label": "Floor %d Access Code" % target_floor,
		}
		GameState.pois_discovered_changed.emit()

	GameState.add_log(
		"[Floor Access] Retrieved access code for Floor %d. Unlockable at the elevator panel." % target_floor
	)

	# Disable after one use.
	enabled = false
	prompt = "Floor %d access code — retrieved" % target_floor
