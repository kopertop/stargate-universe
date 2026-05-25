@tool
extends Node3D

# Console screen workbench (V2 — TextMesh approach).
#
# The SubViewport-render-to-texture approach proved unreliable in @tool
# mode (the viewport doesn't always render in time for the editor to
# sample the texture). Switched to TextMesh: a built-in 3D primitive that
# generates real geometry for text. Renders reliably in editor without
# any frame-timing tricks.
#
# Workflow:
#   1. Open scenes/console_test.tscn in the editor.
#   2. Select the "ConsoleTest" root node.
#   3. Edit the @export properties in the Inspector — changes apply LIVE.
#   4. Once you have a look you like, paste the values back to Claude and
#      they get baked into scripts/gate_console.gd.

@export_multiline var screen_text: String = "GATE CONTROL\nSTANDBY":
	set(value):
		screen_text = value
		_refresh_text()

@export var text_color: Color = Color(0.32, 0.72, 1.0):
	set(value):
		text_color = value
		_refresh_material()

@export_range(0.0, 8.0, 0.1) var emission_energy: float = 2.5:
	set(value):
		emission_energy = value
		_refresh_material()

@export_range(16, 200, 4) var font_size: int = 64:
	set(value):
		font_size = value
		_refresh_text()

@export_range(0.0, 0.1, 0.001) var text_depth: float = 0.01:
	set(value):
		text_depth = value
		_refresh_text()

@export_range(0.001, 0.02, 0.001) var text_pixel_size: float = 0.005:
	set(value):
		text_pixel_size = value
		_refresh_text()

@export var text_local_position: Vector3 = Vector3(0.0, 0.0, 0.01):
	set(value):
		text_local_position = value
		_refresh_position()

# Color the plate's BACKGROUND becomes (dark, so the text glow pops).
@export var plate_bg_color: Color = Color(0.04, 0.06, 0.10):
	set(value):
		plate_bg_color = value
		_refresh_plate_bg()

@export_range(0.0, 5.0, 0.1) var plate_emission_energy: float = 0.4:
	set(value):
		plate_emission_energy = value
		_refresh_plate_bg()

# Click this in the Inspector to rebuild everything from scratch.
@export var refresh_now: bool = false:
	set(_v):
		refresh_now = false
		_full_rebuild()

var _text_mi: MeshInstance3D
var _text_mesh: TextMesh
var _text_material: StandardMaterial3D
var _plate: MeshInstance3D


func _ready() -> void:
	_full_rebuild()


func _full_rebuild() -> void:
	_plate = get_node_or_null("Stage/ScreenPlate") as MeshInstance3D
	if _plate == null:
		push_warning("console_preview: no Stage/ScreenPlate found")
		return

	# Tear down any previous text node (e.g. on script reload in @tool).
	var existing: Node = _plate.get_node_or_null("ScreenText")
	if existing != null:
		existing.queue_free()
	_text_mi = null

	# Build the TextMesh as a child of the plate. It inherits the plate's
	# tilt + position, so the text always lies ON the plate surface.
	_text_mi = MeshInstance3D.new()
	_text_mi.name = "ScreenText"
	_text_mesh = TextMesh.new()
	_text_material = StandardMaterial3D.new()
	_text_mi.mesh = _text_mesh
	_text_mi.material_override = _text_material
	_plate.add_child(_text_mi)

	_refresh_text()
	_refresh_material()
	_refresh_position()
	_refresh_plate_bg()


func _refresh_text() -> void:
	if _text_mesh == null:
		return
	_text_mesh.text = screen_text
	_text_mesh.font_size = font_size
	_text_mesh.depth = text_depth
	_text_mesh.pixel_size = text_pixel_size
	_text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _refresh_material() -> void:
	if _text_material == null:
		return
	_text_material.albedo_color = text_color
	_text_material.emission_enabled = true
	_text_material.emission = text_color
	_text_material.emission_energy_multiplier = emission_energy
	# Pop on top of the plate regardless of intervening geometry — the
	# text is supposed to glow visibly.
	_text_material.no_depth_test = true


func _refresh_position() -> void:
	if _text_mi == null:
		return
	_text_mi.position = text_local_position


# Replace the plate's bright emissive blue with a darker background so
# the text glow has contrast to pop against.
func _refresh_plate_bg() -> void:
	if _plate == null:
		return
	var existing: Material = _plate.material_override
	if existing == null or not (existing is StandardMaterial3D):
		return
	var src: StandardMaterial3D = existing
	var mat: StandardMaterial3D = src.duplicate()
	mat.albedo_color = plate_bg_color
	mat.emission_enabled = true
	mat.emission = plate_bg_color
	mat.emission_energy_multiplier = plate_emission_energy
	# Clear any leftover textures from prior SubViewport experiments.
	mat.albedo_texture = null
	mat.emission_texture = null
	_plate.material_override = mat
