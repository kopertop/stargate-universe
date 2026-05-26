extends Node3D

# Floating diamond waypoint for the active quest objective. Spawned by
# room.gd / gate_room.gd into $World, positioned either above the in-room
# anchor (NPC, pickup, console, bed) or above the next door on the BFS path
# to the target room. The HUD finds us via the "quest_waypoint" group to draw
# the screen-edge arrow when we're offscreen.
#
# Visual: billboarded outlined diamond, cyan accent matching the Kino Remote
# UI palette. Procedural texture so we don't need a separate art asset.

const ACCENT: Color = Color(0.55, 0.85, 1.0)
const TEX_SIZE: int = 96
# World-space size of the diamond sprite. Was 0.012 (1.15 m wide) — too big,
# blocked NPC silhouettes and dominated the frame. 0.008 → 0.77 m wide reads
# clearly without crowding.
const WORLD_PIXEL_SIZE: float = 0.008
# Outline ring sits at the outer edge of the texture; solid inner diamond
# sits at ~40% of the outer radius (matches the concept-art "frame + core"
# motif). Insets are in source-pixel units inside a TEX_SIZE/2 half-radius.
const OUTLINE_OUTER_INSET: float = 0.0
const OUTLINE_INNER_INSET: float = 4.0
const INNER_SOLID_RADIUS_FRAC: float = 0.40
# Vertical bob amplitude / period for the float animation. Small enough to read
# as "alive" without competing with NPC idle motion.
const BOB_AMPLITUDE: float = 0.10
const BOB_PERIOD: float = 1.2

var _sprite: Sprite3D
var _base_y: float = 0.0
var _tween: Tween

# Mutable texture cache so we only rasterise the diamond once per session.
static var _cached_texture: ImageTexture = null


func _ready() -> void:
	add_to_group("quest_waypoint")
	_sprite = Sprite3D.new()
	_sprite.name = "Diamond"
	_sprite.texture = _diamond_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.no_depth_test = true
	_sprite.pixel_size = WORLD_PIXEL_SIZE
	_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	# Sit on top of geometry so the diamond never hides inside a wall/ceiling.
	_sprite.render_priority = 8
	add_child(_sprite)
	_base_y = global_position.y
	_start_bob()


func set_target_position(pos: Vector3) -> void:
	global_position = pos
	_base_y = pos.y
	if _sprite != null:
		_start_bob()


# Tween a vertical bob + alpha pulse. Loops forever; gets recreated on every
# target reposition so the animation always starts from base_y.
func _start_bob() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.set_loops()
	_tween.tween_property(_sprite, "position:y", BOB_AMPLITUDE, BOB_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_sprite, "position:y", 0.0, BOB_PERIOD * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Concept-art "frame + core" diamond: outer outline ring + solid inner diamond
# with a transparent gap between them. Cached after the first rasterisation.
# Diamond is drawn white/coloured against a transparent background; Sprite3D
# modulate handles final tint.
static func _diamond_texture() -> ImageTexture:
	if _cached_texture != null:
		return _cached_texture
	var img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: int = TEX_SIZE / 2
	var half: float = float(c - 6)
	var outline_outer: float = half - OUTLINE_OUTER_INSET
	var outline_inner: float = half - OUTLINE_INNER_INSET
	var solid_outer: float = half * INNER_SOLID_RADIUS_FRAC
	# Solid core gets a faint outer halo so it feels emissive, not pasted-on.
	var halo_band: float = 2.0
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d: float = abs(float(x - c)) + abs(float(y - c))
			# Outer outline ring (priority 1 — drawn whether or not the core lit up).
			if d <= outline_outer and d >= outline_inner:
				var a: float = 1.0
				if d > outline_outer - 1.0:
					a = clamp(outline_outer - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(ACCENT.r, ACCENT.g, ACCENT.b, a))
				continue
			# Solid inner diamond.
			if d <= solid_outer:
				var a: float = 1.0
				if d > solid_outer - 1.0:
					a = clamp(solid_outer - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(ACCENT.r, ACCENT.g, ACCENT.b, a))
				continue
			# Soft halo around the solid core (sells "this is glowing").
			if d <= solid_outer + halo_band:
				var halo_a: float = (1.0 - (d - solid_outer) / halo_band) * 0.35
				img.set_pixel(x, y, Color(ACCENT.r, ACCENT.g, ACCENT.b, halo_a))
	_cached_texture = ImageTexture.create_from_image(img)
	return _cached_texture
