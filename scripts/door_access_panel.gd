class_name DoorAccessPanel
extends Interactable

# Soft-lock door panel (weapons-tools): hotwire with the Access Tablet, or
# force-open / hack with the Kino Remote. Same unlock under the hood — clears
# a GameState soft_locked_doors entry and refreshes the linked Door.
#
# Spawned beside Gate Room ExitDoor; generalises to any soft-locked edge.

@export var room_a: String = ""
@export var room_b: String = ""
@export var door_node_path: NodePath = NodePath()

var _resolved: bool = false  # @collection-ok: one-shot panel state, not a collection
var _busy: bool = false  # @collection-ok: in-flight interact guard


func _ready() -> void:
	super()
	_refresh_prompt()
	_build_visual()
	if GameState.has_signal("soft_locks_changed") and not GameState.soft_locks_changed.is_connected(_on_soft_locks_changed):
		GameState.soft_locks_changed.connect(_on_soft_locks_changed)
	if Inventory.has_signal("wield_changed") and not Inventory.wield_changed.is_connected(_on_wield_changed):
		Inventory.wield_changed.connect(_on_wield_changed)


func _on_soft_locks_changed() -> void:
	_refresh_prompt()


func _on_wield_changed(_index: int, _item_id: String) -> void:
	_refresh_prompt()


func _is_soft_locked() -> bool:
	if room_a == "" or room_b == "":
		return false
	return GameState.is_soft_locked(room_a, room_b)


func _interface_tool() -> String:
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return ""
	var active: String = String(inv.call("active_wield_id"))
	if inv.call("is_interface_tool", active):
		return active
	# Owned interface tool but wrong hotbar selection.
	if inv.call("has", "kino_remote"):
		return "kino_remote_unowned_wield"
	if inv.call("has", "tablet"):
		return "tablet_unowned_wield"
	return ""


func _refresh_prompt() -> void:
	if _resolved or not _is_soft_locked():
		_resolved = true
		enabled = false
		prompt = "Panel sealed — door responds."
		return
	enabled = true
	var tool: String = _interface_tool()
	match tool:
		"tablet":
			prompt = "Hack access panel"
		"kino_remote":
			prompt = "Force-open panel"
		"tablet_unowned_wield", "kino_remote_unowned_wield":
			prompt = "Select your interface tool (hotbar 1)"
		_:
			prompt = "Need an access tablet"


func _on_interact(by: Node) -> void:
	if _busy or _resolved or not _is_soft_locked():
		_refresh_prompt()
		return
	var tool: String = _interface_tool()
	if tool != "tablet" and tool != "kino_remote":
		if tool.ends_with("_unowned_wield"):
			GameState.add_log("Select your interface tool on hotbar slot 1 first.")
		else:
			GameState.add_log("I need my tablet to open this panel.")
		return

	_busy = true
	var force: bool = tool == "kino_remote"
	var verb: String = "Force-opening" if force else "Hotwiring"
	GameState.add_log("%s the bulkhead panel…" % verb)
	if by.has_method("begin_tool_use"):
		by.call("begin_tool_use", "repair", 0.0)
	var mg: Node = get_node_or_null("/root/HotwireMinigame")
	var ok: bool = false
	if mg != null and mg.has_method("play"):
		ok = bool(await mg.call("play", force))
	else:
		ok = true
	if is_instance_valid(by) and by.has_method("end_tool_use"):
		by.call("end_tool_use")
	if not ok:
		GameState.add_log("Access attempt cancelled.")
		_busy = false
		_refresh_prompt()
		return
	_finish_unlock(tool)
	_busy = false


func _finish_unlock(tool: String) -> void:
	if _resolved:
		return
	GameState.clear_soft_lock(room_a, room_b)
	var door: Node = get_node_or_null(door_node_path)
	if door != null and door.has_method("unlock"):
		door.call("unlock")
	elif door != null and "locked" in door:
		door.set("locked", false)
		if door.has_method("_refresh_prompt"):
			door.call("_refresh_prompt")
		if door.has_method("_refresh_status_light"):
			door.call("_refresh_status_light")
	_resolved = true
	enabled = false
	prompt = "Panel sealed — door responds."
	if tool == "kino_remote":
		GameState.add_log("Force-open complete. Bulkhead responds.")
	else:
		GameState.add_log("Hotwire complete. Bulkhead responds.")
	_set_done_visual()


# ---- visual -----------------------------------------------------------------

var _status_mat: StandardMaterial3D = null


func _build_visual() -> void:
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.14, 0.15, 0.18, 1.0)
	housing_mat.metallic = 0.7
	housing_mat.roughness = 0.35
	var housing: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.08, 0.55, 0.40)
	housing.mesh = box
	housing.material_override = housing_mat
	housing.position = Vector3(0.0, 1.1, 0.0)
	add_child(housing)

	_status_mat = StandardMaterial3D.new()
	_status_mat.emission_enabled = true
	_status_mat.emission = Color(1.0, 0.45, 0.12, 1.0)
	_status_mat.emission_energy_multiplier = 2.2
	_status_mat.albedo_color = Color(0.4, 0.18, 0.05, 1.0)
	var indicator: MeshInstance3D = MeshInstance3D.new()
	var ind: BoxMesh = BoxMesh.new()
	ind.size = Vector3(0.05, 0.08, 0.08)
	indicator.mesh = ind
	indicator.material_override = _status_mat
	indicator.position = Vector3(0.04, 1.1, 0.0)
	add_child(indicator)

	var label: Label3D = Label3D.new()
	label.text = "ACCESS"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.95, 0.75, 0.35, 1.0)
	label.position = Vector3(0.06, 1.45, 0.0)
	add_child(label)

	if not _is_soft_locked():
		_set_done_visual()


func _set_done_visual() -> void:
	if _status_mat == null:
		return
	_status_mat.emission = Color(0.25, 0.85, 0.45, 1.0)
	_status_mat.albedo_color = Color(0.08, 0.25, 0.14, 1.0)
	_status_mat.emission_energy_multiplier = 1.2
