class_name PlanetCompass
extends Control

# Phase F / F3 planet compass HUD. A horizontal screen-space strip pinned to the
# top of the viewport, showing direction + distance to:
#   - the return gate (group "planet_gate", mode "to_ship")
#   - DISCOVERED lime deposits (group "lime_node" where is_discovered() is true)
#   - every deployed Kino in the current planet scene (GameState.deployed_kinos)
#   - every away-team companion (group "companion")
# Cardinal ticks (N/E/S/W) mark world direction. Anything outside ±90° of the
# player's facing clamps to the strip edge with a small arrow indicator.
#
# Built by planet.gd at MINE_LIME (live play only) under a CanvasLayer so the
# Cinematic letterbox auto-hides it during the departure cutscene.

const STRIP_W: float = 360.0           # fallback width before the control is sized
const STRIP_H: float = 28.0
const TOP_PAD: float = 14.0
const HALF_FOV: float = PI             # ±180° fills the strip — full panoramic.
# Ruler-style ticks every 15°: cardinals (90°) are tall + lettered, the
# intercardinals (45° → NE/SE/SW/NW) are medium + small-lettered, and the rest
# are short minor notches with no label.
const TICK_STEP_DEG: int = 15
const TICK_LEN_MAJOR: float = 18.0
const TICK_LEN_INTER: float = 12.0
const TICK_LEN_MINOR: float = 6.0
const INTERCARDINALS: Dictionary = {45: "NE", 135: "SE", 225: "SW", 315: "NW"}
# A panoramic compass (±180°) means EVERY world direction maps to a strip
# position and nothing ever clamps to the edges, so pips move smoothly even
# as the player makes large rotations. The trade-off is that things directly
# behind the player land at the strip edges instead of off-strip arrows —
# but for a top-down planet surface where exploration directions matter in
# every quadrant, the readability gain beats the "ahead vs behind" cue.

# More transparent than before so the strip floats over the world without
# blocking it. Minor ticks are dimmer still.
const BG: Color = Color(0.04, 0.07, 0.12, 0.30)
const FRAME: Color = Color(0.45, 0.95, 1.0, 0.22)
# "Tech blue" cyan for the cardinal labels + ruler dashes (matches KINO_COL).
const TICK: Color = Color(0.45, 0.95, 1.0, 0.90)
const TICK_MINOR: Color = Color(0.45, 0.95, 1.0, 0.40)
const GATE_COL: Color = Color(1.0, 0.85, 0.35, 1.0)     # warm amber — exit
const LIME_COL: Color = Color(0.93, 0.96, 1.0, 1.0)     # chalky white — deposit
const KINO_COL: Color = Color(0.45, 0.95, 1.0, 1.0)     # cyan tech — drone
const COMP_COL: Color = Color(0.62, 0.85, 1.0, 1.0)     # soft blue — friendly

var _player: Node3D = null
var _scene_path: String = ""
var _font: Font = null

