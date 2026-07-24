extends CharacterBody3D

# Hostile demo drone — hover target for Mixamo combat + Target Lock.
# Built from panel pieces that crack off on hit (procedural, no external mesh).
# Group: combat_target. Hits call take_damage().

signal damaged(remaining_hp: int, max_hp: int)
signal destroyed

const GROUP_NAME: String = "combat_target"

const HIT_SFX: Array[String] = [
	"res://sounds/impact_glass_000.ogg",
	"res://sounds/impact_glass_001.ogg",
	"res://sounds/impact_metal_000.ogg",
	"res://sounds/impact_metal_heavy_000.ogg",
]
const KILL_SFX: String = "res://sounds/break.ogg"

@export var max_hp: int = 28
@export var hover_amp: float = 0.18
@export var hover_hz: float = 0.85
@export var drift_radius: float = 0.35
@export var lock_radius: float = 0.55

var hp: int = 4
var _origin: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _alive: bool = true
var _core: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _lock_mark: MeshInstance3D = null
var _core_mat: StandardMaterial3D = null
var _panels: Array[MeshInstance3D] = []
var _panel_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	hp = max_hp
	_origin = global_position
	add_to_group(GROUP_NAME)
	collision_layer = 1
	collision_mask = 0
	_build_visuals()
	_build_collision()


func is_alive() -> bool:
	return _alive and hp > 0


func get_lock_point() -> Vector3:
	return global_position + Vector3.UP * 0.15


func set_lock_highlighted(on: bool) -> void:
	if _lock_mark != null:
		_lock_mark.visible = on
	if _core_mat != null:
		_core_mat.emission_energy_multiplier = 8.0 if on else 4.5
		_core_mat.albedo_color = Color(1.0, 0.35, 0.25) if on else Color(0.85, 0.2, 0.15)


func take_damage(amount: int = 1) -> void:
	if not _alive:
		return
	hp = maxi(0, hp - maxi(1, amount))
	damaged.emit(hp, max_hp)
	_play_hit_sfx()
	_flash_hit()
	_scar_remaining()
	# Tiny hit sparks only — no mid-air panel leftovers.
	_spawn_hit_sparks()
	if hp <= 0:
		_die()


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_t += delta
	var bob: float = sin(_t * TAU * hover_hz) * hover_amp
	var drift: Vector3 = Vector3(
		sin(_t * 0.7) * drift_radius,
		0.0,
		cos(_t * 0.55) * drift_radius
	)
	global_position = _origin + drift + Vector3.UP * bob
	if _ring != null:
		_ring.rotate_y(delta * 1.6)


const SCRAP_SCRIPT: Script = preload("res://scripts/drone_scrap_part.gd")


func _die() -> void:
	_alive = false
	destroyed.emit()
	set_lock_highlighted(false)
	_play_sfx(KILL_SFX)
	# Disable body FIRST so floor rays never land on this drone.
	collision_layer = 0
	collision_mask = 0
	var drop_at: Vector3 = global_position
	var parent_n: Node = get_parent()
	# Hide the whole assembled drone — scrap is fresh loot, not reused meshes.
	visible = false
	_spawn_death_burst(drop_at, parent_n)
	_spawn_falling_scrap(drop_at, parent_n)
	await get_tree().create_timer(0.2).timeout
	queue_free()


func _scrap_drop_count() -> int:
	# Size / toughness → 1–3 floor scraps.
	if max_hp >= 24 or lock_radius >= 0.6:
		return 3
	if max_hp >= 10 or lock_radius >= 0.4:
		return 2
	return 1


func _spawn_falling_scrap(at: Vector3, parent_n: Node) -> void:
	if parent_n == null:
		return
	var n: int = _scrap_drop_count()
	for i in n:
		var ang: float = TAU * float(i) / float(n) + randf_range(-0.3, 0.3)
		var outward := Vector3(cos(ang), 0.0, sin(ang))
		var spawn_at: Vector3 = at + outward * 0.15 + Vector3.UP * 0.1
		var vel: Vector3 = outward * randf_range(1.6, 2.8) + Vector3.UP * randf_range(2.5, 4.0)
		var grant: int = 2 if i == 0 else 1
		SCRAP_SCRIPT.call("spawn_loot", parent_n, spawn_at, vel, grant)


func _spawn_hit_sparks() -> void:
	var parent_n: Node = get_parent()
	if parent_n == null:
		return
	var burst := GPUParticles3D.new()
	burst.amount = 10
	burst.lifetime = 0.28
	burst.one_shot = true
	burst.explosiveness = 1.0
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 70.0
	pmat.initial_velocity_min = 1.5
	pmat.initial_velocity_max = 3.5
	pmat.gravity = Vector3(0.0, -8.0, 0.0)
	burst.process_material = pmat
	var draw := BoxMesh.new()
	draw.size = Vector3(0.04, 0.04, 0.04)
	burst.draw_pass_1 = draw
	parent_n.add_child(burst)
	burst.global_position = global_position
	burst.emitting = true
	get_tree().create_timer(0.4).timeout.connect(burst.queue_free)


