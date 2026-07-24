class_name RepairConsole
extends Interactable

# Repair console (issue #131): dispatches the RepairRobot to heal a sealed or
# damaged room. Placed in `north_spur` by room.gd to unlock the Sealed Shuttle
# Bay; generalises to any room_id with a condition entry in ProceduralShip.
#
# Interaction validates that the player holds enough parts, then calls
# RepairRobot.dispatch(target_room_id). The robot ticks parts over time
# (or completes synchronously under SceneRouter.instant_mode).

@export var target_room_id: String = ""

var _dispatched: bool = false  # @collection-ok: tracks single-object dispatch state, not collection membership


func _ready() -> void:
	super()
	prompt = "Deploy repair robot"
	_refresh_prompt()
	_build_visual()


func _on_interact(by: Node) -> void:
	if _dispatched:
		return
	if target_room_id == "":
		return

	# Already repaired — nothing to do (idempotent guard).
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	if ps != null and not ps.call("is_room_sealed", target_room_id):
		_dispatched = true
		enabled = false
		prompt = "Repair complete."
		_refresh_prompt()
		GameState.add_log("The bulkhead is already clear.")
		return

	# Validate parts.
	var rr: Node = get_node_or_null("/root/RepairRobot")
	if rr == null:
		GameState.add_log("ERROR: RepairRobot autoload not found.")
		return

	var cost: int = int(ps.call("get_seal_repair_cost")) if ps != null else 8
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null or int(inv.call("count", "parts")) < cost:
		GameState.add_log("Not enough spare parts. Need %d to deploy the repair robot." % cost)
		return

	if by.has_method("begin_tool_use"):
		by.call("begin_tool_use", "repair", 1.2)
		_dispatch_after(by, 1.2)
		return
	_dispatch_repair()


func _dispatch_after(by: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_dispatch_repair()
	if is_instance_valid(by) and by.has_method("end_tool_use"):
		by.call("end_tool_use")


func _dispatch_repair() -> void:
	if _dispatched:
		return
	var rr: Node = get_node_or_null("/root/RepairRobot")
	if rr == null:
		GameState.add_log("ERROR: RepairRobot autoload not found.")
		return
	_dispatched = true
	enabled = false
	prompt = "Robot dispatched…"
	_refresh_prompt()
	GameState.add_log("Deploying repair robot to %s. This will take time." % target_room_id)
	rr.call("dispatch", target_room_id)


# ---- visual -----------------------------------------------------------------

var _status_mat: StandardMaterial3D = null

func _build_visual() -> void:
	# Dark housing on the wall face.
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.15, 0.16, 0.20, 1.0)
	housing_mat.metallic = 0.65
	housing_mat.roughness = 0.40
	var housing: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.06, 0.70, 0.52)
	housing.mesh = housing_box
	housing.material_override = housing_mat
	housing.position = Vector3(0.0, 0.9, 0.0)
	add_child(housing)

	# Emissive indicator — cyan (ready) → dark (dispatched / done).
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
	label.text = "REPAIR ROBOT"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.70, 0.90, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.05, 1.40, 0.0)
	add_child(label)


func _refresh_prompt() -> void:
	if _status_mat == null:
		return
	_refresh_status()


func _refresh_status() -> void:
	if _status_mat == null:
		return
	if _dispatched:
		_status_mat.albedo_color = Color(0.15, 0.15, 0.16, 1.0)
		_status_mat.emission = Color(0.0, 0.0, 0.0, 1.0)
		_status_mat.emission_energy_multiplier = 0.0
	else:
		_status_mat.albedo_color = Color(0.20, 0.75, 1.0, 1.0)
		_status_mat.emission = Color(0.20, 0.75, 1.0, 1.0)
		_status_mat.emission_energy_multiplier = 2.5
