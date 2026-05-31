class_name PoiNode
extends Node3D

# A discoverable point-of-interest on a planet surface — the generic sibling of
# the mineable ResourceNode. POIs aren't mined; they exist to be FOUND by the
# Kino's auto-search (which scans group "discoverable"), at which point they
# toast a named find ("Kino found: Ancient Ruin") and light up on the compass
# with their category's colour/glyph (planet_compass.gd reads `poi_category`).
#
# Discovery survives save/load: the planet seed is fixed, so a node's stable name
# maps to the same world position, and GameState.discovered_pois records it.

@export var poi_category: String = "ruin"      # ruin | ore | water | debris (compass styling key)
@export var poi_label: String = "Point of interest"

var _discovered: bool = false

func _ready() -> void:
	# "discoverable" — scanned by the drone's auto-search detection sweep.
	# "poi" — scanned by the compass to draw a per-category pip.
	add_to_group("discoverable")
	add_to_group("poi")
	_discovered = GameState.is_poi_discovered(name)
	_build_visual()

func is_discovered() -> bool:
	return _discovered

# `announce` is true only when the Kino's auto-search is the finder, so the toast
# names it. Discovery is recorded either way (it shows on the compass).
func _mark_discovered(announce: bool = false) -> void:
	if _discovered:
		return
	_discovered = true
	GameState.discover_poi(name, poi_category, poi_label, announce)

# A simple, category-distinct silhouette with an emissive accent so it reads as a
# landmark from the air. Built procedurally — no per-POI art assets needed yet.
func _build_visual() -> void:
	match poi_category:
		"ore":
			_add_mesh(_crystal_mesh(), Color(1.0, 0.55, 0.2), 1.4, Vector3(0.0, 1.0, 0.0))
		"water":
			_add_mesh(_disc_mesh(), Color(0.3, 0.85, 0.95), 0.8, Vector3.ZERO)
		"debris":
			_add_mesh(_box_mesh(Vector3(2.2, 1.1, 1.6)), Color(0.7, 0.73, 0.78), 0.2, Vector3(0.0, 0.55, 0.0), 0.5)
		_:  # "ruin" and anything unknown — a cluster of broken pillars.
			_add_mesh(_box_mesh(Vector3(0.7, 4.2, 0.7)), Color(0.78, 0.6, 1.0), 0.5, Vector3(-0.9, 2.1, 0.0), 0.1)
			_add_mesh(_box_mesh(Vector3(0.7, 2.8, 0.7)), Color(0.78, 0.6, 1.0), 0.5, Vector3(0.9, 1.4, 0.4), -0.18)


func _add_mesh(mesh: Mesh, color: Color, emission_energy: float, offset: Vector3, tilt: float = 0.0) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission_energy
	mi.material_override = mat
	mi.position = offset
	if tilt != 0.0:
		mi.rotation.z = tilt
	add_child(mi)


func _box_mesh(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	return m


func _crystal_mesh() -> PrismMesh:
	var m: PrismMesh = PrismMesh.new()
	m.size = Vector3(1.4, 2.4, 1.4)
	return m


func _disc_mesh() -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = 2.6
	m.bottom_radius = 2.6
	m.height = 0.18
	return m
