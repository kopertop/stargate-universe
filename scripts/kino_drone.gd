class_name KinoDrone
extends CharacterBody3D

# Preloaded (not referenced by class_name) so a -s SceneTree test that loads
# this script in the same headless run doesn't hit "Identifier 'AtmoReadout'
# not declared" — freshly-added class_name globals aren't guaranteed registered
# mid-run (see memory feedback_godot_class_name_headless).
const AtmoReadoutScript := preload("res://scripts/atmo_readout.gd")

# Pilotable scout Kino — the small orb the player launches to recon the lime
# planet before stepping through to mine. Two launch modes:
#
#   • launch_in_ship = true  — spawned in the Gate Room at the player's spot.
#     The player flies it through the active Stargate; crossing the event
#     horizon warps to the planet (kino_pilot_mode stays set), where a fresh
#     drone spawns in recon mode.
#   • launch_in_ship = false — spawned on the planet (planet.gd). Recon: fly
#     around, read the atmosphere, find lime, press E to recall.
#
# Flight: WASD planar relative to heading, Space ascend / Ctrl descend, mouse-
# look yaw+pitch, damped momentum. No gravity — MOTION_MODE is FLOATING so
# move_and_slide keeps full 3D velocity while still sliding off terrain/walls.

const MAX_SPEED: float = 9.0          # m/s, planar
const VERT_SPEED: float = 6.0         # m/s, ascend/descend
const SPRINT_MULT: float = 3.0        # Shift boost
const ACCEL_DAMP: float = 5.0         # velocity lerp factor (higher = snappier)
const MOUSE_SENS: float = 0.0025      # radians per pixel of mouse motion
const LIME_CONFIRM_RANGE: float = 7.0 # metres to a lime node before "confirmed"
const GATE_CROSS_RADIUS: float = 2.6  # metres from the ship gate that warps us through

# Auto-search patrol — runs after _exit_kino on the planet so the drone keeps
# revealing new lime instead of going inert. Multiple drones cooperate via the
# "patrolling_kino" group: each publishes its current _autopilot_target and
# the others avoid choosing destinations within AUTO_AVOID_RADIUS, so the team
# naturally fans out instead of doubling up on the same area.
const AUTO_SPEED: float = 5.5         # cruise speed in patrol mode
const AUTO_ARRIVE: float = 8.0        # distance to target before picking the next
const AUTO_DETECT_RANGE: float = 24.0 # discover any non-discovered lime within this radius
const AUTO_CRUISE_Y: float = 14.0     # patrol altitude above world origin (planet origin is ~0)
const AUTO_AVOID_RADIUS: float = 50.0 # min separation from another drone's chosen target
const AUTO_RANDOM_TRIALS: int = 12    # how many candidate fallback points to score per pick
# The orb body renders on this visual layer; the pilot's own camera culls it
# (so it doesn't fill the first-person view), but every OTHER camera (Eli's
# third-person view) sees the Kino flying / hovering where it was left.
const ORB_VIEW_LAYER: int = 20

# Spawner-set BEFORE add_child (so _ready sees the right mode + heading).
var launch_in_ship: bool = false
# Atmosphere readings shown on the recon HUD (filled by planet.gd from data).
var atmosphere: Dictionary = {}

var _yaw: float = 0.0
var _pitch: float = 0.0
var _ending: bool = false             # recall or gate-cross in progress
var _lime_confirmed: bool = false
var _camera: Camera3D = null
var _caption: Label = null
var _hint: Label = null
var _atmo_box: VBoxContainer = null