func _ready() -> void:
	# Width comes from the control's anchors (≈70% of the screen); only the
	# height is constrained here.
	custom_minimum_size = Vector2(0.0, TOP_PAD + STRIP_H + 16.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	# Live refresh when the underlying state changes (a deposit gets spotted, a
	# Kino is deployed/recalled). Per-frame queue_redraw is cheap but signals
	# let us update instantly even when the player is stationary.
	if not GameState.lime_discovered_changed.is_connected(queue_redraw):
		GameState.lime_discovered_changed.connect(queue_redraw)
	if not GameState.deployed_kinos_changed.is_connected(queue_redraw):
		GameState.deployed_kinos_changed.connect(queue_redraw)

# GameState is an autoload and outlives this Control, so explicitly disconnect
# our signal callables when the compass exits the tree — otherwise a scene
# tear-down could leave the autoload holding stale handles into a freed object.
func _exit_tree() -> void:
	if GameState.lime_discovered_changed.is_connected(queue_redraw):
		GameState.lime_discovered_changed.disconnect(queue_redraw)
	if GameState.deployed_kinos_changed.is_connected(queue_redraw):
		GameState.deployed_kinos_changed.disconnect(queue_redraw)

# Tell the compass which planet scene's deployed Kinos to query. Without this
# it just won't draw Kino pips.
func set_scene_path(p: String) -> void:
	_scene_path = p

func _process(_dt: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	queue_redraw()

# Current strip width — the control's actual size (≈70% screen), with a sane
# floor before layout settles.
func _strip_w() -> float:
	return maxf(size.x, STRIP_W)


# Screen X for a bearing relative to the heading: -HALF_FOV → left edge,
# 0 → centre, +HALF_FOV → right edge.
func _bearing_to_x(rel: float) -> float:
	var w: float = _strip_w()
	return w / 2.0 + (rel / HALF_FOV) * (w / 2.0)


func _draw() -> void:
	# `_draw` runs synchronously after queue_redraw within the same frame, but a
	# scene change between _process and _draw could leave `_player` freed-but-
	# non-null. is_instance_valid blocks the rotation read on a dead handle.
	if _player == null or not is_instance_valid(_player):
		return
	var bar: Rect2 = Rect2(0.0, TOP_PAD, _strip_w(), STRIP_H)
	draw_rect(bar, BG, true)
	draw_rect(bar, FRAME, false)
	_draw_ticks()
	_draw_markers(_player.global_position)


# Yaw-only basis aligned with the CAMERA's horizontal forward, so the heading
# tracks where the player is LOOKING — not the body's facing. Strafing
# left/right no longer spins the compass; only turning the camera does. Falls
# back to the player body when no 3D camera is active.
func _heading_basis() -> Basis:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return _player.global_transform.basis
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return _player.global_transform.basis
	return Basis.looking_at(fwd.normalized(), Vector3.UP)


# Bearing of a world-space vector (point or direction) relative to the camera
# heading: 0 = straight ahead, +π/2 = directly to the right, ±π = behind,
# -π/2 = directly to the left. Y is zeroed because the planet is flat.
#
# Why through `basis.inverse()`: Godot's +Y rotation is counterclockwise from
# above, so a naive `world_yaw - heading_yaw` subtraction inverts the left/right
# sign. Collapsing into a single XZ comparison in the heading frame has no sign
# traps.
func _bearing(world_offset: Vector3) -> float:
	var flat: Vector3 = Vector3(world_offset.x, 0.0, world_offset.z)
	var local: Vector3 = _heading_basis().inverse() * flat
	return atan2(local.x, -local.z)


# Ruler-style ticks every TICK_STEP_DEG around the full circle: tall lettered
# cardinals, medium lettered intercardinals, short minor notches between.
func _draw_ticks() -> void:
	for deg in range(0, 360, TICK_STEP_DEG):
		var rad: float = deg_to_rad(float(deg))
		# World direction for this compass heading (0°=N=-Z, 90°=E=+X, …).
		var dir: Vector3 = Vector3(sin(rad), 0.0, -cos(rad))
		var rel: float = _bearing(dir)
		if absf(rel) > HALF_FOV:
			continue
		var x: float = _bearing_to_x(rel)
		var label: String = ""
		var tick_len: float = TICK_LEN_MINOR
		var col: Color = TICK_MINOR
		if deg % 90 == 0:
			label = ["N", "E", "S", "W"][deg / 90]
			tick_len = TICK_LEN_MAJOR
			col = TICK
		elif INTERCARDINALS.has(deg):
			label = String(INTERCARDINALS[deg])
			tick_len = TICK_LEN_INTER
			col = TICK
		draw_line(Vector2(x, TOP_PAD), Vector2(x, TOP_PAD + tick_len), col, 1.0)
		if label != "" and _font != null:
			var fsize: int = 12 if deg % 90 == 0 else 9
			draw_string(_font, Vector2(x - 4.0, TOP_PAD - 2.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, col)

func _draw_markers(ppos: Vector3) -> void:
	var gate: Node3D = _find_gate()
	if gate != null:
		_draw_pip(gate.global_position, GATE_COL, "Gate", ppos)
	for c in get_tree().get_nodes_in_group("companion"):
		if c is Node3D:
			_draw_pip((c as Node3D).global_position, COMP_COL, "", ppos)
	for n in get_tree().get_nodes_in_group("lime_node"):
		if not (n is Node3D):
			continue
		if not n.has_method("is_discovered") or n.call("is_discovered") != true:
			continue
		# Mined deposits stay in the tree (their resource_node script keeps the
		# node alive but hides it) — drop them from the compass too so the
		# strip reflects only actionable destinations.
		if n.get("depleted") == true:
			continue
		_draw_pip((n as Node3D).global_position, LIME_COL, "", ppos)
	if _scene_path != "":
		for k in GameState.deployed_kinos_in_scene(_scene_path):
			if k is Dictionary:
				var d: Dictionary = k
				var p: Vector3 = Vector3(
					float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
				_draw_pip(p, KINO_COL, "K", ppos)

func _draw_pip(target: Vector3, color: Color, glyph: String, ppos: Vector3) -> void:
	var delta: Vector3 = target - ppos
	var dist: float = Vector2(delta.x, delta.z).length()    # planar (no Y) — planets are flat
	if dist < 0.01:
		return
	var rel: float = _bearing(delta)
	var off_strip: bool = absf(rel) > HALF_FOV
	var clamped: float = clampf(rel, -HALF_FOV, HALF_FOV)
	var x: float = _bearing_to_x(clamped)
	var y: float = TOP_PAD + STRIP_H / 2.0
	var col: Color = color
	if off_strip:
		col.a *= 0.55
	draw_circle(Vector2(x, y), 5.0, col)
	if off_strip:
		var edge_x: float = _strip_w() if rel > 0.0 else 0.0
		var dirx: float = -1.0 if rel > 0.0 else 1.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(edge_x, y),
			Vector2(edge_x + dirx * 9.0, y - 6.0),
			Vector2(edge_x + dirx * 9.0, y + 6.0),
		]), col)
	if glyph != "" and _font != null:
		draw_string(_font, Vector2(x + 7.0, y + 4.0), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, color)
	# Distance label below the pip — only when on-strip so the edges stay clean.
	if not off_strip and _font != null:
		draw_string(_font, Vector2(x - 12.0, y + 18.0), "%dm" % int(round(dist)),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(color.r, color.g, color.b, 0.85))

func _find_gate() -> Node3D:
	for n in get_tree().get_nodes_in_group("planet_gate"):
		if n is Node3D and String(n.get("mode")) == "to_ship":
			return n as Node3D
	return null
