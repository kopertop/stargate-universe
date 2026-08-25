extends Node

# Lighting + vent-burst + gate-collapse module for the gate room. Extracted from
# gate_room.gd to decompose the god object. Added as a child Node by the main
# script and called via the host reference.

const AncientGlowScript: Script = preload("res://scripts/ancient_glow.gd")
#
# Owns: _build_lighting_props, open_dark, flicker_lights_up, apply_flicker_level,
# collapse_blackout, flashlights_during_dark, collapse_gate, vent_gate_sides,
# spawn_vent_burst.
#
# State vars moved here: flicker_pairs, open_env, open_ambient0.
# State vars that stay on the host (accessed via host.): _glow_mat, _glow_energy0,
# _gate_ring, _stargate, _chevron_glows, _chevron_rig, _gate_forced_open,
# _gate_hum_sfx, _gate_loop_sfx, _gate_shutdown_sfx, _co_skip.

# Host reference (the gate_room.gd Node3D). Set by setup() before any calls.
var host: Node3D = null

# Snapshot of [Light3D, original_energy] pairs for the flicker sequence.
var flicker_pairs: Array = []

# Dark-open: the duplicated env + its original ambient energy, so flicker_lights_up
# can restore the room ambient it crushed for the establishing shot.
var open_env: Environment = null
var open_ambient0: float = 1.35


# One-time wiring — call after adding this node as a child of the host.
func setup(room: Node3D) -> void:
	host = room


# ─── Build-time: light props ────────────────────────────────────────────────

