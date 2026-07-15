class_name RoomBuilder
extends Object

# Procedural geometry builder for Destiny rooms generated from ship_layout.json.
# All 7 template types build as basic boxes (floor + 4 walls + ceiling), sized
# from JSON × ShipLayout.SCALE, with template-specific ceiling heights and
# material palettes so each room TYPE reads as visually distinct even before
# hero detail is added.
#
# Convention matches scripts/gate_room.gd: floor + walls on layer 1|2 (player +
# camera SpringArm), ceiling on layer 2 (camera only) — lets the spring arm
# clamp to the ceiling without the player capsule getting trapped against it.
#
# Usage from a generic room scene script:
#     var data: Dictionary = ShipLayout.room(room_id)
#     RoomBuilder.build(world, data)


# preload (not runtime load) so the control-room consoles get a valid script
# even on a fresh checkout where class_name registration lags in headless
# `-s` runs (same convention as room.gd / gate_room.gd).
const ControlConsoleScript: Script = preload("res://scripts/control_console.gd")


# ============================================================================
# CONSOLE STYLE — single source of truth for ALL consoles in the game.
# Used by attach_console_mesh() below; called from control room (4 stations),
# gate room (Gate Control + FTL), and any future Ancient-tech control surface.
# Tweak these constants to retune every console in one place.
# ============================================================================
const CONSOLE_GLB_PATH: String = "res://models/props/space_station_kit/computer-wide.glb"
# Verified GLB AABB (raw): 0.8 × 0.497 × 0.533 m, single mesh / surface.
# Top-edge profile (sampled per-vertex):
#   z=-0.20 → y_top=0.497  ← BACK of slanted screen housing (tallest)
#   z=-0.05 → y_top=0.294  ← FRONT edge of slanted screen face
#   z=+0.10 → y_top=0.245  ← keyboard/controls deck (operator workspace)
#   z=+0.30 → y_top=0.236  ← far edge of keyboard
# OPERATOR stands on the +Z side (keyboard); screen recess is the slanted
# face on the -Z side, sloping from low at z=-0.05 up to high at z=-0.20.
const CONSOLE_SCALE: float = 2.2                              # → 1.76 × 1.09 × 1.17 m (chest height)
const CONSOLE_BODY_COLOR: Color = Color(0.46, 0.48, 0.52)
const CONSOLE_BODY_METALLIC: float = 0.65
const CONSOLE_BODY_ROUGHNESS: float = 0.45
# Screen plate transform: dialed-in visually by dragging the plate inside the
# GLB's slanted recess in scenes/console_test.tscn. Plate sits flush in the
# recess with its high edge toward +Z (operator/keyboard side raised — matches
# Ancient console "display tilted up toward operator" convention).
# Source values from the editor Inspector (Stage-local frame, stage scale 2.2):
#   position = (0.0, 0.365, -0.02)
#   rotation = (+36.5°, 0°, 0°)
#   scale    = (1.2, 1.1, 1.1)  ← baked into CONSOLE_SCREEN_SIZE below
const CONSOLE_SCREEN_PLATE_Y: float = 0.365
const CONSOLE_SCREEN_PLATE_Z: float = -0.02
const CONSOLE_SCREEN_TILT_DEG: float = 36.5
const CONSOLE_SCREEN_SIZE: Vector3 = Vector3(0.744, 0.0165, 0.33)
# Dimly emissive dark blue — workbench-tuned defaults (scenes/console_test.tscn).
# Bright tech-blue glow now comes from the TextMesh on top of the plate, not
# the plate itself.
const CONSOLE_SCREEN_COLOR_DEFAULT: Color = Color(0.04, 0.06, 0.10)
const CONSOLE_SCREEN_EMISSION: float = 0.4
# Albedo texture overlaid on the plate so it reads as a weathered steel
# display rather than a flat-coloured rectangle. Rusted-metal pattern gives
# the plate that Ancient-ship "millennia-old wall panel" feel.
const CONSOLE_SCREEN_OVERLAY_TEX: String = "res://textures/rusted-metal.png"
# Tech-blue text that lives on top of the screen plate (production gate-room
# consoles add this via gate_console.gd; control-room consoles leave it
# absent for a clean "powered-down screen" decorative look).
const CONSOLE_TEXT_COLOR: Color = Color(0.32, 0.72, 1.0)
const CONSOLE_TEXT_EMISSION: float = 1.5
const CONSOLE_TEXT_FONT_SIZE: int = 16
const CONSOLE_TEXT_PIXEL_SIZE: float = 0.005
const CONSOLE_TEXT_DEPTH: float = 0.0
const CONSOLE_TEXT_LOCAL_ROTATION_DEG: Vector3 = Vector3(-90.0, 0.0, 0.0)


# ============================================================================
# WALL PANEL TEXTURE — used on every procedural room's interior walls so the
# generic shell reads as Ancient-tech metal panelling instead of a flat color.
# Tile sizes preserve the source PNG's 3:2 aspect (1536×1024) so individual
# panel sub-shapes don't squash horizontally on long corridors. _make_wall_mat
# clones a material per-wall and sets uv1_scale from the wall's face size, so
# a 5 m vestibule and a 100 m corridor both show panels at the same physical
# scale.
# ============================================================================
const WALL_TEXTURE_PATH: String = "res://textures/wall-panel.png"
const WALL_TILE_U_M: float = 4.0
const WALL_TILE_V_M: float = 2.667
static var _wall_texture_cache: Texture2D = null


# ============================================================================
# SET-DRESSING CATALOG — data-driven authored props for iconic special rooms.
# Keyed by room type id ("bridge", "observation_deck", etc.).
# Each entry mirrors the `setdressing` object in room_types.json.
# Populated once on first call to _load_setdressing_catalog(); stays null
# until then so unrelated room builds pay zero cost.
# ============================================================================
static var _setdressing_cache: Dictionary = {}
static var _setdressing_loaded: bool = false


# ============================================================================
# FLOOR GRATE TEXTURE — used on the floor of every "generic" procedural room
# (corridor, control room, kino room, quarters). Special-floor templates opt
# out via FLOOR_TEMPLATE_SKIP below: hydroponics keeps its earthy palette, and
# the elevator keeps a clean base under its emissive transport pad.
# Source PNG is square (1254×1254); tile at 3 m per repeat so each ~1 m grate
# sub-panel reads at realistic industrial scale.
# ============================================================================
const FLOOR_TEXTURE_PATH: String = "res://textures/floor-grate.png"
const FLOOR_TILE_M: float = 3.0
const FLOOR_TEMPLATE_SKIP: Array[String] = ["hydroponics-template", "elevator-template"]
# HDR albedo multiplier applied to every floor (textured AND flat-colour) so
# the dark grate metal reads brighter under the rooms' Omni lighting. Single
# knob — bump it to lift all floors at once. >1 is intentional: it pushes the
# albedo above the texture's own (near-black) values.
const FLOOR_BRIGHTNESS: float = 2.4
static var _floor_texture_cache: Texture2D = null


# Default ceiling height per template (metres). Picked to make small rooms
# feel intimate and large rooms feel monumental without per-room tuning.
const CEILING_BY_TEMPLATE: Dictionary = {
	"gate-room-template": 9.0,
	"corridor-template": 6.4,
	"control-room-template": 9.0,
	"kino-room-template": 6.0,
	"quarters-template": 5.4,
	"hydroponics-template": 10.0,
	"elevator-template": 5.6,
	"storage-template": 5.0,
}


static func build(world: Node3D, room_data: Dictionary) -> void:
	if room_data.is_empty() or world == null:
		return
	var template_id: String = String(room_data.get("template_id", ""))
	var width_m: float = float(room_data.get("width", 200)) * ShipLayout.SCALE
	var depth_m: float = float(room_data.get("height", 200)) * ShipLayout.SCALE
	var ceiling_m: float = CEILING_BY_TEMPLATE.get(template_id, 3.5)

	# Apply a per-template visual palette and any template-specific accents
	# AFTER the base shell is built so accents render on top.
	var palette: Dictionary = _palette_for(template_id)
	_build_shell(world, template_id, width_m, depth_m, ceiling_m, palette)
	_add_template_accents(world, template_id, width_m, depth_m, ceiling_m, palette)
	_add_fill_light(world, width_m, depth_m, ceiling_m, palette)
	# Step 4: data-driven authored set-dressing for iconic special rooms.
	# Early-returns unless the type has authored_setdressing=true + a setdressing dict.
	_add_authored_setdressing(world, room_data, width_m, depth_m, ceiling_m)


# ============================================================================
# AUTHORED SET-DRESSING — implements GDD §"Per-Type Authored Set-Dressing"
# design/gdd/ship-exploration.md.
#
# 4th build step: placed on top of the shared template shell + accents.
# No per-room .tscn, no fork of _build_shell — purely additive.
# Data source: setdressing dict in room_types.json, keyed by type id.
#
# DOORWAY-CLEARANCE rule (project convention): RoomBuilder runs before doors
# are stamped. Props are authored toward room centre/back wall — never at
# wall midpoints. Smoke test asserts no blocker AABB within 1.5 m of
# representative door positions (see tests/smoke/setdressing.gd).
# ============================================================================

# One-time static loader mirroring _load_wall_texture robustness.
# Reads room_types.json, builds a dict keyed by type id, stores only the
# setdressing sub-dict per entry. Returns true on success.
static func _load_setdressing_catalog() -> void:
	if _setdressing_loaded:
		return
	_setdressing_loaded = true
	const CATALOG_PATH: String = "res://data/room_types.json"
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(CATALOG_PATH)
	if bytes.is_empty():
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Array):
		return
	for entry in (parsed as Array):
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var type_id: String = String(d.get("id", ""))
		if type_id.is_empty():
			continue
		# Only cache entries that have both the flag AND the dict.
		if d.get("authored_setdressing", false) and d.has("setdressing"):
			var sd: Variant = d.get("setdressing", null)
			if sd is Dictionary:
				_setdressing_cache[type_id] = sd


