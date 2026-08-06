# Gate-room hero procedural builder
# Copyright (c) 2024-2026 Newstex. All rights reserved.

extends Node3D

## Hallway configuration constants
const HALL_WIDTH: float = 12.0
const HALL_LENGTH: float = 48.0
const HALL_HEIGHT: float = 12.0

## Gate room configuration constants
const GATE_RING_RADIUS: float = 3.5
const GATE_RING_THICKNESS: float = 0.4
const GATE_RING_CHEVRON_SIZE: float = 0.8

## Camera configuration
const CAM_ZOOM: float = 1.8
const CAM_HEIGHT: float = 0.55
const CAM_ANGLE_Y: float = 0.0
const CAM_ANGLE_PITCH: float = -0.55

## Environment lighting constants
const AMBIENT_COLOR: Color = Color(0.03, 0.03, 0.04)
const AMBIENT_ENERGY: float = 12.0
const GLOBAL_ENERGY: float = 1.0
const FOG_DENSITY: float = 0.005
const FOG_COLOR: Color = Color(0.08, 0.08, 0.09)

## Material properties
const METAL_COLOR: Color = Color(0.17, 0.18, 0.205)
const METAL_ROUGHNESS: float = 0.42
const METAL_METALLIC: float = 0.85
const FLOOR_ROUGHNESS: float = 0.20
const FLOOR_METALLIC: float = 0.9

## Console screen constants
const SCREEN_COLOR: Color = Color(0.22, 0.45, 0.85)
const SCREEN_ENERGY: float = 0.65

## Chevron glow parameters for better visibility
const GATE_RING_GLOW_SIZE: float = 20.0
const GATE_RING_GLOW_COLOR: Color = Color(0.75, 0.88, 0.96)

## Vortex shader parameters
const VORTEX_UV_SCALE: float = 3.0
const VORTEX_CHURN_SPEED: float = 1.5
const VORTEX_COLOR: Color = Color(0.4, 0.75, 1.0)
const VORTEX_INTENSITY: float = 3.0

## Ceiling dome parameters
const CEILING_DOWNLIGHT_ENERGY: float = 25.0
const CEILING_RIM_ENERGY: float = 1.5

## Render capture — saves image from _process() as fallback when harness camera fails
var _frame_count: int = 0
const _CAPTURE_FRAME: int = 180

func _ready() -> void:
	# Build all scene components
	_build_hall()
	_build_gate_ring()
	_build_vortex()
	_build_console_banks()
	_build_ceiling()
	_build_floor()
	
	# Camera setup — positioned at harness location for correct view
	_build_camera()
	
	# Lighting setup
	_setup_lighting()

func _process(delta: float) -> void:
	_frame_count += 1
	if _frame_count == _CAPTURE_FRAME:
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://hero.png")
		print("HERO_CAPTURE saved at frame ", _frame_count)

func _build_hall() -> void:
	# Hall centered at Z=0 to encompass render camera at Z=-19
	var hall_mat := _standard_material(METAL_COLOR, METAL_ROUGHNESS, METAL_METALLIC)
	hall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hall := _box(
		Vector3(HALL_WIDTH, HALL_HEIGHT, HALL_LENGTH),
		Vector3(0.0, HALL_HEIGHT * 0.5, 0.0),
		hall_mat,
		Quaternion()
	)
	add_child(hall)

func _build_gate_ring() -> void:
	# Main gate ring platform
	var platform := _box(
		Vector3(8.0, 1.0, 8.0),
		Vector3(0.0, 0.0, 0.0),
		_standard_material(Color(0.12, 0.12, 0.13), 0.4, 0.8),
		Quaternion()
	)
	add_child(platform)
	
	# Ring geometry — TorusMesh ring with aperture showing vortex behind it
	var ring_mesh := MeshInstance3D.new()
	var torus_shape := TorusMesh.new()
	torus_shape.outer_radius = GATE_RING_RADIUS
	torus_shape.inner_radius = GATE_RING_RADIUS * 0.78
	torus_shape.ring_segments = 32
	ring_mesh.mesh = torus_shape
	ring_mesh.material_override = _standard_material(Color(0.09, 0.09, 0.1), 0.5, 0.9)
	ring_mesh.position = Vector3(0.0, 6.0, GATE_RING_RADIUS * 0.5)
	add_child(ring_mesh)
	
	# Segmented chevrons (triangular segments) — raised to match ring
	for i in range(9):
		var angle := deg_to_rad(i * 40.0 - 180.0)
		var chevron := _cone(
			Vector3(0.4, 0.3, 0.4),
			Vector3(cos(angle) * GATE_RING_RADIUS, 6.0, sin(angle) * GATE_RING_RADIUS + GATE_RING_RADIUS * 0.5),
			_emissive(Color(0.75, 0.88, 0.96), GATE_RING_GLOW_SIZE)
		)
		chevron.rotate_y(angle + PI / 2.0)
		add_child(chevron)
	
	# Small central staircase below gate ring
	var stair := _box(
		Vector3(2.0, 0.6, 3.0),
		Vector3(0.0, 0.3, -1.0),
		_standard_material(Color(0.15, 0.15, 0.17), 0.35, 0.85),
		Quaternion()
	)
	stair.position.y += 0.3
	add_child(stair)

