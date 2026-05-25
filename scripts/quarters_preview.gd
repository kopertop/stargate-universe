@tool
extends Node3D

# Quarters furniture workbench. Attach to the root of
# scenes/quarters_test.tscn. Runs in @tool mode so every Inspector change
# updates the scene LIVE in the editor.
#
# Workflow:
#   1. Open scenes/quarters_test.tscn in the editor.
#   2. Click the "QuartersTest" root node.
#   3. Adjust the per-prop @export groups (Bed, Nightstand, Lamp, ...).
#   4. When you have a layout you like, paste the values back to Claude
#      and they get baked into RoomBuilder._accent_quarters in room_builder.gd.
#
# The placeholder walls + floor are 10×12 m to match Eli's Quarters
# (half_x = 5, half_z = 6 — same dimensions used by the live ship layout).

# --- Knobs --------------------------------------------------------------

@export var refresh_now: bool = false:
	set(_v):
		refresh_now = false
		_full_rebuild()

@export_group("Bed")
@export var bed_position: Vector3 = Vector3(-1.5, 0.0, -5.4):
	set(v): bed_position = v; _rebuild_prop_bed()
@export_range(-180.0, 180.0, 1.0) var bed_yaw_deg: float = 0.0:
	set(v): bed_yaw_deg = v; _rebuild_prop_bed()
@export_range(0.1, 6.0, 0.05) var bed_scale: float = 2.5:
	set(v): bed_scale = v; _rebuild_prop_bed()

@export_group("Nightstand")
@export var nightstand_position: Vector3 = Vector3(0.85, 0.0, -5.1):
	set(v): nightstand_position = v; _rebuild_prop_nightstand()
@export_range(-180.0, 180.0, 1.0) var nightstand_yaw_deg: float = 0.0:
	set(v): nightstand_yaw_deg = v; _rebuild_prop_nightstand()
@export_range(0.1, 6.0, 0.05) var nightstand_scale: float = 2.0:
	set(v): nightstand_scale = v; _rebuild_prop_nightstand()

@export_group("Lamp")
@export var lamp_position: Vector3 = Vector3(0.85, 1.0, -5.1):
	set(v): lamp_position = v; _rebuild_prop_lamp()
@export_range(-180.0, 180.0, 1.0) var lamp_yaw_deg: float = 0.0:
	set(v): lamp_yaw_deg = v; _rebuild_prop_lamp()
@export_range(0.1, 6.0, 0.05) var lamp_scale: float = 2.0:
	set(v): lamp_scale = v; _rebuild_prop_lamp()

@export_group("Locker")
@export var locker_position: Vector3 = Vector3(-1.5, 0.0, 5.3):
	set(v): locker_position = v; _rebuild_prop_locker()
@export_range(-180.0, 180.0, 1.0) var locker_yaw_deg: float = 180.0:
	set(v): locker_yaw_deg = v; _rebuild_prop_locker()
@export_range(0.1, 6.0, 0.05) var locker_scale: float = 2.5:
	set(v): locker_scale = v; _rebuild_prop_locker()

@export_group("Desk")
@export var desk_position: Vector3 = Vector3(3.6, 0.0, 0.0):
	set(v): desk_position = v; _rebuild_prop_desk()
@export_range(-180.0, 180.0, 1.0) var desk_yaw_deg: float = -90.0:
	set(v): desk_yaw_deg = v; _rebuild_prop_desk()
@export_range(0.1, 6.0, 0.05) var desk_scale: float = 2.5:
	set(v): desk_scale = v; _rebuild_prop_desk()

@export_group("Chair")
@export var chair_position: Vector3 = Vector3(2.0, 0.0, 0.0):
	set(v): chair_position = v; _rebuild_prop_chair()
@export_range(-180.0, 180.0, 1.0) var chair_yaw_deg: float = -90.0:
	set(v): chair_yaw_deg = v; _rebuild_prop_chair()
@export_range(0.1, 6.0, 0.05) var chair_scale: float = 2.5:
	set(v): chair_scale = v; _rebuild_prop_chair()

# --- Implementation -----------------------------------------------------

const PROPS: Dictionary = {
	"Bed":        "res://models/props/furniture_kit/bedSingle.glb",
	"Nightstand": "res://models/props/furniture_kit/cabinetBedDrawerTable.glb",
	"Lamp":       "res://models/props/furniture_kit/lampSquareTable.glb",
	"Locker":     "res://models/props/furniture_kit/bathroomCabinet.glb",
	"Desk":       "res://models/props/furniture_kit/desk.glb",
	"Chair":      "res://models/props/furniture_kit/chairDesk.glb",
}

const TINTS: Dictionary = {
	"Bed":        Color(0.62, 0.58, 0.52),
	"Nightstand": Color(0.42, 0.36, 0.30),
	"Lamp":       Color(0.85, 0.78, 0.65),
	"Locker":     Color(0.38, 0.40, 0.44),
	"Desk":       Color(0.45, 0.40, 0.35),
	"Chair":      Color(0.30, 0.32, 0.36),
}


func _ready() -> void:
	_full_rebuild()


func _full_rebuild() -> void:
	_rebuild_prop_bed()
	_rebuild_prop_nightstand()
	_rebuild_prop_lamp()
	_rebuild_prop_locker()
	_rebuild_prop_desk()
	_rebuild_prop_chair()


func _rebuild_prop_bed() -> void:
	_spawn("Bed", bed_position, bed_yaw_deg, bed_scale)

func _rebuild_prop_nightstand() -> void:
	_spawn("Nightstand", nightstand_position, nightstand_yaw_deg, nightstand_scale)

func _rebuild_prop_lamp() -> void:
	_spawn("Lamp", lamp_position, lamp_yaw_deg, lamp_scale)

func _rebuild_prop_locker() -> void:
	_spawn("Locker", locker_position, locker_yaw_deg, locker_scale)

func _rebuild_prop_desk() -> void:
	_spawn("Desk", desk_position, desk_yaw_deg, desk_scale)

func _rebuild_prop_chair() -> void:
	_spawn("Chair", chair_position, chair_yaw_deg, chair_scale)


# Tear down any existing instance of this prop and rebuild it at the
# requested transform. Each prop lives as a direct child of QuartersTest
# named after the prop key ("Bed", "Nightstand", etc.) for easy editor
# selection.
func _spawn(prop_name: String, pos: Vector3, yaw_deg: float, scale_f: float) -> void:
	var glb_path: String = PROPS.get(prop_name, "")
	if glb_path == "":
		return
	var tint: Color = TINTS.get(prop_name, Color.WHITE)

	var existing: Node = get_node_or_null(prop_name)
	if existing != null:
		existing.queue_free()

	var holder: Node3D = Node3D.new()
	holder.name = prop_name
	holder.position = pos
	holder.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	holder.scale = Vector3.ONE * scale_f
	add_child(holder)

	var glb: PackedScene = load(glb_path)
	if glb == null:
		push_warning("quarters_preview: missing %s" % glb_path)
		return
	var inst: Node = glb.instantiate()
	holder.add_child(inst)

	# Kenney textures are stripped on glTF import — paint over with a
	# solid tint so the prop reads as something other than a white blob.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = 0.0
	mat.roughness = 0.55
	_apply_material_recursive(inst, mat)


static func _apply_material_recursive(root: Node, mat: StandardMaterial3D) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		var surf_count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i in surf_count:
			mi.set_surface_override_material(i, mat)
	for child in root.get_children():
		_apply_material_recursive(child, mat)