# Main entry — called by build() as 4th step.
# Reads `type` from room_data (set by procedural_ship.gd::_make_room_row or
# ShipLayout JSON). The catalog lookup is the authoritative gate: only types
# that appear in _setdressing_cache (i.e. authored_setdressing=true AND a
# setdressing dict present in room_types.json) get set-dressing placed.
# Avoids depending on room_data carrying authored_setdressing (generated rows
# from _make_room_row don't include that key — catalog is canonical).
static func _add_authored_setdressing(world: Node3D, room_data: Dictionary, w: float, d: float, h: float) -> void:
	_load_setdressing_catalog()
	var type_id: String = String(room_data.get("type", ""))
	if type_id.is_empty():
		return
	var sd: Variant = _setdressing_cache.get(type_id, null)
	if not (sd is Dictionary):
		return
	var sd_dict: Dictionary = sd

	# Hero props — spawned via _spawn_kenney_prop (tint applied, avoids white-mesh).
	var props_array: Variant = sd_dict.get("hero_props", null)
	if props_array is Array:
		var prop_idx: int = 0
		for entry in (props_array as Array):
			if not (entry is Dictionary):
				continue
			_place_hero_prop(world, entry, prop_idx)
			prop_idx += 1

	# Emissive window slab for observation_deck (observation window illusion).
	if sd_dict.get("window_slab", false):
		_add_observation_window(world, w, d, h)

	# Signage — billboard Label3D on the named wall.
	var signs_array: Variant = sd_dict.get("signage", null)
	if signs_array is Array:
		for sign_entry in (signs_array as Array):
			if not (sign_entry is Dictionary):
				continue
			_place_signage(world, sign_entry, w, d, h)

	# Accent lights — optional per-type fill OmniLights.
	var lights_array: Variant = sd_dict.get("accent_lights", null)
	if lights_array is Array:
		for light_entry in (lights_array as Array):
			if not (light_entry is Dictionary):
				continue
			_place_accent_light(world, light_entry, sd_dict)


# Place one hero prop GLB. Mirrors _spawn_kenney_prop convention (tint applied,
# scale uniform). Optional `blocker` array adds a walk-blocker on layer 1 ONLY.
# DOORWAY CLEARANCE: props are authored toward room centre/back (pos from JSON)
# so they never land on wall midpoints where doors stamp.
static func _place_hero_prop(world: Node3D, entry: Dictionary, idx: int) -> void:
	var glb_path: String = String(entry.get("glb", ""))
	if glb_path.is_empty():
		return
	var glb: PackedScene = load(glb_path)
	if glb == null:
		return
	var pos_raw: Variant = entry.get("pos", null)
	var pos: Vector3 = Vector3.ZERO
	if pos_raw is Array and (pos_raw as Array).size() >= 3:
		pos = Vector3(float((pos_raw as Array)[0]), float((pos_raw as Array)[1]), float((pos_raw as Array)[2]))
	var yaw: float = float(entry.get("yaw", 0.0))
	var scale: float = float(entry.get("scale", 2.0))
	var tint_raw: Variant = entry.get("tint", null)
	var tint: Color = Color(0.45, 0.45, 0.50)
	if tint_raw is Array and (tint_raw as Array).size() >= 3:
		tint = Color(float((tint_raw as Array)[0]), float((tint_raw as Array)[1]), float((tint_raw as Array)[2]))

	# _spawn_kenney_prop handles GLB instantiation + material override (white-mesh fix).
	_spawn_kenney_prop(world, glb, pos, yaw, scale, tint)

	# Optional walk-blocker on layer 1 ONLY (never layer 2 — springarm safety).
	var blocker_raw: Variant = entry.get("blocker", null)
	if blocker_raw is Array and (blocker_raw as Array).size() >= 3:
		var bs: Vector3 = Vector3(float((blocker_raw as Array)[0]), float((blocker_raw as Array)[1]), float((blocker_raw as Array)[2]))
		_add_walk_blocker(world, pos, yaw, bs, "SetDressBlocker%d" % idx)