# Auto-search state (set after the player closes the remote on the planet).
var _autopilot: bool = false
var _autopilot_target: Vector3 = Vector3.ZERO
var _autopilot_discover_t: float = 0.0   # accumulator for the periodic discovery sweep

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 0          # nothing needs to detect the drone
	collision_mask = 1           # slide off ground + walls only
	# Headless / instant_mode never pilots — the playthrough completes the
	# scout directly. Bail before capturing the mouse so tests stay clean.
	if SceneRouter.instant_mode:
		return
	_build_collision()
	_build_body()
	_build_camera_rig()
	_build_overlay()
	_yaw = rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if launch_in_ship:
		GameState.add_log("Kino active. Fly it through the gate to scout the far side.")
	else:
		GameState.add_log("Kino is through the gate. Scout the surface for lime.")
	_refresh_hint()

func _build_collision() -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 0.35
	cs.shape = sphere
	add_child(cs)

# Visible Kino orb — a dark sphere with a glowing cyan eye. Rendered only to
# OTHER cameras (see ORB_VIEW_LAYER) so the pilot's first-person view stays clear
# but Eli (and onlookers) can see the Kino in flight and where it was left.
func _build_body() -> void:
	var shell: MeshInstance3D = MeshInstance3D.new()
	shell.name = "OrbBody"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	shell.mesh = sphere
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.11, 0.14)
	m.metallic = 0.6
	m.roughness = 0.4
	shell.material_override = m
	shell.layers = 1 << (ORB_VIEW_LAYER - 1)
	add_child(shell)

	var eye: MeshInstance3D = MeshInstance3D.new()
	var lens: SphereMesh = SphereMesh.new()
	lens.radius = 0.07
	lens.height = 0.14
	eye.mesh = lens
	var em: StandardMaterial3D = StandardMaterial3D.new()
	em.albedo_color = Color(0.55, 0.85, 1.0)
	em.emission_enabled = true
	em.emission = Color(0.55, 0.85, 1.0)
	em.emission_energy_multiplier = 3.0
	eye.material_override = em
	eye.layers = 1 << (ORB_VIEW_LAYER - 1)
	eye.position = Vector3(0.0, 0.0, -0.13)   # front-facing eye (−Z)
	add_child(eye)

func _build_camera_rig() -> void:
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.current = true
	# Cull the orb body from the pilot's own view (it's inside/at the camera).
	_camera.cull_mask = ((1 << 20) - 1) & ~(1 << (ORB_VIEW_LAYER - 1))
	add_child(_camera)
	# A soft scan-glow so terrain near the orb reads on a dim graybox planet.
	var glow: OmniLight3D = OmniLight3D.new()
	glow.light_color = Color(0.78, 0.95, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = 9.0
	_camera.add_child(glow)

func _build_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)

	# Vignette — strong radial darkening so the edges clearly fade to black,
	# selling the "looking through a Kino's fisheye eye" feel. Built inline
	# (a runtime ShaderMaterial needs no import sidecar).
	var vig: ColorRect = ColorRect.new()
	vig.anchor_right = 1.0
	vig.anchor_bottom = 1.0
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	var sh: Shader = Shader.new()
	sh.code = "shader_type canvas_item;\n" \
		+ "void fragment() {\n" \
		+ "\tvec2 d = (UV - vec2(0.5)) * vec2(1.05, 1.0);\n" \
		+ "\tfloat r = length(d) * 1.42;\n" \
		+ "\tfloat v = smoothstep(0.28, 1.02, r);\n" \
		+ "\tCOLOR = vec4(0.0, 0.02, 0.04, v * 0.86);\n" \
		+ "}\n"
	mat.shader = sh
	vig.material = mat
	layer.add_child(vig)

	var tag: Label = Label.new()
	tag.text = "● KINO 1 — RECON"
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", Color(0.65, 0.95, 1.0, 0.9))
	tag.add_theme_color_override("font_outline_color", Color(0.0, 0.06, 0.10, 0.85))
	tag.add_theme_constant_override("outline_size", 5)
	tag.position = Vector2(34.0, 26.0)
	layer.add_child(tag)

	_build_atmo_readout(layer)

	_hint = Label.new()
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_right = 1.0
	_hint.offset_left = 28.0
	_hint.offset_right = -28.0
	_hint.offset_top = -64.0
	_hint.offset_bottom = -24.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0, 0.92))
	_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.06, 0.10, 0.85))
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hint)

	_caption = Label.new()
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 0.5
	_caption.offset_left = 60.0
	_caption.offset_right = -60.0
	_caption.offset_top = -40.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color(0.72, 1.0, 0.45, 1.0))
	_caption.add_theme_color_override("font_outline_color", Color(0.0, 0.10, 0.0, 0.9))
	_caption.add_theme_constant_override("outline_size", 7)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	layer.add_child(_caption)