# Atmospheric uplights, gate spotlights, ceiling fill, door-arch pool, gate fog
# volume, and the Ancient glow pulse on ceiling strips.
func build_lighting_props() -> void:
	# Atmospheric uplights — amber OmniLights at floor level pointed up by
	# placement, washing the upper walls warm. Plus dedicated SpotLights aimed
	# at the gate from below.
	var half_x: float = host.room_size.x * 0.5
	var half_z: float = host.room_size.y * 0.5

	# Floor uplights around the perimeter (4 corners + 2 mid-walls).
	var uplight_positions: Array = [
		Vector3(-half_x + 2.0, 0.5,  half_z - 2.0),
		Vector3( half_x - 2.0, 0.5,  half_z - 2.0),
		Vector3(-half_x + 2.0, 0.5, -half_z + 2.0),
		Vector3( half_x - 2.0, 0.5, -half_z + 2.0),
		Vector3(-half_x + 2.0, 0.5, 0.0),
		Vector3( half_x - 2.0, 0.5, 0.0),
	]
	for p in uplight_positions:
		var l: OmniLight3D = OmniLight3D.new()
		l.light_color = Color(0.42, 0.58, 0.95, 1.0)   # cool blue wash (was amber)
		l.light_energy = 1.6
		l.omni_range = 12.0
		l.omni_attenuation = 1.6
		l.position = p
		host._world.add_child(l)

	# Gate uplighting: 1 spot from directly in front, 2 from the sides.
	# look_at() requires the node to already be inside the tree, so add_child
	# before re-orienting; otherwise the call quietly errors and the spotlight
	# points along its default axis.
	var gate_center: Vector3 = Vector3(0.0, host.interactables.gate_center_y(), host.GATE_Z)
	# Front spot — cool, to pick the gate ring out of the dark (was warm).
	var front_spot: SpotLight3D = SpotLight3D.new()
	front_spot.light_color = Color(0.55, 0.7, 1.0, 1.0)
	front_spot.light_energy = 3.5
	front_spot.spot_range = 14.0
	front_spot.spot_angle = 35.0
	front_spot.position = Vector3(0.0, 1.2, gate_center.z - 5.5)
	host._world.add_child(front_spot)
	front_spot.look_at(gate_center, Vector3.UP)
	# Side spots
	for sx in [-1.0, 1.0]:
		var side: SpotLight3D = SpotLight3D.new()
		side.light_color = Color(0.5, 0.66, 1.0, 1.0)
		side.light_energy = 2.4
		side.spot_range = 12.0
		side.spot_angle = 32.0
		side.position = Vector3(sx * 5.5, 1.2, gate_center.z - 1.5)
		host._world.add_child(side)
		side.look_at(gate_center, Vector3.UP)

	# Soft top key light — directional, slightly cool. Establishes the "shafts
	# from above" feel even without a volumetric pass.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color(0.78, 0.85, 1.0, 1.0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	key.shadow_opacity = 0.45
	# Tilt to come "from above and front" (-Y mostly, slight +Z).
	key.rotation = Vector3(deg_to_rad(-72.0), deg_to_rad(15.0), 0.0)
	host._world.add_child(key)

	# Ceiling fill — 6 downward Omnis in a 2×3 grid below the ceiling. Wide range
	# so each one washes a quadrant. Cool tint so warm uplights still pop on the
	# walls without the whole room going flat-grey.
	var ceiling_fill_y: float = host.ceiling_height - 0.8
	var fill_positions: Array = [
		Vector3(-half_x * 0.55, ceiling_fill_y,  half_z * 0.55),
		Vector3( half_x * 0.55, ceiling_fill_y,  half_z * 0.55),
		Vector3(-half_x * 0.55, ceiling_fill_y, 0.0),
		Vector3( half_x * 0.55, ceiling_fill_y, 0.0),
		Vector3(-half_x * 0.55, ceiling_fill_y, -half_z * 0.55),
		Vector3( half_x * 0.55, ceiling_fill_y, -half_z * 0.55),
	]
	for p in fill_positions:
		var fill: OmniLight3D = OmniLight3D.new()
		fill.light_color = Color(0.62, 0.72, 0.95, 1.0)
		fill.light_energy = 1.5
		fill.omni_range = 15.0
		fill.omni_attenuation = 1.4
		fill.position = p
		host._world.add_child(fill)

	# Door-archway pool — spotlight aimed straight down through the -Z arch so
	# the exit reads as "lit doorway" instead of black hole. Player sees it from
	# across the room and walks toward it.
	var door_spot: SpotLight3D = SpotLight3D.new()
	door_spot.name = "DoorArchSpot"
	door_spot.light_color = Color(1.0, 0.78, 0.45, 1.0)
	door_spot.light_energy = 5.5
	door_spot.spot_range = 8.0
	door_spot.spot_angle = 38.0
	door_spot.position = Vector3(0.0, host.ceiling_height - 0.6, -half_z + 1.2)
	host._world.add_child(door_spot)

	# --- Volumetric FogVolume at the gate ring -------------------------------
	# A localized fog cloud around the event horizon — atmospheric haze where
	# the gate's glow scatters into, giving the ring real depth when viewed
	# from across the room. Enabled by the gate-room-environment.tres
	# volumetric_fog_enabled=true; this FogVolume adds localized density on
	# top of the global low-density haze.
	var gate_fog := FogVolume.new()
	gate_fog.name = "GateFogVolume"
	gate_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	gate_fog.size = Vector3(6.0, 5.0, 3.0)
	gate_fog.position = Vector3(0.0, host.interactables.gate_center_y(), host.GATE_Z)
	var gate_fog_mat := FogMaterial.new()
	gate_fog_mat.density = 0.15
	gate_fog_mat.albedo = Color(0.3, 0.5, 0.9)
	# FogMaterial has no emission_energy_multiplier (only StandardMaterial3D
	# does), so bake the energy into the emission color directly.
	gate_fog_mat.emission = Color(0.15, 0.35, 0.7) * 1.5
	gate_fog.material = gate_fog_mat
	host._world.add_child(gate_fog)

	# --- Ancient glow on ceiling strips --------------------------------------
	# The cool-blue ceiling edge-glow strips (emissive host._glow_mat) pulse
	# subtly — the ship "breathing." Low amplitude so it reads as ambient
	# life, not a strobe. The glow is dimmed during the dark-open sequence
	# by open_dark/flicker_lights_up (which drive host._glow_mat directly).
	var glow = AncientGlowScript.new()
	glow.pulse_amplitude = 0.08
	glow.pulse_period = 4.0
	glow.pulse_color = Color(0.42, 0.58, 0.95)
	host.add_child(glow)
	if host._glow_mat != null:
		glow.add_target(host._glow_mat)
	door_spot.look_at(Vector3(0.0, 0.0, -half_z + 0.2), Vector3.UP)


# ─── Cold-open lighting ──────────────────────────────────────────────────────