# Billboard Label3D anchored to the named wall surface, at the specified height.
# Renders the room's signage (room name, etc.) in a Godot Label3D so it renders
# without needing a font asset — defaults to the project's built-in font.
static func _place_signage(world: Node3D, entry: Dictionary, w: float, d: float, h: float) -> void:
	var text: String = String(entry.get("text", ""))
	if text.is_empty():
		return
	var wall: String = String(entry.get("wall", "-z"))
	var height: float = float(entry.get("height", 2.5))

	var lbl: Label3D = Label3D.new()
	lbl.name = "Signage"
	lbl.text = text
	lbl.font_size = 64
	lbl.pixel_size = 0.008
	lbl.modulate = Color(0.85, 0.80, 0.65, 1.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.no_depth_test = false
	lbl.double_sided = true

	# Position on named wall, inset 0.15 m so it's flush against the surface.
	var half_w: float = w * 0.5
	var half_d: float = d * 0.5
	var inset: float = 0.15
	match wall:
		"+x":
			lbl.position = Vector3(half_w - inset, height, 0.0)
			lbl.rotation_degrees = Vector3(0.0, -90.0, 0.0)
		"-x":
			lbl.position = Vector3(-half_w + inset, height, 0.0)
			lbl.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		"+z":
			lbl.position = Vector3(0.0, height, half_d - inset)
			lbl.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		_:  # "-z" default
			lbl.position = Vector3(0.0, height, -half_d + inset)
			lbl.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	world.add_child(lbl)


# Emissive window slab for the Observation Deck — a wide dark box on the -Z wall
# with a subtle blue emissive so it reads as "looking out into space" even
# without a real skybox behind it.
static func _add_observation_window(world: Node3D, w: float, d: float, h: float) -> void:
	var window_mat: StandardMaterial3D = _emissive_mat(Color(0.05, 0.08, 0.22), 1.8)
	window_mat.roughness = 0.05
	window_mat.metallic = 0.2
	var half_d: float = d * 0.5
	var win_w: float = w - 1.2
	var win_h: float = h - 1.8
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "ObservationWindow"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(win_w, win_h, 0.12)
	mi.mesh = box
	mi.material_override = window_mat
	mi.position = Vector3(0.0, h * 0.5 + 0.2, -half_d + 0.06)
	world.add_child(mi)
	# Faint blue fill cast from the window surface into the room.
	var win_light: OmniLight3D = OmniLight3D.new()
	win_light.name = "WindowFill"
	win_light.light_color = Color(0.30, 0.55, 1.0)
	win_light.light_energy = 0.8
	win_light.omni_range = w * 0.7
	win_light.omni_attenuation = 1.6
	win_light.shadow_enabled = false
	win_light.position = Vector3(0.0, h * 0.5, -half_d + 1.0)
	world.add_child(win_light)


# Per-entry accent OmniLight from the setdressing accent_lights array.
static func _place_accent_light(world: Node3D, entry: Dictionary, sd_dict: Dictionary) -> void:
	var pos_raw: Variant = entry.get("pos", null)
	var pos: Vector3 = Vector3.ZERO
	if pos_raw is Array and (pos_raw as Array).size() >= 3:
		pos = Vector3(float((pos_raw as Array)[0]), float((pos_raw as Array)[1]), float((pos_raw as Array)[2]))
	var energy: float = float(entry.get("energy", 1.4))
	var range_val: float = float(entry.get("range", 7.0))

	# Accent colour — from the setdressing accent_color or fall back to warm white.
	var col: Color = Color(1.0, 0.90, 0.78)
	var ac_raw: Variant = sd_dict.get("accent_color", null)
	if ac_raw is Array and (ac_raw as Array).size() >= 3:
		col = Color(float((ac_raw as Array)[0]), float((ac_raw as Array)[1]), float((ac_raw as Array)[2]))

	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "SetDressLight"
	lamp.light_color = col
	lamp.light_energy = energy
	lamp.omni_range = range_val
	lamp.omni_attenuation = 1.6
	lamp.shadow_enabled = false
	lamp.position = pos
	world.add_child(lamp)


# ----- shell (floor + walls + ceiling, identical structure across templates) --

static func _build_shell(world: Node3D, template_id: String, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var wall_thickness: float = 0.4

	# Slightly more metallic + crisper roughness than the first pass — empty
	# walls were reading flat next to the gate-room artisan walls. These values
	# put the procedural rooms in the same finish range as gate_room.gd.
	# Floor: generic rooms get the metal-grate texture (make_floor_mat); special
	# templates listed in FLOOR_TEMPLATE_SKIP keep their flat-colour palette
	# floor (hydroponics earthy-green, elevator under-pad clean).
	var floor_mat: StandardMaterial3D
	if FLOOR_TEMPLATE_SKIP.has(template_id):
		# Flat-colour floor (hydroponics/elevator) — still brightened by the
		# shared FLOOR_BRIGHTNESS knob so "all rooms" stay consistently lit.
		floor_mat = _make_mat(_scale_rgb(palette["floor"], FLOOR_BRIGHTNESS), 0.25, 0.55)
	else:
		floor_mat = make_floor_mat(palette["floor"], width, depth)
	# Wall material is cloned per-axis so panel tiling matches each wall's
	# face dimensions (see _make_wall_mat). ±X walls show depth × height; ±Z
	# walls show width × height — a single shared scale would stretch panels
	# on whichever axis didn't match.
	var wall_mat_x: StandardMaterial3D = make_wall_mat(palette["wall"], depth, height)
	var wall_mat_z: StandardMaterial3D = make_wall_mat(palette["wall"], width, height)
	var ceil_mat: StandardMaterial3D = _make_mat(palette["ceiling"], 0.25, 0.65)

	# Floor — single box + collider.
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1 | 2
	floor_body.collision_mask = 0
	world.add_child(floor_body)
	_add_box(floor_body, floor_mat, Vector3(0.0, -0.1, 0.0), Vector3(width, 0.2, depth))

	# Walls — one StaticBody3D containing four wall colliders + meshes.
	var walls: StaticBody3D = StaticBody3D.new()
	walls.name = "Walls"
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	world.add_child(walls)
	# +X / -X
	_add_box(walls, wall_mat_x,
		Vector3(half_x + wall_thickness * 0.5, height * 0.5, 0.0),
		Vector3(wall_thickness, height, depth))
	_add_box(walls, wall_mat_x,
		Vector3(-half_x - wall_thickness * 0.5, height * 0.5, 0.0),
		Vector3(wall_thickness, height, depth))
	# +Z / -Z
	_add_box(walls, wall_mat_z,
		Vector3(0.0, height * 0.5, half_z + wall_thickness * 0.5),
		Vector3(width, height, wall_thickness))
	_add_box(walls, wall_mat_z,
		Vector3(0.0, height * 0.5, -half_z - wall_thickness * 0.5),
		Vector3(width, height, wall_thickness))

	# Ceiling — camera-only collision so the SpringArm can clamp to it without
	# trapping the player capsule against it (matches gate_room convention).
	var ceil_body: StaticBody3D = StaticBody3D.new()
	ceil_body.name = "Ceiling"
	ceil_body.collision_layer = 2
	ceil_body.collision_mask = 0
	world.add_child(ceil_body)
	_add_box(ceil_body, ceil_mat,
		Vector3(0.0, height + wall_thickness * 0.5, 0.0),
		Vector3(width, wall_thickness, depth))


# ----- template-specific accents --------------------------------------------

static func _add_template_accents(world: Node3D, template_id: String, width: float, depth: float, height: float, palette: Dictionary) -> void:
	match template_id:
		"corridor-template":
			_accent_corridor(world, width, depth, height, palette)
		"control-room-template":
			_accent_control_room(world, width, depth, height, palette)
		"kino-room-template":
			_accent_kino_room(world, width, depth, height, palette)
		"quarters-template":
			_accent_quarters(world, width, depth, height, palette)
		"hydroponics-template":
			_accent_hydroponics(world, width, depth, height, palette)
		"elevator-template":
			_accent_elevator(world, width, depth, height, palette)
		"storage-template":
			_accent_storage(world, width, depth, height, palette)
		"gate-room-template":
			# Reference-only — the artisan gate_room.tscn handles its own geometry.
			pass


# Corridor: layered industrial detail — emissive runners at the top + base of
# both long walls, chest-height sconces along the side walls, and a dark
# conduit down the centreline of the ceiling. Reads as an Ancient ship
# corridor at both 5 m vestibule and 100 m hall scales.
#
# Previously had bulkhead "ribs" — dark vertical boxes between sconces — that
# protruded ~0.22 m from each wall. Removed once the wall-panel texture went
# in: the ribs fought the panel pattern instead of complementing it.
static func _accent_corridor(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var strip_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.4)
	var sconce_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 4.5)
	var conduit_mat: StandardMaterial3D = _make_mat(Color(0.09, 0.09, 0.11), 0.7, 0.45)

	var axis_z: bool = depth > width
	var long_len: float = depth if axis_z else width
	var short_len: float = width if axis_z else depth
	var half_short: float = short_len * 0.5
	var strip_len: float = long_len - 0.6
	var inset: float = 0.06

	for side in [1.0, -1.0]:
		var perp: float = side * (half_short - inset)
		_corridor_place(world, strip_mat, axis_z, perp, height - 0.45, 0.0, 0.10, 0.10, strip_len)
		_corridor_place(world, strip_mat, axis_z, perp, 0.20, 0.0, 0.10, 0.10, strip_len)

	# Sconces evenly spaced down both long walls — sconce_count derived from
	# the corridor's long-axis length so 5 m vestibules and 100 m halls both
	# get one sconce roughly every ~6 m. Skip in narrow rooms (<2 m short
	# axis) where wall sconces would crowd the path.
	var sconce_count: int = int(floor(strip_len / 6.0))
	if sconce_count >= 1 and short_len > 2.0:
		var spacing: float = strip_len / float(sconce_count + 1)
		for j in range(sconce_count + 1):
			var ts: float = -strip_len * 0.5 + spacing * (float(j) + 0.5)
			for side_s in [1.0, -1.0]:
				var perp_s: float = side_s * (half_short - 0.025)
				_corridor_place(world, sconce_mat, axis_z, perp_s,
					1.65, ts, 0.05, 0.32, 0.18)
				# Sconces only GLOW without a real light; the wall stayed flat.
				# A small OmniLight3D per sconce pool of warm bounce gives the
				# corridor genuine depth and picks up the wall-panel texture.
				var lamp: OmniLight3D = OmniLight3D.new()
				lamp.light_color = palette["accent"]
				lamp.light_energy = 1.6
				lamp.omni_range = 5.5
				lamp.omni_attenuation = 1.8
				lamp.shadow_enabled = false
				if axis_z:
					lamp.position = Vector3(perp_s - side_s * 0.25, 1.7, ts)
				else:
					lamp.position = Vector3(ts, 1.7, perp_s - side_s * 0.25)
				world.add_child(lamp)

	_corridor_place(world, conduit_mat, axis_z, 0.0, height - 0.18, 0.0, 0.22, 0.22, strip_len)

	# --- Floor walkway stripe -----------------------------------------------
	# Pair of dim emissive strips inset from the floor edges, framing a
	# pedestrian lane down the corridor's center. Only worth adding when the
	# corridor is wide enough that the lane reads as intentional.
	if short_len >= 2.5:
		var lane_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 0.9)
		var lane_inset: float = 0.50
		for lane_side in [1.0, -1.0]:
			_corridor_place(world, lane_mat, axis_z,
				lane_side * (half_short - lane_inset),
				0.025, 0.0,
				0.06, 0.02, strip_len)

	# --- Wall service panels -------------------------------------------------
	# Small dark recessed rectangles set into the wall between sconces — a
	# silent storytelling beat: "this corridor has working systems behind it."
	# Each panel gets a tiny accent indicator dot. Only emit when the corridor
	# is wide enough that the panels won't crowd the player path.
	if sconce_count >= 1 and short_len > 2.0:
		var panel_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.55), 0.5, 0.55)
		var indicator_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 3.0)
		var spacing_p: float = strip_len / float(sconce_count + 1)
		for j in range(sconce_count + 1):
			var ts_p: float = -strip_len * 0.5 + spacing_p * (float(j) + 0.5)
			# Panel sits ~0.85 m off the floor — hip height. Slim recess look.
			for side_p in [1.0, -1.0]:
				_corridor_place(world, panel_mat, axis_z,
					side_p * (half_short - 0.02),
					0.85, ts_p, 0.03, 0.45, 0.30)
				_corridor_place(world, indicator_mat, axis_z,
					side_p * (half_short - 0.04),
					1.02, ts_p + 0.10, 0.02, 0.04, 0.04)


# Place a decor box inside a corridor whose long axis is +Z (axis_z=true) or
# +X (axis_z=false). perp_off/along_off are positions in the corridor's short
# and long axes; perp_size/along_size are box extents along those same axes.
static func _corridor_place(world: Node3D, mat: StandardMaterial3D, axis_z: bool,
		perp_off: float, y: float, along_off: float,
		perp_size: float, h: float, along_size: float) -> void:
	if axis_z:
		_add_decor(world, mat, Vector3(perp_off, y, along_off), Vector3(perp_size, h, along_size))
	else:
		_add_decor(world, mat, Vector3(along_off, y, perp_off), Vector3(along_size, h, perp_size))


