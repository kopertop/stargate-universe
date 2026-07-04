class_name Stargate
extends Node3D

# Procedural Stargate ring. Builds an Ancient-style 9-chevron portal from
# Godot primitives so we don't need a custom .glb:
#
#   • Outer ring     — torus, dark steel + faint amber emissive (dormant state)
#   • Inner glyph band — flat ring riding the inner face of the torus
#   • 9 chevrons     — small trapezoidal brackets at 40° intervals
#   • Event horizon  — emissive plane in the center, hidden unless `active = true`
#
# Real-world canon: ~6.7 m outer diameter. We use 6 m so it reads big without
# eating the whole room. Stands upright (XY plane), faces -Z by default.

@export var radius_outer: float = 3.0   # ring outer edge
@export var radius_inner: float = 2.4   # ring inner edge (event-horizon size)
@export var ring_depth: float = 0.55    # how deep the ring is along Z
@export var chevron_count: int = 9
@export var active: bool = false:
	set(value):
		active = value
		_set_horizon_visible(value)

var _horizon: MeshInstance3D
var _horizon_ripples: Array[MeshInstance3D] = []
var _horizon_light: OmniLight3D
# Kawoosh plume — a cone that erupts OUT of the gate toward the room/camera (local
# -Z) on activation, then retracts into the flat puddle. Built hidden; animated by
# kawoosh(). This makes the "flush" read as coming AT the viewer, not spreading
# sideways in the ring plane.
var _kawoosh_plume: Node3D = null
# True only during the kawoosh burst, so the idle surface pulse in _process
# doesn't fight the burst tween animating _horizon.scale.
var _kawooshing: bool = false

func _ready() -> void:
	_build_outer_ring()
	_build_inner_glyph_band()
	_build_chevrons()
	_build_event_horizon()
	_set_horizon_visible(active)

func _process(delta: float) -> void:
	if not active:
		return
	if _horizon != null and not _kawooshing:
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.015
		_horizon.scale = Vector3(pulse, pulse, 1.0)
	for i in _horizon_ripples.size():
		var ripple: MeshInstance3D = _horizon_ripples[i]
		ripple.rotation.z += delta * (0.25 + float(i) * 0.18)