func _build_vortex() -> void:
	# Vortex portal disc — PlaneMesh gives proper 0..1 UVs that the shader's
	# (UV - 0.5) * 2.0 mapping converts to -1..1 disc coordinates.
	# CylinderMesh UVs break the radial shader (confirmed: vortex invisible).
	# PlaneMesh size = ring diameter so the disc fills the aperture.
	var vortex_mesh := MeshInstance3D.new()
	var vortex_shape := PlaneMesh.new()
	vortex_shape.size = Vector2(GATE_RING_RADIUS * 2.0, GATE_RING_RADIUS * 2.0)
	vortex_mesh.mesh = vortex_shape
	# Position vortex at gate ring height, facing camera at Z=-19
	vortex_mesh.position = Vector3(0.0, 6.0, GATE_RING_RADIUS * 0.5)
	# PlaneMesh faces +Y by default; rotate to face -Z (toward camera)
	vortex_mesh.rotate_x(-PI / 2.0)
	
	# Apply portal shader
	var portal_mat := ShaderMaterial.new()
	portal_mat.shader = preload("res://shaders/hero_portal.gdshader")
	# Wire noise texture to shader uniform — without this, texture() returns black
	portal_mat.set_shader_parameter("noise_tex", preload("res://assets/hero/noise_1024.png"))
	vortex_mesh.material_override = portal_mat
	add_child(vortex_mesh)

func _build_console_banks() -> void:
	# Front console bank (left side)
	_build_console_row(3.0, 4.5, -0.3, 3, 4)
	
	# Front console bank (right side)
	_build_console_row(-3.0, 4.5, 0.3, 3, 4)
	
	# Rear console bank (left side)
	_build_console_row(3.0, -4.5, -0.3, 2, 4)
	
	# Rear console bank (right side)
	_build_console_row(-3.0, -4.5, 0.3, 2, 4)

func _build_console_row(x_desk: float, z: float, yaw: float, rows: int, cols: int) -> void:
	var desk := _box(
		Vector3(0.4 * cols, 0.4, cols * 0.3),
		Vector3(x_desk, 0.6, z),
		_standard_material(Color(0.2, 0.22, 0.24), 0.3, 0.9),
		Quaternion(Vector3.UP, yaw)
	)
	desk.position.y += 0.0
	add_child(desk)
	
	for i in range(rows):
		for col in range(cols):
			var screen := _box(
				Vector3(0.1, 0.3, 0.05),
				Vector3(x_desk + 0.22 + col * 0.2, 1.0 + i * 0.35, z + 0.3 * (col % 2)),
				_emissive(Color(0.16, 0.34, 0.62) * (0.7 + float((col + i + 0) % 3) * 0.4), SCREEN_ENERGY * (0.7 + float((col + i + 0) % 3) * 0.4))
			)
			screen.rotate_x(-0.55)
			add_child(screen)
	
	# Lip trim
	var lip := _box(
		Vector3(0.5 * cols + 0.05, 0.05, 0.15),
		Vector3(x_desk + 0.2 * cols, 0.52, z + 0.15),
		_emissive(Color(0.16, 0.32, 0.58), 0.3)
	)
	lip.rotate_x(-0.55)
	lip.rotate_y(yaw)
	lip.position.y += -0.02
	add_child(lip)