# Control room: industrial metal-grate floor overlay, a continuous amber band
# at chest height around all four walls, a massive floor-to-ceiling central
# pillar (Ancient power column with pipe and conduit cladding), and 4 Kenney
# `desk_computer.glb` consoles arranged 2-east / 2-west, all facing the pillar.
# Rush (placed by room.gd::_spawn_dr_rush) stands at the NW console.
static func _accent_control_room(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var accent: Color = palette["accent"]
	var band_mat: StandardMaterial3D = _emissive_mat(accent, 1.6)
	var ring_mat: StandardMaterial3D = _emissive_mat(accent, 2.2)

	# Previously stamped a procedural 32×32 grate overlay slab here. Removed
	# once the shared metal-grate floor texture went in (_build_shell calls
	# make_floor_mat for all non-special templates) — the overlay was the
	# same idea at lower fidelity and double-grated the room when both were
	# active.

	# --- Wall band -----------------------------------------------------------
	# Continuous emissive band at chest height around all four walls — the
	# room's primary colour anchor.
	var hx: float = width * 0.5 - 0.05
	var hz: float = depth * 0.5 - 0.05
	var band_t: float = 0.06
	_add_decor(world, band_mat, Vector3(hx, 1.4, 0.0), Vector3(band_t, band_t, depth - 0.6))
	_add_decor(world, band_mat, Vector3(-hx, 1.4, 0.0), Vector3(band_t, band_t, depth - 0.6))
	_add_decor(world, band_mat, Vector3(0.0, 1.4, hz), Vector3(width - 0.6, band_t, band_t))
	_add_decor(world, band_mat, Vector3(0.0, 1.4, -hz), Vector3(width - 0.6, band_t, band_t))

	# --- Central power pillar -----------------------------------------------
	# SGU control-room signature: a circular column running floor-to-ceiling
	# with cladding pipes + emissive conduit bands. Doubles as a navigation
	# anchor (player can't walk through it — see PillarCollider).
	_accent_control_pillar(world, height, accent)

	# --- Four consoles clustered N / S / E / W around the pillar ------------
	# Each console sits ~4 m from the room centre — close enough that the
	# pillar is at the operator's back, far enough not to overlap the pillar
	# itself (radius ≈ 1.4 m). Rotation has each console's front face (screen
	# + tilted plate) pointing OUTWARD toward the walls, so the operator
	# stands on the inside (pillar-side), looking outward at the console —
	# matching the SGU control-room blocking the user dialled in.
	#
	# DOORWAY-CLEARANCE rule: rooms must keep ≥1–2 m clear of every doorway.
	# The control room's doors sit on wall midpoints; with consoles at 4 m
	# from origin, the nearest console-to-door distance is ~10 m. Safe.
	const CONSOLE_OFFSET: float = 4.0
	var east_pos: Vector3  = Vector3( CONSOLE_OFFSET, 0.0, 0.0)
	var west_pos: Vector3  = Vector3(-CONSOLE_OFFSET, 0.0, 0.0)
	var north_pos: Vector3 = Vector3(0.0, 0.0, -CONSOLE_OFFSET)
	var south_pos: Vector3 = Vector3(0.0, 0.0,  CONSOLE_OFFSET)
	# Rotation Y so each console's forward (-Z local) points TOWARD the
	# central pillar — its tilted screen sits on the local +Z face which
	# then faces OUTWARD (away from pillar) toward the operator. Operators
	# stand on the wall-side of the console, facing inward through the
	# screen toward the pillar beyond.
	#   east  (+X)  → forward = -X (toward origin) → rot.y = +PI/2
	#   west  (-X)  → forward = +X (toward origin) → rot.y = -PI/2
	#   north (-Z)  → forward = +Z (toward origin) → rot.y = PI
	#   south (+Z)  → forward = -Z (toward origin) → rot.y = 0
	# All four consoles are identical Ancient control terminals — each opens
	# the same shipwide control menu (Kino-Remote-style panel: map, status,
	# log). Named by cardinal position so save/load anchors remain stable
	# and quest waypoints can target a specific one without changing
	# behavior. ControlConsole sits on collision layer 1|4 so the player
	# capsule can't walk through and the interact ray still finds it.
	# (Script is the module-level ControlConsoleScript preload.)
	var consoles: Array = [
		{"pos": east_pos,  "rot":  PI * 0.5, "name": "ControlConsoleEast"},
		{"pos": west_pos,  "rot": -PI * 0.5, "name": "ControlConsoleWest"},
		{"pos": north_pos, "rot":  PI,       "name": "ControlConsoleNorth"},
		{"pos": south_pos, "rot":  0.0,      "name": "ControlConsoleSouth"},
	]
	for c in consoles:
		var body: StaticBody3D = StaticBody3D.new()
		body.set_script(ControlConsoleScript)
		body.name = c["name"]
		body.position = c["pos"]
		body.rotation.y = c["rot"]
		world.add_child(body)
		attach_console_mesh(body)

	# --- Console downlights ---------------------------------------------------
	# One soft warm pool above each console, plus a small emissive ceiling
	# plate so the consoles pop against the cooler walls.
	for cp in [east_pos, west_pos, north_pos, south_pos]:
		var pos: Vector3 = cp
		_add_decor(world, ring_mat,
			Vector3(pos.x, height - 0.08, pos.z),
			Vector3(0.7, 0.04, 0.7))
		var work_light: OmniLight3D = OmniLight3D.new()
		work_light.light_color = accent.lerp(Color(1.0, 0.92, 0.78), 0.4)
		work_light.light_energy = 1.9
		work_light.omni_range = 8.0
		work_light.omni_attenuation = 1.6
		work_light.shadow_enabled = false
		work_light.position = Vector3(pos.x, 2.6, pos.z)
		world.add_child(work_light)


# Floor-to-ceiling power column at the room's centre. Built from a dark metal
# shaft, 6 amber-tinted vertical pipes ringing the outside, three emissive
# conduit bands at quarter/half/three-quarter height, a wider floor collar,
# and a tapered top cap that visually merges into the ceiling. A CylinderShape
# collider on layer 1|2 blocks player+camera from passing through.
static func _accent_control_pillar(world: Node3D, height: float, accent: Color) -> void:
	var shaft_mat: StandardMaterial3D = _make_mat(Color(0.22, 0.24, 0.28), 0.75, 0.40)
	var pipe_mat: StandardMaterial3D = _make_mat(Color(0.62, 0.55, 0.40), 0.70, 0.38)
	var conduit_mat: StandardMaterial3D = _emissive_mat(accent, 2.2)
	var collar_mat: StandardMaterial3D = _make_mat(Color(0.30, 0.32, 0.36), 0.70, 0.50)
	var cap_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.20, 0.22), 0.70, 0.45)

	# --- Main shaft (dark cylinder, slightly conical for visual weight) ----
	var shaft_mi: MeshInstance3D = MeshInstance3D.new()
	shaft_mi.name = "PillarShaft"
	var shaft_mesh: CylinderMesh = CylinderMesh.new()
	shaft_mesh.top_radius = 1.40
	shaft_mesh.bottom_radius = 1.55
	shaft_mesh.height = height
	shaft_mesh.radial_segments = 32
	shaft_mi.mesh = shaft_mesh
	shaft_mi.material_override = shaft_mat
	shaft_mi.position = Vector3(0.0, height * 0.5, 0.0)
	world.add_child(shaft_mi)

	# --- Cladding pipes (6 around the shaft) -------------------------------
	var pipe_count: int = 6
	var pipe_radius: float = 0.10
	var pipe_offset: float = 1.70
	for i in pipe_count:
		var theta: float = (TAU / float(pipe_count)) * float(i)
		var pipe_mi: MeshInstance3D = MeshInstance3D.new()
		var pipe_mesh: CylinderMesh = CylinderMesh.new()
		pipe_mesh.top_radius = pipe_radius
		pipe_mesh.bottom_radius = pipe_radius
		pipe_mesh.height = height - 0.4
		pipe_mesh.radial_segments = 8
		pipe_mi.mesh = pipe_mesh
		pipe_mi.material_override = pipe_mat
		pipe_mi.position = Vector3(cos(theta) * pipe_offset, height * 0.5, sin(theta) * pipe_offset)
		world.add_child(pipe_mi)

	# --- Emissive conduit bands wrapping the shaft -------------------------
	# Three bands at quarter heights — read as "power flowing up the column."
	for y_frac in [0.20, 0.50, 0.80]:
		var band_mi: MeshInstance3D = MeshInstance3D.new()
		var band_mesh: CylinderMesh = CylinderMesh.new()
		band_mesh.top_radius = 1.78
		band_mesh.bottom_radius = 1.78
		band_mesh.height = 0.18
		band_mesh.radial_segments = 32
		band_mi.mesh = band_mesh
		band_mi.material_override = conduit_mat
		band_mi.position = Vector3(0.0, height * y_frac, 0.0)
		world.add_child(band_mi)

	# --- Floor collar (wider base disc) ------------------------------------
	var collar_mi: MeshInstance3D = MeshInstance3D.new()
	var collar_mesh: CylinderMesh = CylinderMesh.new()
	collar_mesh.top_radius = 1.90
	collar_mesh.bottom_radius = 2.10
	collar_mesh.height = 0.30
	collar_mesh.radial_segments = 32
	collar_mi.mesh = collar_mesh
	collar_mi.material_override = collar_mat
	collar_mi.position = Vector3(0.0, 0.15, 0.0)
	world.add_child(collar_mi)

	# --- Top cap (tapered up into ceiling) ---------------------------------
	var cap_mi: MeshInstance3D = MeshInstance3D.new()
	var cap_mesh: CylinderMesh = CylinderMesh.new()
	cap_mesh.top_radius = 1.95
	cap_mesh.bottom_radius = 1.50
	cap_mesh.height = 0.50
	cap_mesh.radial_segments = 32
	cap_mi.mesh = cap_mesh
	cap_mi.material_override = cap_mat
	cap_mi.position = Vector3(0.0, height - 0.25, 0.0)
	world.add_child(cap_mi)

	# --- Player+camera collider --------------------------------------------
	# Radius covers the shaft plus pipes so the SpringArm can't clip through
	# either. Player capsule stops at the same radius. Matches kenney_room
	# floor/walls convention: layer 1|2.
	var pillar_body: StaticBody3D = StaticBody3D.new()
	pillar_body.name = "PillarCollider"
	pillar_body.collision_layer = 1 | 2
	pillar_body.collision_mask = 0
	var p_cs: CollisionShape3D = CollisionShape3D.new()
	var p_shape: CylinderShape3D = CylinderShape3D.new()
	p_shape.radius = 1.85
	p_shape.height = height
	p_cs.shape = p_shape
	p_cs.position = Vector3(0.0, height * 0.5, 0.0)
	pillar_body.add_child(p_cs)
	world.add_child(pillar_body)