# Open the cold open DARK: snapshot every dynamic light's energy, then crush them
# to near-black so the establishing shot + the gate dial play in the SGU gloom (only
# the gate + amber floor strips glow). flicker_lights_up() later restores them.
func open_dark() -> void:
	flicker_pairs = []
	for ln: Node in host.find_children("*", "Light3D", true, false):
		var light: Light3D = ln as Light3D
		if light != null:
			flicker_pairs.append([light, light.light_energy])
	apply_flicker_level(0.04)
	# The room's base glow is the WorldEnvironment AMBIENT (energy 1.35) — dimming the
	# Light3D nodes alone won't darken it. Crush the ambient too, on a DUPLICATE env so
	# the shared gate-room-environment.tres isn't mutated. Restored by flicker_lights_up.
	var we: WorldEnvironment = host.get_node_or_null("Environment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment = we.environment.duplicate()
		open_env = we.environment
		open_ambient0 = open_env.ambient_light_energy
		open_env.ambient_light_energy = open_ambient0 * 0.10
	# Snuff the emissive blue ceiling strips too (Light3D/ambient crush can't reach
	# them) so the ceiling line goes black like the reference; restored on flicker-up.
	if host._glow_mat != null:
		host._glow_energy0 = host._glow_mat.emission_energy_multiplier
		host._glow_mat.emission_energy_multiplier = host._glow_energy0 * 0.04


# §1.1: "a little lighting flickers on." The derelict's lights stutter back up from
# the dark-open level to full (fired as the crew start flooding through), with the
# electrical buzz. Uses the energies snapshotted by open_dark().
func flicker_lights_up() -> void:
	if flicker_pairs.is_empty():
		open_dark()   # safety: snapshot if the dark-open was skipped
	var fl: AudioStream = load("res://sounds/flicker.ogg") as AudioStream
	if fl != null:
		var fp: AudioStreamPlayer = AudioStreamPlayer.new()
		fp.name = "FlickerSfx"
		fp.stream = fl
		fp.volume_db = -6.0
		host.add_child(fp)
		fp.play()
		fp.finished.connect(fp.queue_free)
	var t: Tween = host.create_tween()
	for level: float in [0.06, 0.55, 0.1, 0.8, 0.25, 1.0, 0.45, 1.0]:
		t.tween_callback(apply_flicker_level.bind(level))
		t.tween_interval(0.1)
	t.tween_callback(apply_flicker_level.bind(1.0))   # settle at full
	# Bring the room ambient back up in step with the lights.
	if open_env != null:
		var et: Tween = host.create_tween()
		et.tween_interval(0.3)
		et.tween_property(open_env, "ambient_light_energy", open_ambient0, 0.8)
	# Flicker the ceiling strips back up with the lights (they were snuffed in open_dark).
	if host._glow_mat != null:
		var gt: Tween = host.create_tween()
		gt.tween_interval(0.3)
		gt.tween_property(host._glow_mat, "emission_energy_multiplier", host._glow_energy0, 0.8)


func apply_flicker_level(level: float) -> void:
	for pair: Array in flicker_pairs:
		if is_instance_valid(pair[0]):
			(pair[0] as Light3D).light_energy = float(pair[1]) * level


# Script §1.7: as the gate snuffs out, the room is plunged into darkness — then
# recovers. Briefly dims every dynamic light to ~12% and restores, so lit surfaces
# go dark while the UNSHADED emissive vent flames glow through the gloom. Touches
# only Light3D energies (snapshotted + restored); the shared Environment resource
# is left alone. Fire-and-forget coroutine.
func collapse_blackout() -> void:
	if host.cinematic.co_skip:
		return
	var pairs: Array = []
	var dim: Tween = host.create_tween().set_parallel(true)
	for ln: Node in host.find_children("*", "Light3D", true, false):
		var light: Light3D = ln as Light3D
		if light == null:
			continue
		pairs.append([light, light.light_energy])
		dim.tween_property(light, "light_energy", light.light_energy * 0.12, 0.3)
	await get_tree().create_timer(0.8).timeout   # hold the darkness while the flames vent
	var up: Tween = host.create_tween().set_parallel(true)
	for pair: Array in pairs:
		if is_instance_valid(pair[0]):
			up.tween_property(pair[0], "light_energy", pair[1], 1.3)


# Script §1.7: in the darkness, crew with flashlights switch them on. Two spot
# beams from perimeter positions cut the gloom toward the arrival zone, fading in
# with the blackout and out as room lighting recovers, then free themselves.
func flashlights_during_dark() -> void:
	if host.cinematic.co_skip:
		return
	var specs: Array = [
		[Vector3(7.5, 1.5, host.GATE_Z - 10.5), Vector3(-0.7, -0.15, 0.4)],
		[Vector3(-8.0, 1.5, host.GATE_Z - 9.0), Vector3(0.8, -0.15, 0.45)],
	]
	var beams: Array[SpotLight3D] = []
	for spec: Array in specs:
		var sl: SpotLight3D = SpotLight3D.new()
		sl.name = "CrewFlashlight"
		sl.position = spec[0]
		sl.light_energy = 0.0
		sl.light_color = Color(0.86, 0.91, 1.0)
		sl.spot_range = 15.0
		sl.spot_angle = 16.0
		sl.spot_attenuation = 1.3
		host._world.add_child(sl)
		sl.look_at(sl.global_position + (spec[1] as Vector3), Vector3.UP)
		beams.append(sl)
	# Slow back-and-forth yaw sweep so each reads as a held flashlight scanning the
	# dark, not a static pool. Opposite directions; only rotation.y so the pitch holds.
	for i: int in beams.size():
		var b: SpotLight3D = beams[i]
		var y0: float = b.rotation.y
		var dir: float = 1.0 if i == 0 else -1.0
		var sweep: Tween = host.create_tween()
		sweep.tween_property(b, "rotation:y", y0 + dir * 0.30, 1.5).set_trans(Tween.TRANS_SINE)
		sweep.tween_property(b, "rotation:y", y0 - dir * 0.18, 1.4).set_trans(Tween.TRANS_SINE)
	var up: Tween = host.create_tween().set_parallel(true)
	for b: SpotLight3D in beams:
		up.tween_property(b, "light_energy", 4.5, 0.3)
	await get_tree().create_timer(1.0).timeout
	var down: Tween = host.create_tween().set_parallel(true)
	for b: SpotLight3D in beams:
		if is_instance_valid(b):
			down.tween_property(b, "light_energy", 0.0, 1.3)
	await get_tree().create_timer(1.6).timeout
	for b: SpotLight3D in beams:
		if is_instance_valid(b):
			b.queue_free()


# ─── Gate collapse ──────────────────────────────────────────────────────────

func collapse_gate() -> void:
	if host.cinematic.co_skip:
		return   # finalize sets the gate dormant directly; skip its vent/shutdown FX
	host.interactables.gate_forced_open = false
	host.interactables.light_chevrons(0)
	if host._stargate != null and "active" in host._stargate:
		host._stargate.active = false
	if host._gate_hum_sfx != null and host._gate_hum_sfx.playing:
		host._gate_hum_sfx.stop()
	if host._gate_loop_sfx != null and host._gate_loop_sfx.playing:
		var t: Tween = host.create_tween()
		t.tween_property(host._gate_loop_sfx, "volume_db", -60.0, host.arrival_fade)
		t.tween_callback(Callable(host._gate_loop_sfx, "stop"))
	if host._gate_shutdown_sfx != null and host._gate_shutdown_sfx.stream != null:
		host._gate_shutdown_sfx.play()


# ─── Vent gate sides ────────────────────────────────────────────────────────

func vent_gate_sides() -> void:
	if host.cinematic.co_skip:
		return
	var base: Vector3 = Vector3(0.0, 0.4, host.GATE_Z)
	for sx: float in [-1.0, 1.0]:
		var side_pos: Vector3 = base + Vector3(sx * 2.3, 0.0, 0.15)
		# Flame: fast, additive, hot orange, falls back under gravity.
		spawn_vent_burst(side_pos, Vector3(sx * 0.25, 1.0, -0.2), 48, 0.75, 1.1,
			2.4, 4.6, Vector3(0.0, -1.2, 0.0), 0.25, 0.7, 0.45,
			Color(1.0, 0.55, 0.2, 0.85), Color(1.0, 0.45, 0.12), 3.5, true)
		# Steam: slower, billowing, grey, near-buoyant — lingers above the flame.
		spawn_vent_burst(side_pos + Vector3(0.0, 0.4, 0.0), Vector3(sx * 0.15, 1.0, -0.15),
			30, 0.55, 1.8, 1.0, 2.2, Vector3(0.0, 0.2, 0.0), 0.7, 1.5, 0.7,
			Color(0.72, 0.73, 0.78, 0.32), Color.BLACK, 0.0, false)


# Build + fire ONE one-shot particle burst (flame or steam). Frees itself after
# its lifetime. additive=true → hot/glowing (flame); false → soft alpha (steam).
func spawn_vent_burst(pos: Vector3, dir: Vector3, amount: int, explosive: float,
		life: float, vmin: float, vmax: float, grav: Vector3, smin: float, smax: float,
		quad_size: float, col: Color, emission: Color, emit_energy: float, additive: bool) -> void:
	var p: GPUParticles3D = GPUParticles3D.new()
	p.name = "GateVent"
	p.amount = amount
	p.one_shot = true
	p.explosiveness = explosive
	p.lifetime = life
	p.position = pos
	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 22.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = grav
	pm.scale_min = smin
	pm.scale_max = smax
	pm.color = col
	p.process_material = pm
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	var dm: StandardMaterial3D = StandardMaterial3D.new()
	dm.albedo_color = col
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if additive:
		dm.emission_enabled = true
		dm.emission = emission
		dm.emission_energy_multiplier = emit_energy
		dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = dm
	p.draw_pass_1 = quad
	host._world.add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 1.0).timeout.connect(p.queue_free)