# The unstable-vortex "kawoosh": the event horizon erupts outward then settles
# back into the ring. Call the instant the chevrons lock and the wormhole forms.
# Self-contained on the gate (the surrounding ring spin is driven by the room).
func kawoosh() -> void:
	active = true
	if _horizon == null:
		return
	_kawooshing = true
	# The puddle just snaps to full (no sideways radial punch). The eruption is the
	# PLUME bursting OUT toward the room/camera, then collapsing back into the flat
	# event horizon — so the "flush" reads as coming at the viewer, not left/right.
	_horizon.scale = Vector3(1.0, 1.0, 1.0)
	if _kawoosh_plume != null:
		_kawoosh_plume.visible = true
		_kawoosh_plume.scale = Vector3(0.2, 0.2, 0.05)
		var pt: Tween = create_tween()
		# Erupt out toward the camera (full radius + full length), then suck back in.
		pt.tween_property(_kawoosh_plume, "scale", Vector3(1.15, 1.15, 1.0), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pt.tween_property(_kawoosh_plume, "scale", Vector3(0.6, 0.6, 0.18), 0.20)
		pt.tween_property(_kawoosh_plume, "scale", Vector3.ZERO, 0.30) \
			.set_trans(Tween.TRANS_SINE)
		pt.tween_callback(func() -> void:
			_kawooshing = false
			if _kawoosh_plume != null:
				_kawoosh_plume.visible = false)
	else:
		_kawooshing = false
	# Light flare that decays to the steady glow.
	if _horizon_light != null:
		var base_energy: float = 4.6
		_horizon_light.light_energy = 18.0
		var lt: Tween = create_tween()
		lt.tween_property(_horizon_light, "light_energy", base_energy, 0.55) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _set_horizon_visible(is_visible: bool) -> void:
	if _horizon != null:
		_horizon.visible = is_visible
	for ripple in _horizon_ripples:
		ripple.visible = is_visible
	if _horizon_light != null:
		_horizon_light.visible = is_visible

func _build_outer_ring() -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "OuterRing"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius_inner
	torus.outer_radius = radius_outer
	torus.ring_segments = 96
	torus.rings = 24
	mi.mesh = torus
	# Torus default lies flat on Y; rotate to stand upright facing -Z.
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	# Ancient-metal triplanar shader (dark steel, faint amber seam glow).
	mi.material_override = load("res://shaders/ancient_metal_ring.tres")
	add_child(mi)

func _build_inner_glyph_band() -> void:
	# A second, slightly smaller torus sitting inside the outer ring. Darker,
	# rougher — this is where the glyphs would be painted in a higher-fi pass.
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "GlyphBand"
	var torus: TorusMesh = TorusMesh.new()
	var band_width: float = (radius_outer - radius_inner) * 0.45
	torus.inner_radius = radius_inner + 0.01
	torus.outer_radius = radius_inner + 0.01 + band_width
	torus.ring_segments = 96
	torus.rings = 16
	mi.mesh = torus
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	# Darker/rougher Ancient-metal variant — the glyph band.
	mi.material_override = load("res://shaders/ancient_metal_band.tres")
	add_child(mi)

func _build_chevrons() -> void:
	# Each chevron has two parts: the outer bracket (a block sitting on top of
	# the ring's outer rim) and the inward-pointing tip (a small wedge that
	# crosses the ring inward toward the center). They're parented to a pivot
	# Node3D so we can rotate the pair as a unit around the gate's axis.
	# Brighter Ancient-metal variant with stronger orange-gold seam glow.
	var chev_mat: Material = load("res://shaders/ancient_metal_chevron.tres")

	# Bracket dimensions (block hugging the outer rim).
	var bracket_w: float = 0.85   # along the tangent
	var bracket_h: float = 0.55   # radially outward
	var bracket_d: float = ring_depth * 1.15  # along the gate's Z axis (a bit proud)

	# Tip dimensions (wedge crossing the rim inward).
	var tip_w: float = 0.42
	var tip_h: float = 0.32       # how far it pokes inward past the rim
	var tip_d: float = ring_depth * 1.30

	for i in chevron_count:
		var angle_deg: float = 90.0 - (360.0 / float(chevron_count)) * float(i)
		var pivot: Node3D = Node3D.new()
		pivot.name = "Chevron%d" % i
		pivot.rotation_degrees = Vector3(0.0, 0.0, angle_deg)
		add_child(pivot)

		# Bracket sits at the outer rim, pushed +Y in pivot-local space.
		var bracket: MeshInstance3D = MeshInstance3D.new()
		bracket.name = "Bracket"
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(bracket_w, bracket_h, bracket_d)
		bracket.mesh = bm
		bracket.material_override = chev_mat
		bracket.position = Vector3(0.0, radius_outer + bracket_h * 0.45, 0.0)
		pivot.add_child(bracket)

		# Tip sits inside the rim, also +Y in pivot-local but smaller, more inward.
		var tip: MeshInstance3D = MeshInstance3D.new()
		tip.name = "Tip"
		var tm: BoxMesh = BoxMesh.new()
		tm.size = Vector3(tip_w, tip_h, tip_d)
		tip.mesh = tm
		tip.material_override = chev_mat
		# Bridge between bracket and inner ring — sit halfway between radius_inner
		# and radius_outer so the wedge crosses the rim.
		tip.position = Vector3(0.0, radius_outer - tip_h * 0.4, 0.0)
		pivot.add_child(tip)

func _build_event_horizon() -> void:
	# Center plane: emissive blue puddle for the active gate. Use a thin
	# cylinder rotated onto the gate's Z axis so it reads as a vertical disc.
	_horizon = MeshInstance3D.new()
	_horizon.name = "EventHorizon"
	var disk: CylinderMesh = CylinderMesh.new()
	disk.top_radius = radius_inner - 0.08
	disk.bottom_radius = radius_inner - 0.08
	disk.height = 0.08
	disk.radial_segments = 96
	disk.rings = 2
	_horizon.mesh = disk
	_horizon.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	# Animated energy-surface shader (scrolling noise + Fresnel rim).
	_horizon.material_override = load("res://shaders/event_horizon.tres")
	_horizon.visible = active
	add_child(_horizon)

	# (Removed the additive ripple toruses — built with rings=8 they rendered as
	# hard WHITE OCTAGON outlines inside the puddle. The shader swirl carries the
	# energy now; the plume below carries the eruption.)

	# Kawoosh plume: a cone whose wide mouth faces the room (local -Z, toward the
	# camera) and apex sits at the gate plane. kawoosh() scales this pivot from 0
	# out and back, so the flush erupts TOWARD the viewer (not sideways).
	_kawoosh_plume = Node3D.new()
	_kawoosh_plume.name = "KawooshPlume"
	var plume_len: float = 3.5
	var cone: MeshInstance3D = MeshInstance3D.new()
	cone.name = "PlumeCone"
	var cone_mesh: CylinderMesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.06                       # narrow at the gate (apex)
	cone_mesh.bottom_radius = radius_inner - 0.10     # wide mouth toward the camera
	cone_mesh.height = plume_len
	cone_mesh.radial_segments = 48
	cone.mesh = cone_mesh
	# Cylinder axis is +Y; rotate +90° about X so +Y(apex)→+Z(gate) and -Y(mouth)→
	# -Z(room). Offset so the apex sits at the gate plane and the body extends to -Z.
	cone.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	cone.position = Vector3(0.0, 0.0, -plume_len * 0.5)
	var plume_mat: StandardMaterial3D = StandardMaterial3D.new()
	plume_mat.albedo_color = Color(0.30, 0.65, 1.0, 0.45)
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume_mat.emission_enabled = true
	plume_mat.emission = Color(0.35, 0.7, 1.0, 1.0)
	plume_mat.emission_energy_multiplier = 2.2
	cone.material_override = plume_mat
	_kawoosh_plume.add_child(cone)
	_kawoosh_plume.scale = Vector3.ZERO
	_kawoosh_plume.visible = false
	add_child(_kawoosh_plume)

	# Soft light spilling from the puddle so the room lights up when active.
	_horizon_light = OmniLight3D.new()
	_horizon_light.name = "HorizonLight"
	_horizon_light.light_color = Color(0.55, 0.80, 1.0, 1.0)
	_horizon_light.light_energy = 4.6
	_horizon_light.omni_range = 16.0
	_horizon_light.position = Vector3(0.0, 0.0, 0.6)
	_horizon_light.visible = active
	add_child(_horizon_light)