# Attach the SHARED Ancient-tech console mesh as a child of `parent`. Caller
# is responsible for positioning + yaw-rotating `parent`; this populates the
# GLB + emissive screen plate inside it. Used by control_room, gate_room, and
# any future scene that wants the same console silhouette.
#
# `screen_color` overrides the default tech-blue (e.g. gate room passes
# distinct colors to differentiate Gate Control vs FTL Countdown consoles).
#
# All tweakable visual constants are at file top (CONSOLE_*) — edit there to
# retune every console in one shot.
static func attach_console_mesh(parent: Node3D, screen_color: Color = CONSOLE_SCREEN_COLOR_DEFAULT) -> void:
	# Inner stage holds the scaled GLB + screen so the caller can attach
	# unscaled siblings (collision shapes, scripts) without inheriting display
	# scale.
	var stage: Node3D = Node3D.new()
	stage.name = "ConsoleMesh"
	stage.scale = Vector3(CONSOLE_SCALE, CONSOLE_SCALE, CONSOLE_SCALE)
	parent.add_child(stage)

	var glb: PackedScene = load(CONSOLE_GLB_PATH)
	if glb != null:
		var inst: Node = glb.instantiate()
		stage.add_child(inst)
		# Kenney textures are stripped on glTF import (see
		# feedback_gltf_embedded_texture_lost). Override with the shared Ancient-
		# metal panel material so consoles match the Stargate/walls; fall back to
		# brushed metal if the shader resource is missing.
		var body_mat: Material = load("res://shaders/ancient_metal_panel.tres")
		if body_mat == null:
			body_mat = _make_mat(CONSOLE_BODY_COLOR, CONSOLE_BODY_METALLIC, CONSOLE_BODY_ROUGHNESS)
		_apply_material_recursive(inst, body_mat)

	var screen_mat: StandardMaterial3D = _emissive_mat(screen_color, CONSOLE_SCREEN_EMISSION)
	screen_mat.roughness = 0.25
	# Overlay material: a second layer drawn on top of material_override that
	# adds the panel-texture detail. Lets the plate read as a real steel-panel
	# display rather than a flat rectangle. No emission on the overlay — only
	# the base material contributes the dim background glow.
	var overlay_mat: StandardMaterial3D = StandardMaterial3D.new()
	overlay_mat.albedo_texture = load(CONSOLE_SCREEN_OVERLAY_TEX)
	var screen_mi: MeshInstance3D = MeshInstance3D.new()
	# Named so external scripts (gate_console.gd) can find the plate and
	# attach a TextMesh child for the readout.
	screen_mi.name = "ScreenPlate"
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = CONSOLE_SCREEN_SIZE
	screen_mi.mesh = screen_box
	screen_mi.material_override = screen_mat
	screen_mi.material_overlay = overlay_mat
	# Plate is dimly emissive — no shadow casting (would just darken the
	# console housing beneath it with a tiny crisp box silhouette).
	screen_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen_mi.position = Vector3(0.0, CONSOLE_SCREEN_PLATE_Y, CONSOLE_SCREEN_PLATE_Z)
	screen_mi.rotation = Vector3(deg_to_rad(CONSOLE_SCREEN_TILT_DEG), 0.0, 0.0)
	stage.add_child(screen_mi)


# Generic Space Kit desk_computer.glb spawner — used by kino-room's
# corner-desk + chair decor. Control room now uses _spawn_station_console
# instead (computer-wide.glb has a stronger silhouette).
static func _spawn_kenney_console(world: Node3D, glb: PackedScene, pos: Vector3, yaw: float) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "Console"
	holder.position = pos
	holder.rotation.y = yaw
	# Space Kit assets are authored ~1u = 1m. A 2× upscale puts a desk at
	# realistic console height (~1.6 m) without distorting proportions.
	holder.scale = Vector3(2.0, 2.0, 2.0)
	world.add_child(holder)

	var inst: Node = glb.instantiate()
	holder.add_child(inst)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.36, 0.38, 0.42)
	body_mat.metallic = 0.7
	body_mat.roughness = 0.45
	_apply_material_recursive(inst, body_mat)

	# Emissive screen plate floating just above the desk surface — gives every
	# console a glowing readout that catches the eye from across the room.
	var screen_mat: StandardMaterial3D = _emissive_mat(Color(1.0, 0.55, 0.18), 2.6)
	var screen_mi: MeshInstance3D = MeshInstance3D.new()
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = Vector3(0.45, 0.02, 0.30)
	screen_mi.mesh = screen_box
	screen_mi.material_override = screen_mat
	# Top of the GLB desk surface, in the model's local space (before scale).
	screen_mi.position = Vector3(0.0, 0.55, 0.0)
	holder.add_child(screen_mi)


# Walk a GLB instance and stamp `mat` onto every surface of every MeshInstance3D.
# Used to recover Kenney GLBs whose embedded textures were dropped by the
# Godot glTF importer.
static func _apply_material_recursive(root: Node, mat: Material) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root
		var surf_count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i in surf_count:
			mi.set_surface_override_material(i, mat)
	for child in root.get_children():
		_apply_material_recursive(child, mat)


# Kino room: a working drone bay. Two wall shelves of dormant kino spheres on
# the -Z wall, a centre pedestal where the player's active kino rests, an
# operator workbench (Kenney desk_computer + desk_chair) on the -X wall for the
# kino remote pilot, and a row of storage barrels along the +X wall. A warm
# pedestal light + a ceiling lamp panel keep the scene readable.
static func _accent_kino_room(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var shelf_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.4, 0.55)
	var body_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.20, 0.24), 0.55, 0.35)
	var eye_mat: StandardMaterial3D = _emissive_mat(Color(0.95, 0.85, 0.55), 3.5)
	var pedestal_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.2), 0.3, 0.6)
	var pedestal_top_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 1.8)
	var lamp_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.5)

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5

	# --- Kino display shelves (signature: this is THE kino room) -----------
	for shelf_y in [1.2, 1.9]:
		_add_decor(world, shelf_mat,
			Vector3(0.0, shelf_y, -half_z + 0.35),
			Vector3(width - 0.8, 0.08, 0.6))
		var span: float = width - 1.6
		for k in 4:
			var x: float = -span * 0.5 + span * (float(k) / 3.0)
			_add_kino_ball(world, body_mat, eye_mat,
				Vector3(x, shelf_y + 0.20, -half_z + 0.35))

	# --- Centre pedestal — DO NOT MOVE. room.gd::_spawn_kino_pickup places
	# the working kino + interactable hitbox at exactly (0, 1.05, 0).
	_add_decor(world, pedestal_mat, Vector3(0.0, 0.5, 0.0), Vector3(0.9, 1.0, 0.9))
	_add_decor(world, pedestal_top_mat, Vector3(0.0, 1.025, 0.0), Vector3(0.7, 0.05, 0.7))

	# Soft warm pool around the pedestal so the working kino reads as the
	# centerpiece — without this the eye drifts to the brighter shelf kinos.
	var pedestal_light: OmniLight3D = OmniLight3D.new()
	pedestal_light.name = "PedestalLight"
	pedestal_light.light_color = (palette["accent"] as Color).lerp(Color(1.0, 0.92, 0.78), 0.4)
	pedestal_light.light_energy = 1.8
	pedestal_light.omni_range = 4.5
	pedestal_light.omni_attenuation = 1.6
	pedestal_light.shadow_enabled = false
	pedestal_light.position = Vector3(0.0, 1.8, 0.0)
	world.add_child(pedestal_light)

	# --- Operator workbench against -X wall --------------------------------
	# A Kenney `desk_computerCorner.glb` (L-shaped desk with screen) faces +X
	# into the room, with a `desk_chair.glb` slid under it. This is where Eli
	# (or whoever inherits kino-pilot duty) sits to fly a kino remotely.
	var corner_glb: PackedScene = load("res://models/props/space_kit/desk_computerCorner.glb")
	var chair_glb: PackedScene = load("res://models/props/space_kit/desk_chair.glb")
	if corner_glb != null:
		# Tucked into -X wall, facing +X. Yaw of PI/2 rotates the desk so its
		# back-edge meets the wall.
		_spawn_kenney_console(world, corner_glb,
			Vector3(-half_x + 0.8, 0.0, 0.0), PI * 0.5)
	if chair_glb != null:
		var chair: Node3D = Node3D.new()
		chair.name = "OperatorChair"
		chair.position = Vector3(-half_x + 2.0, 0.0, 0.0)
		chair.rotation.y = -PI * 0.5
		chair.scale = Vector3(1.6, 1.6, 1.6)
		world.add_child(chair)
		var chair_inst: Node = chair_glb.instantiate()
		chair.add_child(chair_inst)
		var chair_mat: StandardMaterial3D = _make_mat(Color(0.22, 0.24, 0.28), 0.45, 0.55)
		_apply_material_recursive(chair_inst, chair_mat)

	# --- Storage barrels along +X wall -------------------------------------
	# Sample crates / spare-parts barrels lined up. A `machine_wireless.glb`
	# in the middle reads as a kino comms relay; the row of barrels around it
	# fills the wall without crowding the path.
	var barrels_glb: PackedScene = load("res://models/props/space_kit/barrels.glb")
	var wireless_glb: PackedScene = load("res://models/props/space_kit/machine_wireless.glb")
	if barrels_glb != null:
		for off_z in [-half_z + 2.5, half_z - 2.5]:
			_spawn_kenney_prop(world, barrels_glb,
				Vector3(half_x - 0.7, 0.0, off_z), -PI * 0.5, 1.6,
				Color(0.55, 0.45, 0.20))
	if wireless_glb != null:
		_spawn_kenney_prop(world, wireless_glb,
			Vector3(half_x - 0.7, 0.0, 0.0), -PI * 0.5, 1.6,
			Color(0.32, 0.36, 0.42))

	# --- Ceiling lamp -------------------------------------------------------
	_add_decor(world, lamp_mat, Vector3(0.0, height - 0.15, 0.0), Vector3(0.6, 0.05, 0.6))


# Spawn a Kenney prop GLB with a flat material override (textures stripped on
# import — see feedback_gltf_embedded_texture_lost). `tint` controls the body
# colour; `scale` is a uniform multiplier (Kenney space-kit is ~1u = 1m).
static func _spawn_kenney_prop(world: Node3D, glb: PackedScene, pos: Vector3, yaw: float, scale: float, tint: Color) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "KenneyProp"
	holder.position = pos
	holder.rotation.y = yaw
	holder.scale = Vector3(scale, scale, scale)
	world.add_child(holder)
	var inst: Node = glb.instantiate()
	holder.add_child(inst)
	var mat: StandardMaterial3D = _make_mat(tint, 0.55, 0.55)
	_apply_material_recursive(inst, mat)


# Procedural walk-blocker. `pos` is the prop's floor anchor; the body is auto-
# raised by size.y/2 so the box sits flush with the floor. Layer 1 only — camera
# spring-arm (layer 2) can still see over so the third-person view isn't pulled
# in tight whenever it grazes a chair.
static func _add_walk_blocker(world: Node3D, pos: Vector3, yaw: float, size: Vector3, body_name: String) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = body_name
	body.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	world.add_child(body)


