class_name SalvagePanel
extends Interactable

# D4 parts economy: a salvageable broken panel or console fixture.
# One-shot: dismantling grants `parts` once, then disables itself so the
# interact ray no longer hits it. Spawned by room.gd in generated
# power_node/storage/control rooms and in the authored aft_storage_hall.
#
# Grants are intentionally small (SALVAGE_PANEL_GRANT parts each) so the
# player collects from several sources per floor rather than a single jackpot.
# ProceduralShip.floor_parts_budget() tracks the aggregate per floor.

@export var grant_amount: int = 3  # Parts granted on dismantle.
@export var dismantled_prompt: String = "Already stripped."

var _dismantled: bool = false  # @collection-ok: tracks single-object state, not collection membership


func _ready() -> void:
	super()
	prompt = "Salvage parts from panel"
	if _dismantled:
		enabled = false
		prompt = dismantled_prompt
	_build_visual()


func _on_interact(_by: Node) -> void:
	if _dismantled:
		return
	_dismantled = true
	enabled = false
	prompt = dismantled_prompt
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv != null:
		inv.call("add_item", "parts", grant_amount, "salvage_panel")
	GameState.add_log("Salvaged %d parts from the broken panel." % grant_amount)
	# Dim the emissive indicator so the panel reads as stripped.
	_set_stripped()


# ---- visual -----------------------------------------------------------------

var _status_mat: StandardMaterial3D = null

func _build_visual() -> void:
	# Dark housing on the wall face.
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.18, 0.17, 0.19, 1.0)
	housing_mat.metallic = 0.55
	housing_mat.roughness = 0.45
	var housing: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.65, 0.50)
	housing.mesh = housing_box
	housing.material_override = housing_mat
	housing.position = Vector3(0.0, 0.9, 0.0)
	add_child(housing)

	# Small emissive indicator — amber (available) or dark (stripped).
	_status_mat = StandardMaterial3D.new()
	_status_mat.emission_enabled = true
	_refresh_status()
	var indicator: MeshInstance3D = MeshInstance3D.new()
	var ind_box: BoxMesh = BoxMesh.new()
	ind_box.size = Vector3(0.04, 0.10, 0.10)
	indicator.mesh = ind_box
	indicator.material_override = _status_mat
	indicator.position = Vector3(0.02, 0.9, 0.0)
	add_child(indicator)

	# Label.
	var label: Label3D = Label3D.new()
	label.text = "SALVAGE"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.85, 0.80, 0.65, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.05, 1.35, 0.0)
	add_child(label)


func _refresh_status() -> void:
	if _status_mat == null:
		return
	if _dismantled:
		_status_mat.albedo_color = Color(0.15, 0.15, 0.16, 1.0)
		_status_mat.emission = Color(0.0, 0.0, 0.0, 1.0)
		_status_mat.emission_energy_multiplier = 0.0
	else:
		_status_mat.albedo_color = Color(1.0, 0.55, 0.10, 1.0)
		_status_mat.emission = Color(1.0, 0.55, 0.10, 1.0)
		_status_mat.emission_energy_multiplier = 2.8


func _set_stripped() -> void:
	_refresh_status()


# ---- save contract ----------------------------------------------------------
# SalvagePanel is a scene node, not an autoload, so its state rides in GameState's
# room-interactable snapshot. For now the one-shot is session-persistent only
# (re-entering a room re-spawns the panel undismantled — acceptable for Phase A;
# persistence is deferred to the full interactable-state save in issue #132).