# Top-right atmosphere panel. In ship mode (no telemetry yet) it shows a
# placeholder; once on the planet, planet.gd hands us the readings.
func _build_atmo_readout(layer: CanvasLayer) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -288.0
	panel.offset_right = -24.0
	panel.offset_top = 24.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.07, 0.11, 0.55)
	sb.border_color = Color(0.4, 0.75, 1.0, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	_atmo_box = VBoxContainer.new()
	_atmo_box.add_theme_constant_override("separation", 4)
	panel.add_child(_atmo_box)
	_render_atmo()

# Delegates to AtmoReadout.render — the single source of truth shared with the
# always-on ship readout in hud.gd. The planet telemetry dict carries no
# "status" key, so the recon panel keeps its original composition/temp/rad/tox
# layout while the ship readout adds a leading status banner.
func _render_atmo() -> void:
	AtmoReadoutScript.render(_atmo_box, atmosphere)

func _unhandled_input(event: InputEvent) -> void:
	if _ending or _camera == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		# Full 360° yaw + look nearly straight up/down. Pitch is clamped just shy
		# of vertical (±89°): going PAST vertical rolls the whole view upside down
		# (the world flips), which reads as a bug, not "free look". This keeps the
		# Kino's view always upright while still letting it look almost straight
		# up or down at anything.
		_yaw -= mm.relative.x * MOUSE_SENS
		_pitch -= mm.relative.y * MOUSE_SENS
		_pitch = clampf(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		rotation.y = _yaw
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("interact"):
		_exit_kino()

func _physics_process(delta: float) -> void:
	if _autopilot:
		# Player has left the drone; AI keeps flying. Camera/HUD are gone
		# (freed by _make_inert) but the body still exists in the scene tree.
		_drive_autopilot(delta)
		return
	if _ending or _camera == null:
		return
	# Heading-relative planar movement (yaw only), vertical from Space/Ctrl.
	var basis: Basis = global_transform.basis
	var fwd: Vector3 = -basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = basis.x
	right.y = 0.0
	right = right.normalized()

	var move_fwd: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var move_side: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var move_vert: float = Input.get_action_strength("jump") - Input.get_action_strength("kino_descend")

	var boost: float = SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0
	var planar: Vector3 = (fwd * move_fwd + right * move_side).limit_length(1.0) * MAX_SPEED * boost
	var target_vel: Vector3 = Vector3(planar.x, clampf(move_vert, -1.0, 1.0) * VERT_SPEED * boost, planar.z)
	velocity = velocity.lerp(target_vel, clampf(ACCEL_DAMP * delta, 0.0, 1.0))
	move_and_slide()

	if launch_in_ship:
		_try_gate_crossing()
	else:
		_check_lime_proximity()

# Ship mode: warp to the planet when the drone reaches the active Stargate.
# Uses the ship gate's group position directly so we bypass the player-only
# quest gating in planet_gate.gd's body_entered handler.
func _try_gate_crossing() -> void:
	var gate: Node3D = _find_ship_gate()
	if gate == null:
		return
	if global_position.distance_to(gate.global_position) <= GATE_CROSS_RADIUS:
		_ending = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# kino_pilot_mode stays set so planet.gd spawns a recon drone on arrival.
		# Pass NO spawn point: _start_kino_recon owns the drone's placement, and a
		# spawn key would make SceneRouter._place_player_at_spawn grab the drone
		# (it's in group "player") and clobber it down to the ground marker facing
		# away from the gate.
		SceneRouter.change_to("res://scenes/planet.tscn", "")

func _find_ship_gate() -> Node3D:
	for n in get_tree().get_nodes_in_group("planet_gate"):
		if n is Node3D and String(n.get("mode")) == "to_planet":
			return n
	return null

# Confirm the scout once the drone gets close to any lime deposit. Cosmetic —
# the actual quest advance happens on recall — but it gives the player the
# "I found it" beat the design calls for before they pull the Kino back.
func _check_lime_proximity() -> void:
	if _lime_confirmed:
		return
	for node in get_tree().get_nodes_in_group("interactable"):
		var rn: Node3D = node as Node3D
		if rn == null:
			continue
		var script: Script = rn.get_script()
		if script == null or not script.resource_path.ends_with("resource_node.gd"):
			continue
		if rn.global_position.distance_to(global_position) <= LIME_CONFIRM_RANGE:
			_lime_confirmed = true
			GameState.add_log("Kino spotted lime deposits.")
			Audio.play("res://sounds/menu_open.ogg")
			if _caption != null:
				_caption.text = "LIME DEPOSITS CONFIRMED"
				_caption.visible = true
			_refresh_hint()
			return

func _refresh_hint() -> void:
	if _hint == null:
		return
	var controls: String = "[WASD] Fly   [Shift] Boost   [Space] Up   [Ctrl] Down   [Mouse] Look   [E] Close Kino Remote"
	if launch_in_ship:
		_hint.text = controls + "\nFly through the active Stargate to scout the far side"
	elif _lime_confirmed:
		_hint.text = controls + "\nLime confirmed — the Kino stays here when you close the remote"
	else:
		_hint.text = controls + "\nScout for lime (it may be hidden behind the ridges)"

# [E] CLOSES THE KINO REMOTE — returns the player to their body. The player only
# CONTROLS the Kino, never becomes it; the Kino is left LIVE where it is (FIFO-
# tracked, retrievable later from the remote). Same scene as the body → restore
# control in place; different scene → warp back to the body's scene + spot.
func _exit_kino() -> void:
	if _ending:
		return
	_ending = true
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.kino_pilot_mode = false
	# Leave the Kino where it is (FIFO, capped). Captured before any scene change.
	GameState.deploy_kino(GameState.current_scene_path, global_position)
	# First planet recon confirms the scout (advances the quest).
	if GameState.current_scene_path == "res://scenes/planet.tscn" and not GameState.kino_scout_done:
		GameState.complete_kino_scout()
	var body_scene: String = GameState.kino_return_scene
	var same_scene: bool = body_scene == "" or body_scene == GameState.current_scene_path
	if same_scene:
		_close_in_place()
	else:
		_close_to_scene(body_scene)
	# Planet drones that stay in this scene flip into auto-search patrol so they
	# keep revealing new lime while the player is back in their body. The
	# in-place exit path freed the camera + HUD via _make_inert, but
	# start_autopilot re-enables _physics_process so the body keeps flying.
	if same_scene and not launch_in_ship and GameState.current_scene_path == "res://scenes/planet.tscn":
		start_autopilot()
	# Body restored — clear the return/target batons so the NEXT launch can't
	# inherit a stale destination. (_close_to_scene already copied what it needs
	# into pending_spawn_position before this runs.)
	GameState.kino_return_scene = ""
	GameState.kino_return_room_id = ""
	GameState.kino_return_position = null
	GameState.kino_pilot_target_scene = ""
	GameState.kino_pilot_target_pos = null

# Body is in THIS scene: hand control straight back to it (unlock, drop the
# holding pose + prop, restore the third-person camera + HUD), leaving the Kino
# hovering inert where it was.
func _close_in_place() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		if player.has_method("set_input_locked"):
			player.call("set_input_locked", false)
		if player.has_method("set_pose_override"):
			player.call("set_pose_override", "")
		var prop: Node = player.get_node_or_null("KinoRemoteProp")
		if prop != null:
			prop.queue_free()
	var scene: Node = get_tree().current_scene
	if scene != null:
		var hud: Node = scene.get_node_or_null("HUDLayer")
		if hud is CanvasLayer:
			(hud as CanvasLayer).visible = true
		var view: Node = scene.get_node_or_null("View")
		if view != null:
			var vcam: Camera3D = view.get_node_or_null("SpringArm/Camera") as Camera3D
			if vcam == null:
				vcam = view.get_node_or_null("Camera") as Camera3D
			if vcam != null:
				vcam.current = true
			if view.has_method("snap_to_target"):
				view.call("snap_to_target")
	GameState.add_log("Closed the Kino remote — the Kino is still where you left it.")
	_make_inert()

# Body is in a DIFFERENT scene: warp back to it at the exact spot it was left.
func _close_to_scene(scene_path: String) -> void:
	if GameState.kino_return_position is Vector3:
		GameState.pending_spawn_position = GameState.kino_return_position
		GameState.pending_spawn_yaw = GameState.kino_return_yaw
		GameState.skip_arrival_cinematic = true
	# Procedural rooms need their id so room.tscn rebuilds the right room.
	if scene_path == "res://scenes/room.tscn":
		GameState.next_room_id = GameState.kino_return_room_id
	SceneRouter.change_to(scene_path, "")

# Flip the drone into auto-search patrol. The player has left it; we keep
# _physics_process alive so the body keeps cruising, pick targets that
# maximize discovery, and reveal any non-discovered lime that wanders into
# AUTO_DETECT_RANGE. Multi-drone coordination uses the "patrolling_kino"
# group: every drone in autopilot publishes its current _autopilot_target as
# a script var, and _autopilot_pick_target rejects candidates within
# AUTO_AVOID_RADIUS of any other drone's target — so the team fans out.
func start_autopilot() -> void:
	if launch_in_ship or _autopilot:
		return
	_autopilot = true
	add_to_group("patrolling_kino")
	set_physics_process(true)
	_autopilot_pick_target()
	GameState.add_log("Kino now auto-searching for lime deposits.")


# Pick the highest-value next target. Priority 1: nearest non-discovered,
# non-depleted lime deposit that no other drone has already claimed. Priority
# 2 (fallback when no undiscovered lime remains, or all candidates are too
# close to other drones' targets): a random point biased AWAY from every
# patrolling drone's current target, so we explore unclaimed territory
# instead of doubling up.
func _autopilot_pick_target() -> void:
	var candidates: Array = []
	for n in get_tree().get_nodes_in_group("lime_node"):
		if not (n is Node3D):
			continue
		if n.has_method("is_discovered") and n.call("is_discovered") == true:
			continue
		if n.get("depleted") == true:
			continue
		candidates.append(n)
	# Closest undiscovered lime first.
	candidates.sort_custom(_compare_distance)
	for c in candidates:
		var p: Vector3 = (c as Node3D).global_position
		if not _is_target_too_close(p):
			_autopilot_target = Vector3(p.x, AUTO_CRUISE_Y, p.z)
			return
	# No claimable lime — wander to an unclaimed quadrant instead.
	_autopilot_target = _autopilot_random_far_point()


# Sort helper: nearest-to-current-position first.
func _compare_distance(a: Object, b: Object) -> bool:
	var ap: Vector3 = (a as Node3D).global_position
	var bp: Vector3 = (b as Node3D).global_position
	return global_position.distance_squared_to(ap) < global_position.distance_squared_to(bp)


# True if any OTHER patrolling drone is already targeting somewhere within
# AUTO_AVOID_RADIUS of `p` — keeps drones from converging on the same lime.
func _is_target_too_close(p: Vector3) -> bool:
	for d in get_tree().get_nodes_in_group("patrolling_kino"):
		if d == self or not (d is Node3D):
			continue
		var their: Variant = d.get("_autopilot_target")
		if their is Vector3:
			var t: Vector3 = their
			if Vector2(p.x - t.x, p.z - t.z).length() < AUTO_AVOID_RADIUS:
				return true
	return false


# Score-based wandering target: try AUTO_RANDOM_TRIALS random points in the
# planet's playable area, pick the one whose sum-distance from every other
# patrolling drone's target is highest. With a single drone this is just a
# random walk; with N drones it naturally clusters away from teammates.
func _autopilot_random_far_point() -> Vector3:
	var planet_extent: float = 200.0    # rough — matches the planet's middle band
	var best_p: Vector3 = global_position
	var best_score: float = -INF
	for _i in AUTO_RANDOM_TRIALS:
		var p: Vector3 = Vector3(
			randf_range(-planet_extent, planet_extent),
			AUTO_CRUISE_Y,
			randf_range(-planet_extent, planet_extent))
		var score: float = 0.0
		for d in get_tree().get_nodes_in_group("patrolling_kino"):
			if d == self or not (d is Node3D):
				continue
			var their: Variant = d.get("_autopilot_target")
			if their is Vector3:
				var t: Vector3 = their
				score += Vector2(p.x - t.x, p.z - t.z).length()
		# Also reward being far from the current position so we don't pick a
		# point we're already on top of when no other drones exist.
		score += Vector2(p.x - global_position.x, p.z - global_position.z).length() * 0.5
		if score > best_score:
			best_score = score
			best_p = p
	return best_p


func _drive_autopilot(delta: float) -> void:
	var to_t: Vector3 = _autopilot_target - global_position
	to_t.y = 0.0
	var planar_dist: float = to_t.length()
	if planar_dist <= AUTO_ARRIVE:
		_autopilot_pick_target()
		return
	var planar_dir: Vector3 = to_t.normalized() * AUTO_SPEED
	var vert_diff: float = _autopilot_target.y - global_position.y
	var vert: float = clampf(vert_diff * 1.5, -VERT_SPEED, VERT_SPEED)
	velocity = velocity.lerp(
		Vector3(planar_dir.x, vert, planar_dir.z),
		clampf(ACCEL_DAMP * delta, 0.0, 1.0))
	# Face direction of travel so the drone visibly tracks where it's going.
	# Forward is -Z in Godot, so the yaw that makes the body face `planar_dir`
	# is atan2(-planar_dir.x, -planar_dir.z).
	var face_yaw: float = atan2(-planar_dir.x, -planar_dir.z)
	rotation.y = lerp_angle(rotation.y, face_yaw, delta * 4.0)
	move_and_slide()
	# Discovery sweep — non-discovered lime within AUTO_DETECT_RANGE flips to
	# discovered (resource_node._mark_discovered records it in GameState).
	# Throttled to 5 Hz; the loop is small but uniform per-frame work isn't
	# free with multiple drones patrolling.
	_autopilot_discover_t += delta
	if _autopilot_discover_t >= 0.2:
		_autopilot_discover_t = 0.0
		_autopilot_discover_nearby()


func _autopilot_discover_nearby() -> void:
	for n in get_tree().get_nodes_in_group("lime_node"):
		if not (n is Node3D):
			continue
		if n.has_method("is_discovered") and n.call("is_discovered") == true:
			continue
		if n.get("depleted") == true:
			continue
		var node3d: Node3D = n
		var d: float = Vector2(
			node3d.global_position.x - global_position.x,
			node3d.global_position.z - global_position.z).length()
		if d <= AUTO_DETECT_RANGE and n.has_method("_mark_discovered"):
			n.call("_mark_discovered")


# Stop driving the orb and shed the pilot-only camera/overlay, leaving a quiet
# hovering Kino behind (visible to Eli's view via ORB_VIEW_LAYER).
func _make_inert() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	velocity = Vector3.ZERO
	if _camera != null:
		_camera.queue_free()
		_camera = null
	for c in get_children():
		if c is CanvasLayer:
			c.queue_free()