# Small Kino sphere: dark body with an emissive iris sphere protruding from
# its front. Used by the kino-room shelf display.
static func _add_kino_ball(world: Node3D, body: StandardMaterial3D, eye: StandardMaterial3D, pos: Vector3) -> void:
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: SphereMesh = SphereMesh.new()
	body_mesh.radius = 0.13
	body_mesh.height = 0.26
	body_mesh.radial_segments = 16
	body_mesh.rings = 8
	body_mi.mesh = body_mesh
	body_mi.material_override = body
	body_mi.position = pos
	world.add_child(body_mi)
	var eye_mi: MeshInstance3D = MeshInstance3D.new()
	var iris: SphereMesh = SphereMesh.new()
	iris.radius = 0.05
	iris.height = 0.10
	iris.radial_segments = 12
	iris.rings = 6
	eye_mi.mesh = iris
	eye_mi.material_override = eye
	eye_mi.position = pos + Vector3(0.0, 0.0, 0.10)
	world.add_child(eye_mi)


# Quarters: a lived-in crew bunk. Kenney Furniture Kit `bedSingle.glb` against
# the -Z wall (positioned to match the Bed interactable in room.gd::_spawn_quarters_bed),
# a `lampSquareTable.glb` nightstand with a warm lamp glow, a tall
# `bathroomCabinet.glb` locker on the opposite wall, and (in wider rooms) a
# `desk.glb` + `chairDesk.glb` side workstation.
static func _accent_quarters(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	# Values dialled in via scenes/quarters_test.tscn workbench and then
	# generalised into half-axis formulas so the layout works in both
	# Eli's Quarters (10×12 m) and Crew Quarters Alpha (12.8×4.4 m).
	# Furniture switched to Kenney Space Station Kit (sleek sci-fi pieces
	# matching the Ancient ship aesthetic) — the Furniture-Kit domestic
	# pieces previously used didn't fit the visual story.
	const BED_SCALE: float = 2.5
	const LOCKER_SCALE: float = 2.5
	const DESK_SCALE: float = 2.5
	const CHAIR_SCALE: float = 2.5

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var bunk_w: float = min(width - 1.0, 3.0)
	var bunk_x: float = -half_x * 0.3

	# --- Bed (Space Station Kit bed-single.obj as Mesh resource) ----------
	# OBJ imports as a Mesh resource (not a PackedScene), so we instantiate
	# a MeshInstance3D and assign the mesh. Surface material override gives
	# the bed a warm cream tint that reads against the dark Ancient walls.
	var bed_mesh: Mesh = load("res://models/props/space_station_kit/bed-single.obj")
	if bed_mesh != null:
		var bed_mi: MeshInstance3D = MeshInstance3D.new()
		bed_mi.name = "BedProp"
		bed_mi.mesh = bed_mesh
		bed_mi.position = Vector3(bunk_x, 0.0, -half_z + 2.0)
		bed_mi.scale = Vector3.ONE * BED_SCALE
		var bed_mat: StandardMaterial3D = _make_mat(Color(0.62, 0.58, 0.52), 0.0, 0.55)
		# bed-single.obj exposes two surfaces (frame + mattress) — paint both
		# so we don't see the white default fallback on one of them.
		var surf_count: int = bed_mesh.get_surface_count()
		for i in surf_count:
			bed_mi.set_surface_override_material(i, bed_mat)
		world.add_child(bed_mi)

	# --- Wall locker on +Z wall (Space Station Kit container-tall) --------
	var locker_glb: PackedScene = load("res://models/props/space_station_kit/container-tall.glb")
	if locker_glb != null:
		_spawn_kenney_prop(world, locker_glb,
			Vector3(bunk_x, 0.0, half_z - 0.7), PI, LOCKER_SCALE,
			Color(0.38, 0.40, 0.44))

	# --- Side desk + chair (Space Station Kit table + chair-cushion) ------
	# Workbench yaws: desk -90° so its long axis runs +Z; chair +45° for the
	# casual "pulled out a bit" angle the user dialled in.
	if width > 6.0:
		var desk_glb: PackedScene = load("res://models/props/space_station_kit/table.glb")
		var chair_glb: PackedScene = load("res://models/props/space_station_kit/chair-cushion.glb")
		if desk_glb != null:
			var desk_pos: Vector3 = Vector3(half_x - 1.4, 0.0, 0.0)
			_spawn_kenney_prop(world, desk_glb, desk_pos, -PI * 0.5, DESK_SCALE,
				Color(0.45, 0.40, 0.35))
			# Desk walk-blocker SLIGHTLY oversized vs the visual mesh so the
			# player can't slip into the sides of the table.glb collider gap.
			# Long axis follows yaw -90° → world Z. 2.6 m × 1.0 m × 1.3 m
			# gives ~15 cm margin on each side of the visible desk top.
			_add_walk_blocker(world, desk_pos, -PI * 0.5,
				Vector3(1.3, 1.0, 2.6), "DeskBlocker")
		if chair_glb != null:
			# Tuck the chair into the NW corner of the desk (push -Z so it
			# sits against the desk's short end, and pull it slightly closer
			# in X) so the south-side approach to the desk top is clear. The
			# kino pickup sits at desk centre (world z=0); without this tuck
			# the chair sits squarely on the only walk-up path.
			var chair_pos: Vector3 = Vector3(half_x - 2.7, 0.0, -1.5)
			_spawn_kenney_prop(world, chair_glb, chair_pos, PI * 0.25, CHAIR_SCALE,
				Color(0.30, 0.32, 0.36))
			# Chair: ~1.1 m square seat-block footprint, 0.95 m to seat back. Yaw
			# +45° but the near-square box makes that visually irrelevant.
			_add_walk_blocker(world, chair_pos, PI * 0.25,
				Vector3(1.1, 0.95, 1.1), "ChairBlocker")

	# --- Wall sconces (replace the old nightstand-lamp combo) -------------
	# Two warm amber sconces flanking the bed on the back (-Z) wall, mounted
	# 2.6 m up so they read at standing-eye-level. Each sconce: dark housing
	# box + bright emissive plate + OmniLight3D pool.
	_add_wall_sconce(world, Vector3(-3.2, 2.6, -half_z + 0.15))
	_add_wall_sconce(world, Vector3(0.6, 2.6, -half_z + 0.15))


# Procedural wall sconce — a Node3D parent with a dark housing box, bright
# amber emissive plate, and OmniLight3D for the spill. Sized to match the
# scenes/quarters_test.tscn workbench placement so values stay portable.
static func _add_wall_sconce(world: Node3D, pos: Vector3) -> void:
	var sconce: Node3D = Node3D.new()
	sconce.name = "WallSconce"
	sconce.position = pos
	world.add_child(sconce)

	var housing_mat: StandardMaterial3D = _make_mat(Color(0.20, 0.20, 0.22), 0.5, 0.45)
	var housing_mi: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.46, 0.74, 0.16)
	housing_mi.mesh = housing_box
	housing_mi.material_override = housing_mat
	housing_mi.position = Vector3(0.0, 0.0, 0.08)
	sconce.add_child(housing_mi)

	var plate_mat: StandardMaterial3D = _emissive_mat(Color(1.0, 0.78, 0.50), 3.0)
	var plate_mi: MeshInstance3D = MeshInstance3D.new()
	var plate_box: BoxMesh = BoxMesh.new()
	plate_box.size = Vector3(0.32, 0.6, 0.08)
	plate_mi.mesh = plate_box
	plate_mi.material_override = plate_mat
	plate_mi.position = Vector3(0.0, 0.0, 0.16)
	sconce.add_child(plate_mi)

	var glow: OmniLight3D = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.78, 0.50)
	glow.light_energy = 2.4
	glow.omni_range = 4.5
	glow.omni_attenuation = 1.8
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 0.0, 0.3)
	sconce.add_child(glow)


