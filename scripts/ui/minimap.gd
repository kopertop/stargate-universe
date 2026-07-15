extends Control

# Circular radar-style minimap (HUD redesign Phase 4, #141). A self-contained
# Control that draws a top-down radar disc: a gold ring, a faint range grid, a
# fixed player arrow at the centre (north = the player's facing), and a set of
# markers in player-relative, heading-rotated disc space. The HUD feeds it markers
# each frame via set_markers(); this widget owns only the drawing.
#
# Built as a Control with _draw (not a SubViewport camera) so it is cheap and
# headless-safe, and so it never has to fight the room's camera-curtain colliders.

const BG: Color = Color(0.16, 0.34, 0.18, 0.92)        # lit radar-green terrain disc
const BG_INNER: Color = Color(0.21, 0.42, 0.23, 0.95)  # brighter core
const RING: Color = Color(0.83, 0.66, 0.32, 1.0)       # gold rim (skin accent)
const GRID: Color = Color(0.55, 0.80, 0.45, 0.30)      # green range rings/cross
const ARROW: Color = Color(0.98, 0.95, 0.85, 1.0)      # player heading arrow

# Markers: Array of { "pos": Vector2 (disc space, -1..1, up = forward), "color": Color }.
var _markers: Array = []


func set_markers(markers: Array) -> void:
	_markers = markers
	queue_redraw()


func _draw() -> void:
	var r: float = size.x * 0.5
	var c: Vector2 = size * 0.5

	# Disc fill — a lit radar-green so the minimap reads as a map, not a black hole,
	# with a slightly brighter core for depth.
	draw_circle(c, r, BG)
	draw_circle(c, r * 0.6, BG_INNER)

	# Range grid: a cross + an inner ring, in green.
	draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), GRID, 1.0)
	draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), GRID, 1.0)
	draw_arc(c, r * 0.55, 0.0, TAU, 48, GRID, 1.0)

	# Markers (clamped to the disc).
	for m in _markers:
		var p: Vector2 = c + (m["pos"] as Vector2) * (r - 6.0)
		draw_circle(p, 3.5, m["color"] as Color)

	# Player arrow — a small triangle at the centre pointing up (the disc is
	# already rotated into the player's heading frame by the HUD).
	var a: PackedVector2Array = PackedVector2Array([
		c + Vector2(0.0, -8.0),
		c + Vector2(6.0, 7.0),
		c + Vector2(-6.0, 7.0),
	])
	draw_colored_polygon(a, ARROW)

	# Gold rim last so it sits over the disc edge.
	draw_arc(c, r - 1.0, 0.0, TAU, 64, RING, 2.5)
