class_name KinoDrone
extends CharacterBody3D

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

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 0          # nothing needs to detect the drone
	collision_mask = 1           # slide off ground + walls only
	# Headless / instant_mode never pilots — the playthrough completes the
	# scout directly. Bail before capturing the mouse so tests stay clean.
	if SceneRouter.instant_mode:
		return
	_build_collision()
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

func _build_camera_rig() -> void:
	_camera = Camera3D.new()
	_camera.fov = 72.0
	_camera.current = true
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

func _render_atmo() -> void:
	if _atmo_box == null:
		return
	for c in _atmo_box.get_children():
		c.queue_free()
	_atmo_row("ATMOSPHERIC SCAN", "", Color(0.55, 0.85, 1.0, 1.0), 14)
	if atmosphere.is_empty():
		_atmo_row("— awaiting telemetry —", "", Color(0.7, 0.8, 0.9, 0.8), 12)
		return
	_atmo_row("Atmosphere", String(atmosphere.get("composition", "BREATHABLE")),
		_atmo_color(bool(atmosphere.get("breathable", true))), 13)
	var temp_c: int = int(atmosphere.get("temperature_c", 47))
	var temp_note: String = String(atmosphere.get("temperature_note", "HOT"))
	_atmo_row("Temperature", "%d°C  %s" % [temp_c, temp_note],
		Color(1.0, 0.7, 0.3, 1.0) if temp_note != "" else Color(0.6, 1.0, 0.6, 1.0), 13)
	_atmo_row("Radiation", String(atmosphere.get("radiation", "LOW")),
		_level_color(String(atmosphere.get("radiation", "LOW"))), 13)
	_atmo_row("Toxins", String(atmosphere.get("toxins", "NONE")),
		_level_color(String(atmosphere.get("toxins", "NONE"))), 13)

func _atmo_row(label: String, value: String, color: Color, size: int) -> void:
	var l: Label = Label.new()
	l.text = label if value == "" else ("%s:  %s" % [label, value])
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.08, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	_atmo_box.add_child(l)

func _atmo_color(good: bool) -> Color:
	return Color(0.6, 1.0, 0.6, 1.0) if good else Color(1.0, 0.45, 0.4, 1.0)

# Green for LOW/NONE/SAFE, amber otherwise — so radiation/toxin readouts read
# at a glance whether the far side is safe to step onto.
func _level_color(level: String) -> Color:
	var safe: bool = level.to_upper() in ["LOW", "NONE", "SAFE", "TRACE", "NEGLIGIBLE"]
	return Color(0.6, 1.0, 0.6, 1.0) if safe else Color(1.0, 0.7, 0.3, 1.0)

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
	elif event.is_action_pressed("interact") and not launch_in_ship:
		_recall()

func _physics_process(delta: float) -> void:
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
	var controls: String = "[WASD] Fly   [Shift] Boost   [Space] Up   [Ctrl] Down   [Mouse] Look"
	if launch_in_ship:
		_hint.text = controls + "\nFly through the active Stargate to scout the far side"
	elif _lime_confirmed:
		_hint.text = controls + "\nLime confirmed — press [E] to recall the Kino"
	else:
		_hint.text = controls + "\nScout for lime (it may be hidden behind the ridges), then press [E] to recall"

func _recall() -> void:
	if _ending:
		return
	_ending = true
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.kino_pilot_mode = false
	GameState.complete_kino_scout()
	SceneRouter.change_to("res://scenes/gate_room.tscn", "FromGate")