# Hydroponics: working crop bay. Ceiling-spanning grow-light array (emissive
# green slab), four raised planter beds in a 2×2 grid stocked with Kenney
# Nature-Kit crops (corn, wheat, leafy, bushes), a central nutrient column,
# and a row of nutrient barrels along one wall.
static func _accent_hydroponics(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var grow_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 4.0)
	var planter_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.3), 0.4, 0.55)
	var soil_mat: StandardMaterial3D = _make_mat(Color(0.18, 0.13, 0.09), 0.0, 0.9)
	var column_mat: StandardMaterial3D = _make_mat(palette["accent"], 0.2, 0.4)

	# --- Ceiling grow-light array (signature green wash) -------------------
	_add_decor(world, grow_mat,
		Vector3(0.0, height - 0.15, 0.0),
		Vector3(width - 1.0, 0.05, depth - 1.0))

	# Soft green fill light cast downward — the emissive ceiling slab alone
	# doesn't actually illuminate the crops, so add one OmniLight per quadrant.
	for sx_l in [1.0, -1.0]:
		for sz_l in [1.0, -1.0]:
			var grow_light: OmniLight3D = OmniLight3D.new()
			grow_light.light_color = Color(0.55, 1.0, 0.65)
			grow_light.light_energy = 2.2
			grow_light.omni_range = max(width, depth) * 0.35
			grow_light.omni_attenuation = 1.6
			grow_light.shadow_enabled = false
			grow_light.position = Vector3(sx_l * width * 0.22, height - 0.5, sz_l * depth * 0.22)
			world.add_child(grow_light)

	# --- Planter beds (2×2 grid) -------------------------------------------
	var corn_glb: PackedScene = load("res://models/props/nature_kit/crops_cornStageD.glb")
	var wheat_glb: PackedScene = load("res://models/props/nature_kit/crops_wheatStageB.glb")
	var leaf_glb: PackedScene = load("res://models/props/nature_kit/crops_leafsStageB.glb")
	var bush_glb: PackedScene = load("res://models/props/nature_kit/plant_bushDetailed.glb")
	var pumpkin_glb: PackedScene = load("res://models/props/nature_kit/crop_pumpkin.glb")
	var crop_palette: Array = [corn_glb, wheat_glb, leaf_glb, bush_glb]
	var crop_tints: Array = [
		Color(0.40, 0.75, 0.25),
		Color(0.85, 0.78, 0.40),
		Color(0.30, 0.70, 0.30),
		Color(0.20, 0.55, 0.25),
	]

	var bed_w: float = min(width * 0.30, 8.0)
	var bed_d: float = min(depth * 0.30, 6.0)
	var off_x: float = width * 0.24
	var off_z: float = depth * 0.24
	var quad: int = 0
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			var bx: float = sx * off_x
			var bz: float = sz * off_z
			# Planter box (collider-less decor — RoomBuilder is decor-only).
			_add_decor(world, planter_mat,
				Vector3(bx, 0.35, bz),
				Vector3(bed_w, 0.7, bed_d))
			# Dark soil cap sits 1 cm proud of the rim so crops appear rooted.
			_add_decor(world, soil_mat,
				Vector3(bx, 0.71, bz),
				Vector3(bed_w - 0.25, 0.04, bed_d - 0.25))
			# Crop fill: 3 rows × 4 cols of one crop type per bed, jittered for
			# an organic look. Uniform crop per bed reads as a deliberate row.
			var crop_glb: PackedScene = crop_palette[quad % 4]
			var crop_tint: Color = crop_tints[quad % 4]
			if crop_glb != null:
				var rows: int = 3
				var cols: int = 4
				var inner_w: float = bed_w - 0.6
				var inner_d: float = bed_d - 0.6
				for r in rows:
					for c in cols:
						var rx: float = bx - inner_w * 0.5 + inner_w * (float(c) / float(cols - 1))
						var rz: float = bz - inner_d * 0.5 + inner_d * (float(r) / float(rows - 1))
						# A tiny deterministic jitter — different per cell but
						# stable across runs (no RNG seeding needed).
						var jitter_x: float = sin(float(quad * 17 + r * 3 + c)) * 0.08
						var jitter_z: float = cos(float(quad * 13 + r * 5 + c * 2)) * 0.08
						_spawn_kenney_prop(world, crop_glb,
							Vector3(rx + jitter_x, 0.73, rz + jitter_z),
							sin(float(quad + r + c)) * PI, 0.9, crop_tint)
			# A single pumpkin accent at the bed's near edge gives each bed a
			# focal point — like a "today's harvest" demonstration crop.
			if pumpkin_glb != null and (quad % 2 == 0):
				_spawn_kenney_prop(world, pumpkin_glb,
					Vector3(bx, 0.78, bz - bed_d * 0.40),
					sin(float(quad)) * PI, 1.1, Color(0.95, 0.55, 0.20))
			quad += 1

	# --- Central nutrient column -------------------------------------------
	_add_decor(world, column_mat,
		Vector3(0.0, height * 0.45, 0.0),
		Vector3(0.6, height * 0.9, 0.6))

	# --- Nutrient tanks along -X wall --------------------------------------
	# Space-kit barrels lined up — reads as the chemical supply for the beds.
	var barrels_glb: PackedScene = load("res://models/props/space_kit/barrels.glb")
	if barrels_glb != null:
		var half_x: float = width * 0.5
		var slots: int = 3
		for i in slots:
			var t: float = 0.0 if slots == 1 else float(i) / float(slots - 1)
			var bz_b: float = lerp(-depth * 0.3, depth * 0.3, t)
			_spawn_kenney_prop(world, barrels_glb,
				Vector3(-half_x + 0.8, 0.0, bz_b), PI * 0.5, 1.5,
				Color(0.45, 0.55, 0.40))


# Elevator / transport bay: central glowing transport pad with a cyan-emissive
# disc + rim, a matching ceiling cap, a Kenney `machine_generator.glb` lift
# mechanism against the -X wall, and a `machine_wireless.glb` call console on
# the +X wall. Warm cyan Omni lights pool on the pad and ceiling cap.
#
# Previously had four floor-to-ceiling corner pillars with cyan light strips
# climbing them. Removed once the wall-panel texture went in: the pillars and
# their strips read as visual noise stacked on top of the panel surface.
static func _accent_elevator(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var accent: Color = palette["accent"]
	var disc_mat: StandardMaterial3D = _emissive_mat(accent, 2.4)
	var ring_mat: StandardMaterial3D = _emissive_mat(accent, 3.4)
	var cap_mat: StandardMaterial3D = _emissive_mat(accent, 2.0)
	var panel_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.25), 0.55, 0.4)
	var panel_screen_mat: StandardMaterial3D = _emissive_mat(accent, 3.2)

	# --- Transport pad ------------------------------------------------------
	# Inner glowing disc + bright outer ring frame. Ring frame is 4 thin slabs
	# inset around the disc to read as a beveled platform edge.
	var pad_w: float = width - 1.4
	var pad_d: float = depth - 1.4
	_add_decor(world, disc_mat, Vector3(0.0, 0.025, 0.0), Vector3(pad_w, 0.05, pad_d))
	var rim_t: float = 0.10
	var rim_y: float = 0.07
	_add_decor(world, ring_mat,
		Vector3(0.0, rim_y, pad_d * 0.5 + rim_t * 0.5),
		Vector3(pad_w + rim_t * 2.0, 0.04, rim_t))
	_add_decor(world, ring_mat,
		Vector3(0.0, rim_y, -pad_d * 0.5 - rim_t * 0.5),
		Vector3(pad_w + rim_t * 2.0, 0.04, rim_t))
	_add_decor(world, ring_mat,
		Vector3(pad_w * 0.5 + rim_t * 0.5, rim_y, 0.0),
		Vector3(rim_t, 0.04, pad_d))
	_add_decor(world, ring_mat,
		Vector3(-pad_w * 0.5 - rim_t * 0.5, rim_y, 0.0),
		Vector3(rim_t, 0.04, pad_d))

	# --- Ceiling cap --------------------------------------------------------
	_add_decor(world, cap_mat,
		Vector3(0.0, height - 0.10, 0.0),
		Vector3(width - 1.2, 0.06, depth - 1.2))

	# --- Lift machinery against -X wall -------------------------------------
	# `machine_generator.glb` is a chunky pipe-and-housing unit that sells the
	# room as a real elevator shaft rather than an empty cube.
	var gen_glb: PackedScene = load("res://models/props/space_kit/machine_generator.glb")
	if gen_glb != null:
		_spawn_kenney_prop(world, gen_glb,
			Vector3(-width * 0.5 + 0.5, 0.0, -depth * 0.5 + 0.6),
			PI * 0.5, 1.4,
			Color(0.55, 0.58, 0.62))
		_spawn_kenney_prop(world, gen_glb,
			Vector3(-width * 0.5 + 0.5, 0.0, depth * 0.5 - 0.6),
			PI * 0.5, 1.4,
			Color(0.55, 0.58, 0.62))

	# --- Call console on +X wall --------------------------------------------
	# Wall-mounted `machine_wireless.glb` as the floor-selector console plus a
	# small emissive readout plate above it.
	var wireless_glb: PackedScene = load("res://models/props/space_kit/machine_wireless.glb")
	if wireless_glb != null:
		_spawn_kenney_prop(world, wireless_glb,
			Vector3(width * 0.5 - 0.5, 0.0, 0.0),
			-PI * 0.5, 1.0,
			Color(0.50, 0.55, 0.60))
	_add_decor(world, panel_mat,
		Vector3(width * 0.5 - 0.06, 1.55, 0.0),
		Vector3(0.06, 0.45, 0.55))
	_add_decor(world, panel_screen_mat,
		Vector3(width * 0.5 - 0.09, 1.60, 0.0),
		Vector3(0.04, 0.22, 0.40))

	# --- Lights --------------------------------------------------------------
	# Floor pool — the transport-pad glow.
	var pad_light: OmniLight3D = OmniLight3D.new()
	pad_light.name = "PadLight"
	pad_light.light_color = accent
	pad_light.light_energy = 1.8
	pad_light.omni_range = 4.5
	pad_light.omni_attenuation = 1.6
	pad_light.shadow_enabled = false
	pad_light.position = Vector3(0.0, 0.4, 0.0)
	world.add_child(pad_light)
	# Ceiling pool — picks out the cap and machinery housing.
	var cap_light: OmniLight3D = OmniLight3D.new()
	cap_light.name = "CapLight"
	cap_light.light_color = accent
	cap_light.light_energy = 2.0
	cap_light.omni_range = 6.0
	cap_light.omni_attenuation = 1.4
	cap_light.shadow_enabled = false
	cap_light.position = Vector3(0.0, height - 0.5, 0.0)
	world.add_child(cap_light)