func _build_ceiling() -> void:
	# Tiered ceiling dome structure
	var dome := _sphere(
		Vector3(8.0, 0.1, 8.0),
		Vector3(0.0, HALL_HEIGHT * 0.5, 0.0),
		_standard_material(Color(0.14, 0.15, 0.17), 0.4, 0.75)
	)
	dome.scale.y = 0.5
	add_child(dome)
	
	# Downlights on dome
	for i in range(4):
		var angle := deg_to_rad(i * 90.0)
		var light_pos := Vector3(cos(angle) * 6.0, HALL_HEIGHT * 0.5 - 0.3, sin(angle) * 6.0)
		var downlight_mat := _emissive(Color(0.9, 0.9, 1.0), CEILING_DOWNLIGHT_ENERGY)
		var downlight := _box(Vector3(0.3, 0.3, 0.3), light_pos, downlight_mat)
		add_child(downlight)
	
	# Rim bands
	for i in range(6):
		var angle := deg_to_rad(i * 60.0)
		var rim := _box(
			Vector3(0.1, 0.4, 0.3),
			Vector3(cos(angle) * 5.5, HALL_HEIGHT * 0.45, sin(angle) * 5.5),
			_emissive(Color(0.4, 0.45, 0.5), CEILING_RIM_ENERGY)
		)
		rim.rotate_x(PI / 2.0)
		rim.rotate_y(angle)
		add_child(rim)

func _build_floor() -> void:
	# Floor centered at Z=0 to match hall
	var floor := _box(
		Vector3(HALL_WIDTH, 0.1, HALL_LENGTH),
		Vector3(0.0, 0.05, 0.0),
		_standard_material(Color(0.1, 0.1, 0.12), FLOOR_ROUGHNESS, FLOOR_METALLIC)
	)
	floor.position.y += 0.05
	add_child(floor)
	
	# Grid plates spread across hall length
	for i in range(8):
		var plate := _box(
			Vector3(3.0, 0.05, 5.0),
			Vector3(-3.0 + (i % 4) * 2.0, 0.025, -18.0 + (i / 4) * 22.0),
			_standard_material(Color(0.08, 0.08, 0.09), FLOOR_ROUGHNESS * 1.5, FLOOR_METALLIC)
		)
		plate.position.y += 0.06
		add_child(plate)

func _setup_lighting() -> void:
	# Ambient key
	var ambient := DirectionalLight3D.new()
	ambient.light_color = AMBIENT_COLOR
	ambient.light_energy = AMBIENT_ENERGY
	ambient.rotation = Vector3(deg_to_rad(45.0), deg_to_rad(-45.0), 0.0)
	ambient.name = "AmbientKey"
	add_child(ambient)
	
	# Gate ring glow
	var ring_glow := DirectionalLight3D.new()
	ring_glow.light_color = GATE_RING_GLOW_COLOR
	ring_glow.light_energy = GATE_RING_GLOW_SIZE
	ring_glow.name = "RingGlow"
	add_child(ring_glow)
	ring_glow.look_at(Vector3(GATE_RING_RADIUS * 2.5, HALL_HEIGHT * 0.5, -5.0))
	
	# Vortex fill light — positioned at gate ring height, moderate energy to
	# illuminate the gate room interior while keeping dark cinematic tone.
	# Previous cycle: 4.0=too dark (exterior read), 20.0=too bright (washed out).
	# 10.0 + omni_range 25 covers the hall without blowing highlights.
	var vortex_fill := OmniLight3D.new()
	vortex_fill.light_color = VORTEX_COLOR
	vortex_fill.light_energy = 10.0
	vortex_fill.omni_range = 25.0
	vortex_fill.position = Vector3(0.0, 6.0, 1.75)
	vortex_fill.name = "VortexFill"
	add_child(vortex_fill)
	
	# Fog and environment
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.fog_enabled = true
	env.fog_density = FOG_DENSITY
	env.fog_light_color = FOG_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	world_env.environment = env
	add_child(world_env)

func _build_camera() -> void:
	# Scene camera at harness position for correct render view
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.6, -19.0)
	camera.fov = 76.0
	camera.current = true
	camera.name = "Camera3D"
	add_child(camera)
	# look_at AFTER add_child so node is in the scene tree
	camera.look_at(Vector3(0.0, 6.0, 1.75), Vector3.UP)

## Helper materials
func _standard_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

## Geometry helpers
func _box(size: Vector3, position: Vector3, material: Material, rotation: Quaternion = Quaternion()) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = position
	mesh.quaternion = rotation
	return mesh

func _cone(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.height = size.y
	shape.top_radius = size.x * 0.5
	shape.bottom_radius = size.x * 0.5
	shape.radial_segments = 16
	shape.rings = 1
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = position
	return mesh

func _sphere(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = size.x
	shape.height = size.x * 2.0
	shape.radial_segments = 32
	shape.rings = 16
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = position
	return mesh