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

const STRIP_W: float = 360.0
const STRIP_H: float = 28.0
const TOP_PAD: float = 14.0
const HALF_FOV: float = PI / 2.0       # ±90° fills the strip; beyond clamps to edges

const BG: Color = Color(0.04, 0.07, 0.12, 0.78)
const FRAME: Color = Color(0.55, 0.85, 1.0, 0.55)
const TICK: Color = Color(0.55, 0.85, 1.0, 0.85)
const GATE_COL: Color = Color(1.0, 0.85, 0.35, 1.0)     # warm amber — exit
const LIME_COL: Color = Color(0.93, 0.96, 1.0, 1.0)     # chalky white — deposit
const KINO_COL: Color = Color(0.45, 0.95, 1.0, 1.0)     # cyan tech — drone
const COMP_COL: Color = Color(0.62, 0.85, 1.0, 1.0)     # soft blue — friendly

var _player: Node3D = null
var _scene_path: String = ""
var _font: Font = null

func _ready() -> void:
	custom_minimum_size = Vector2(STRIP_W, TOP_PAD + STRIP_H + 16.0)
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

func _draw() -> void:
	# `_draw` runs synchronously after queue_redraw within the same frame, but a
	# scene change between _process and _draw could leave `_player` freed-but-
	# non-null. is_instance_valid blocks the rotation read on a dead handle.
	if _player == null or not is_instance_valid(_player):
		return
	var bar: Rect2 = Rect2(0.0, TOP_PAD, STRIP_W, STRIP_H)
	draw_rect(bar, BG, true)
	draw_rect(bar, FRAME, false)
	_draw_cardinals()
	_draw_markers(_player.global_position)


# Bearing of a world-space vector (point or direction) in the player's local
# frame: 0 = straight ahead, +π/2 = directly to the right, ±π = behind,
# -π/2 = directly to the left. Y is zeroed because the planet is flat — height
# offsets must not skew the horizontal bearing.
#
# Why this beats `wrapf(world_yaw - player.rotation.y, ...)`: Godot's +Y
# rotation is counterclockwise viewed from above (player at yaw=+π/2 actually
# faces WEST), so the naive subtraction inverts the left/right sign relative
# to player intuition. Going through `basis.inverse()` collapses every
# orientation case into a single XZ comparison with no sign traps.
func _bearing(world_offset: Vector3) -> float:
	var flat: Vector3 = Vector3(world_offset.x, 0.0, world_offset.z)
	var local: Vector3 = _player.basis.inverse() * flat
	return atan2(local.x, -local.z)


func _draw_cardinals() -> void:
	# Fixed WORLD directions — N is -Z, E is +X, S is +Z, W is -X.
	var cardinals: Array = [
		{"label": "N", "dir": Vector3(0, 0, -1)},
		{"label": "E", "dir": Vector3(1, 0, 0)},
		{"label": "S", "dir": Vector3(0, 0, 1)},
		{"label": "W", "dir": Vector3(-1, 0, 0)},
	]
	for c in cardinals:
		var rel: float = _bearing(c["dir"] as Vector3)
		if absf(rel) > HALF_FOV:
			continue
		var x: float = STRIP_W / 2.0 + (rel / HALF_FOV) * (STRIP_W / 2.0)
		draw_line(Vector2(x, TOP_PAD), Vector2(x, TOP_PAD + STRIP_H), TICK, 1.0)
		if _font != null:
			draw_string(_font, Vector2(x - 4.0, TOP_PAD - 2.0), String(c["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, TICK)

func _draw_markers(ppos: Vector3) -> void:
	var gate: Node3D = _find_gate()
	if gate != null:
		_draw_pip(gate.global_position, GATE_COL, "Gate", ppos)
	for c in get_tree().get_nodes_in_group("companion"):
		if c is Node3D:
			_draw_pip((c as Node3D).global_position, COMP_COL, "", ppos)
	for n in get_tree().get_nodes_in_group("lime_node"):
		if n is Node3D and n.has_method("is_discovered") and n.call("is_discovered") == true:
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
	var x: float = STRIP_W / 2.0 + (clamped / HALF_FOV) * (STRIP_W / 2.0)
	var y: float = TOP_PAD + STRIP_H / 2.0
	var col: Color = color
	if off_strip:
		col.a *= 0.55
	draw_circle(Vector2(x, y), 5.0, col)
	if off_strip:
		var edge_x: float = STRIP_W if rel > 0.0 else 0.0
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