# Storage room: industrial cargo bay. Rows of BoxMesh crates and barrels
# along both long walls, a ceiling emissive strip down the centreline, a wall-
# mounted indicator panel on the -Z wall, and a dim OmniLight from above.
# Deliberately cheap — no GLB loads, all procedural — so generated storage
# rooms build fast and remain readable as "stuff lives here."
static func _accent_storage(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var crate_mat: StandardMaterial3D = _make_mat(Color(0.45, 0.38, 0.28), 0.35, 0.65)
	var barrel_mat: StandardMaterial3D = _make_mat(Color(0.55, 0.48, 0.35), 0.40, 0.60)
	var strip_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 2.0)
	var panel_mat: StandardMaterial3D = _make_mat((palette["wall"] as Color).darkened(0.50), 0.50, 0.55)
	var indicator_mat: StandardMaterial3D = _emissive_mat(palette["accent"], 3.5)

	var half_x: float = width * 0.5
	var half_z: float = depth * 0.5
	var axis_z: bool = depth > width
	var long_len: float = depth if axis_z else width
	var short_len: float = width if axis_z else depth

	# --- Ceiling strip down the long axis centreline --------------------------
	var strip_len: float = long_len - 1.0
	if axis_z:
		_add_decor(world, strip_mat, Vector3(0.0, height - 0.12, 0.0), Vector3(0.20, 0.06, strip_len))
	else:
		_add_decor(world, strip_mat, Vector3(0.0, height - 0.12, 0.0), Vector3(strip_len, 0.06, 0.20))

	# --- Crate rows along both long walls -------------------------------------
	# Number of crate stacks derived from corridor length so short vestibules
	# and long halls both get appropriately dense rows.
	var crate_count: int = max(2, int(floor(long_len / 2.5)))
	var crate_spacing: float = strip_len / float(crate_count)
	var crate_w: float = 0.80
	var crate_h: float = 0.85
	var crate_d: float = 0.70
	var barrel_radius: float = 0.28
	var wall_inset: float = 0.55   # how far off the wall the crate front sits

	for i in crate_count:
		var along: float = -strip_len * 0.5 + crate_spacing * (float(i) + 0.5)
		for side in [1.0, -1.0]:
			var perp: float = side * (short_len * 0.5 - wall_inset)
			# Alternate crates and barrels for visual variety.
			if i % 3 == 2:
				# Barrel pair: two stacked cylinders drawn as thin boxes (cylinders are costlier; boxes match the game's prop convention).
				var barrel_pos: Vector3
				if axis_z:
					barrel_pos = Vector3(perp, crate_h * 0.5, along)
				else:
					barrel_pos = Vector3(along, crate_h * 0.5, perp)
				_add_decor(world, barrel_mat, barrel_pos, Vector3(barrel_radius * 2.0, crate_h, barrel_radius * 2.0))
			else:
				# Crate box.
				var crate_pos: Vector3
				if axis_z:
					crate_pos = Vector3(perp, crate_h * 0.5, along)
				else:
					crate_pos = Vector3(along, crate_h * 0.5, perp)
				_add_decor(world, crate_mat, crate_pos, Vector3(crate_w, crate_h, crate_d))
				# Second crate stacked on top for depth.
				if i % 2 == 0:
					var top_pos: Vector3 = crate_pos + Vector3(0.0, crate_h, 0.0)
					_add_decor(world, crate_mat, top_pos, Vector3(crate_w * 0.85, crate_h * 0.85, crate_d * 0.85))

	# --- Wall indicator panel on -Z face (works for both axis orientations) ---
	var panel_pos: Vector3 = Vector3(0.0, 1.55, -half_z + 0.04)
	_add_decor(world, panel_mat, panel_pos, Vector3(0.55, 0.42, 0.06))
	_add_decor(world, indicator_mat, panel_pos + Vector3(0.0, 0.10, 0.04), Vector3(0.08, 0.08, 0.03))

	# --- Overhead fill OmniLight ----------------------------------------------
	var over_light: OmniLight3D = OmniLight3D.new()
	over_light.name = "StorageLight"
	over_light.light_color = (palette["accent"] as Color).lerp(Color(1.0, 0.88, 0.72), 0.50)
	over_light.light_energy = 1.4
	over_light.omni_range = max(width, depth) * 0.75 + 3.0
	over_light.omni_attenuation = 1.6
	over_light.shadow_enabled = false
	over_light.position = Vector3(0.0, height - 0.55, 0.0)
	world.add_child(over_light)


# ----- palette ---------------------------------------------------------------

static func _palette_for(template_id: String) -> Dictionary:
	match template_id:
		"corridor-template":
			return {
				"floor": Color(0.25, 0.25, 0.29, 1.0),
				"wall": Color(0.32, 0.33, 0.38, 1.0),
				"ceiling": Color(0.16, 0.17, 0.19, 1.0),
				"accent": Color(1.0, 0.55, 0.18, 1.0),
			}
		"control-room-template":
			return {
				# Brighter brushed-steel walls + cool dark floor so the orange
				# accents (amber band, console screens) really pop. The grate
				# overlay built in _accent_control_room sits on top of `floor`.
				"floor": Color(0.16, 0.18, 0.20, 1.0),
				"wall": Color(0.62, 0.66, 0.72, 1.0),
				"ceiling": Color(0.22, 0.24, 0.27, 1.0),
				"accent": Color(1.0, 0.55, 0.18, 1.0),
			}
		"kino-room-template":
			return {
				"floor": Color(0.26, 0.24, 0.22, 1.0),
				"wall": Color(0.34, 0.32, 0.30, 1.0),
				"ceiling": Color(0.18, 0.17, 0.16, 1.0),
				"accent": Color(0.85, 0.70, 0.45, 1.0),
			}
		"quarters-template":
			return {
				"floor": Color(0.24, 0.23, 0.25, 1.0),
				"wall": Color(0.40, 0.35, 0.34, 1.0),
				"ceiling": Color(0.18, 0.17, 0.18, 1.0),
				"accent": Color(0.75, 0.62, 0.50, 1.0),
			}
		"hydroponics-template":
			return {
				"floor": Color(0.20, 0.24, 0.21, 1.0),
				"wall": Color(0.28, 0.34, 0.30, 1.0),
				"ceiling": Color(0.10, 0.13, 0.11, 1.0),
				"accent": Color(0.30, 1.0, 0.45, 1.0),
			}
		"elevator-template":
			return {
				"floor": Color(0.18, 0.20, 0.24, 1.0),
				"wall": Color(0.26, 0.30, 0.36, 1.0),
				"ceiling": Color(0.10, 0.12, 0.14, 1.0),
				"accent": Color(0.20, 0.85, 1.0, 1.0),
			}
		"storage-template":
			return {
				"floor": Color(0.22, 0.20, 0.18, 1.0),
				"wall": Color(0.30, 0.28, 0.26, 1.0),
				"ceiling": Color(0.12, 0.11, 0.10, 1.0),
				"accent": Color(0.90, 0.60, 0.20, 1.0),
			}
		_:
			return {
				"floor": Color(0.28, 0.28, 0.30, 1.0),
				"wall": Color(0.36, 0.36, 0.40, 1.0),
				"ceiling": Color(0.18, 0.18, 0.20, 1.0),
				"accent": Color(0.80, 0.80, 0.85, 1.0),
			}


# ----- low-level helpers -----------------------------------------------------

static func _add_box(parent: StaticBody3D, mat: StandardMaterial3D, pos: Vector3, size: Vector3) -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	parent.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _add_decor(world: Node3D, mat: StandardMaterial3D, pos: Vector3, size: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	world.add_child(mi)


static func _make_mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m


# Scale a colour's RGB by k (alpha forced to 1.0). Used for HDR albedo
# brightening — Color * float would also scale alpha, which we don't want.
static func _scale_rgb(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


# Robust wall-panel texture loader. Tries the editor-imported .ctex path first
# (fast GPU upload). Falls back to runtime PNG decode for headless smoke tests
# that may run BEFORE the editor has imported the PNG — see memory entry
# feedback_godot_png_no_import_sidecar. Result cached on the class so we don't
# re-decode 3 MB of PNG every time a room is built.
static func _load_wall_texture() -> Texture2D:
	if _wall_texture_cache != null:
		return _wall_texture_cache
	var tex: Texture2D = load(WALL_TEXTURE_PATH) as Texture2D
	if tex == null:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(WALL_TEXTURE_PATH)
		if bytes.size() > 0:
			var img: Image = Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				tex = ImageTexture.create_from_image(img)
	_wall_texture_cache = tex
	return tex


# Same robust-loader pattern as _load_wall_texture, for the floor grate.
static func _load_floor_texture() -> Texture2D:
	if _floor_texture_cache != null:
		return _floor_texture_cache
	var tex: Texture2D = load(FLOOR_TEXTURE_PATH) as Texture2D
	if tex == null:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(FLOOR_TEXTURE_PATH)
		if bytes.size() > 0:
			var img: Image = Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				tex = ImageTexture.create_from_image(img)
	_floor_texture_cache = tex
	return tex


# Floor material with the metal-grate texture tiled to ~FLOOR_TILE_M per
# repeat. Only used for generic templates (see FLOOR_TEMPLATE_SKIP). The
# per-template `palette["floor"]` colour still feeds in as a faint tint so
# kino-room reads warm and control-room reads cool over the same grate.
#
# metallic kept low (0.20): a high-metallic floor has almost no diffuse
# response and reads near-black in these Omni-lit rooms (no reflection probe),
# which fights the brightening. albedo is pushed up by FLOOR_BRIGHTNESS so the
# dark grate metal lifts while the slot-holes stay dark.
static func make_floor_mat(palette_color: Color, width: float, depth: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = _scale_rgb(palette_color.lerp(Color.WHITE, 0.85), FLOOR_BRIGHTNESS)
	m.metallic = 0.20
	m.roughness = 0.50
	var tex: Texture2D = _load_floor_texture()
	if tex != null:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(
			max(width / FLOOR_TILE_M, 0.1),
			max(depth / FLOOR_TILE_M, 0.1),
			1.0)
	return m


# Per-wall material clone with uv1_scale set so the panel texture tiles to
# ~WALL_TILE_*_M regardless of wall length. palette_color is folded in as a
# faint tint (texture stays dominant) so room theming still reads.
#
# PUBLIC: also called from gate_room.gd so the artisan gate-room walls share
# the same panel texture, tile size, and PNG-buffer fallback as procedural
# rooms. Keep the signature stable.
static func make_wall_mat(palette_color: Color, face_w: float, face_h: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = palette_color.lerp(Color.WHITE, 0.85)
	m.metallic = 0.30
	m.roughness = 0.58
	var tex: Texture2D = _load_wall_texture()
	if tex != null:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(
			max(face_w / WALL_TILE_U_M, 0.1),
			max(face_h / WALL_TILE_V_M, 0.1),
			1.0)
	return m


# Every procedural room gets a single soft OmniLight pulled toward the ceiling
# so wall normals catch real shading instead of relying on the world environment
# alone. Without this the rooms read "flat" next to the artisan gate room.
static func _add_fill_light(world: Node3D, width: float, depth: float, height: float, palette: Dictionary) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "FillLight"
	light.light_color = (palette["accent"] as Color).lerp(Color(1.0, 0.92, 0.85), 0.55)
	light.light_energy = 1.1
	light.omni_range = max(width, depth) * 0.9 + 4.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0.0, height - 0.6, 0.0)
	world.add_child(light)


static func _emissive_mat(tint: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = 0.0
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	return m