func _flash_hit() -> void:
	if _core_mat == null:
		return
	var base_e: float = 8.0 if (_lock_mark != null and _lock_mark.visible) else 4.5
	_core_mat.emission_energy_multiplier = 14.0
	var tw := create_tween()
	tw.tween_property(_core_mat, "emission_energy_multiplier", base_e, 0.12)


func _scar_remaining() -> void:
	var hurt: float = 1.0 - float(hp) / float(maxi(1, max_hp))
	if _core_mat != null:
		_core_mat.albedo_color = Color(0.85, 0.2, 0.15).lerp(Color(0.25, 0.08, 0.06), hurt)
		_core_mat.emission = Color(1.0, 0.25, 0.12).lerp(Color(1.0, 0.55, 0.1), hurt)
	for mat in _panel_mats:
		if mat == null:
			continue
		mat.albedo_color = Color(0.55, 0.58, 0.62).lerp(Color(0.2, 0.15, 0.12), hurt)
		mat.emission_energy_multiplier = lerpf(1.2, 3.5, hurt)


func _spawn_death_burst(at: Vector3, parent_n: Node) -> void:
	if parent_n == null:
		return
	# Soft spark burst only — short life, tiny draw, so it never reads as scrap.
	var burst := GPUParticles3D.new()
	burst.amount = 18
	burst.lifetime = 0.35
	burst.one_shot = true
	burst.explosiveness = 1.0
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0.0, 1.0, 0.0)
	pmat.spread = 100.0
	pmat.initial_velocity_min = 1.5
	pmat.initial_velocity_max = 4.0
	pmat.gravity = Vector3(0.0, -12.0, 0.0)
	pmat.scale_min = 0.4
	pmat.scale_max = 0.9
	burst.process_material = pmat
	var draw := SphereMesh.new()
	draw.radius = 0.02
	draw.height = 0.04
	burst.draw_pass_1 = draw
	parent_n.add_child(burst)
	burst.global_position = at
	burst.emitting = true
	get_tree().create_timer(0.5).timeout.connect(burst.queue_free)


func _play_hit_sfx() -> void:
	if HIT_SFX.is_empty():
		return
	_play_sfx(HIT_SFX[randi() % HIT_SFX.size()])


func _play_sfx(path: String) -> void:
	var audio_n: Node = get_node_or_null("/root/Audio")
	if audio_n != null and audio_n.has_method("play"):
		audio_n.call("play", path)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = lock_radius
	shape.shape = sphere
	add_child(shape)


func _build_visuals() -> void:
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(0.85, 0.2, 0.15)
	_core_mat.emission_enabled = true
	_core_mat.emission = Color(1.0, 0.25, 0.12)
	_core_mat.emission_energy_multiplier = 4.5

	_core = MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.22
	body.height = 0.44
	_core.mesh = body
	_core.material_override = _core_mat
	add_child(_core)

	# Armored panels around the core — these crack off on successive hits.
	var offsets: Array[Vector3] = [
		Vector3(0.32, 0.05, 0.0),
		Vector3(-0.32, 0.05, 0.0),
		Vector3(0.0, 0.05, 0.32),
		Vector3(0.0, 0.05, -0.32),
		Vector3(0.22, 0.22, 0.22),
		Vector3(-0.22, -0.1, 0.22),
	]
	for i in offsets.size():
		var panel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.06, 0.22)
		panel.mesh = box
		var pmat := StandardMaterial3D.new()
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.albedo_color = Color(0.55, 0.58, 0.62)
		pmat.emission_enabled = true
		pmat.emission = Color(0.35, 0.55, 0.75)
		pmat.emission_energy_multiplier = 1.2
		panel.material_override = pmat
		var outward: Vector3 = offsets[i]
		if outward.length_squared() > 0.0001:
			panel.transform = Transform3D(Basis.looking_at(outward.normalized(), Vector3.UP), outward)
		else:
			panel.position = outward
		add_child(panel)
		_panels.append(panel)
		_panel_mats.append(pmat)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.52
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.35, 0.85, 1.0, 0.85)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 0.7, 1.0)
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = ring_mat
	_ring.rotation.x = deg_to_rad(70.0)
	add_child(_ring)

	_lock_mark = MeshInstance3D.new()
	var mark := TorusMesh.new()
	mark.inner_radius = 0.62
	mark.outer_radius = 0.7
	_lock_mark.mesh = mark
	var mark_mat := StandardMaterial3D.new()
	mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.95)
	mark_mat.emission_enabled = true
	mark_mat.emission = Color(1.0, 0.75, 0.15)
	mark_mat.emission_energy_multiplier = 5.0
	mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lock_mark.material_override = mark_mat
	_lock_mark.visible = false
	add_child(_lock_mark)
