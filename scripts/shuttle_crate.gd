class_name ShuttleCrate
extends Interactable

# A lootable supply crate in the Shuttle Dock. Searching it once yields its
# contents. `fuse_type` decides what's inside:
#   "small"   — the Small Fuse the jammed door panel needs
#   "large"   — a Large Fuse (wrong size for the door; flavor / future use)
#   "rations" — ration packs (added to the shared resource pool)
# Every crate holds something so none is a dead end.
#
# Visual style (issue #37): Ancient-tech storage crate — a dark navy/charcoal
# metallic cube with reinforced corner brackets, recessed face panels framed
# by glowing cyan trim, glowing corner studs, and a small round port on the
# front. The crate owns its own body + hinged lid (built in _ready). When
# looted the lid swings UP and back on its rear-top hinge, revealing the dark
# interior — a visible "emptied" cue. Clips like the consoles (layer 1|4) so
# the player can't walk through it.

@export var fuse_type: String = ""

const BODY_SIZE: float = 0.86               # outer cube edge (m)
const WALL_T: float = 0.07                  # wall thickness
const LID_H: float = 0.16                   # lid slab height
const BRACKET_T: float = 0.10               # corner bracket thickness
const ACCENT: Color = Color(0.18, 0.78, 1.0)  # electric-cyan glow
const ACCENT_ENERGY: float = 2.4

var _looted: bool = false
var _lid: Node3D = null

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	prompt = "Search crate"
	add_to_group("shuttle_crate")
	_build_visual()

func _build_visual() -> void:
	# Interact collider runs up to chest height (1.5 m) so the player's
	# horizontal interact ray (origin ~1.1 m) hits it — a crate-height box
	# (0.9 m) would let the ray fly over the top. See
	# feedback_interactable_ray_chest_height.
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.9, 1.5, 0.9)
	cs.shape = box
	cs.position = Vector3(0.0, 0.75, 0.0)
	add_child(cs)

	var s: float = BODY_SIZE
	var half: float = s * 0.5
	var body_top: float = s              # body box occupies y in [0, s]
	var body_cy: float = s * 0.5

	# Shared materials. Body + interior are non-emissive so ShipAlert's
	# emissive tint pass (which only touches material_override meshes it
	# recolors) leaves the structure alone; the glow accents are their own
	# emissive material and read as Ancient energy lines.
	var body_mat: StandardMaterial3D = _mat(Color(0.09, 0.12, 0.18), 0.65, 0.45)
	var panel_mat: StandardMaterial3D = _mat(Color(0.13, 0.18, 0.26), 0.55, 0.5)
	var bracket_mat: StandardMaterial3D = _mat(Color(0.05, 0.07, 0.11), 0.7, 0.4)
	var inner_mat: StandardMaterial3D = _mat(Color(0.04, 0.06, 0.09), 0.2, 0.7)
	var glow_mat: StandardMaterial3D = _glow_mat()

	# --- Open-topped container: four walls + a floor, no top face. Once the
	# lid swings open the player sees a dark interior, not a solid square.
	var base_y: float = WALL_T * 0.5
	_box(Vector3(0.0, base_y, 0.0), Vector3(s, WALL_T, s), body_mat)
	# Slightly-raised darker inner floor reads as the bottom of the bin.
	_box(Vector3(0.0, WALL_T + 0.02, 0.0), Vector3(s - 2.2 * WALL_T, 0.04, s - 2.2 * WALL_T), inner_mat)
	# Four walls rising to the open rim.
	_box(Vector3(-half + WALL_T * 0.5, body_cy, 0.0), Vector3(WALL_T, s, s), body_mat)
	_box(Vector3(half - WALL_T * 0.5, body_cy, 0.0), Vector3(WALL_T, s, s), body_mat)
	_box(Vector3(0.0, body_cy, -half + WALL_T * 0.5), Vector3(s - 2.0 * WALL_T, s, WALL_T), body_mat)
	_box(Vector3(0.0, body_cy, half - WALL_T * 0.5), Vector3(s - 2.0 * WALL_T, s, WALL_T), body_mat)

	# --- Reinforced corner brackets (dark) on all four vertical edges. They
	# read as the riveted corner posts of the reference crate.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var bx: float = sx * (half - BRACKET_T * 0.5 + 0.005)
			var bz: float = sz * (half - BRACKET_T * 0.5 + 0.005)
			_box(Vector3(bx, body_cy, bz), Vector3(BRACKET_T, s + 0.01, BRACKET_T), bracket_mat)

	# --- Per-face detailing: a recessed panel + glowing border frame + four
	# glowing corner studs. The four walls share the treatment; the +Z face
	# (player-facing, toward -X… see room.gd placement) gets an extra round
	# port to match the reference.
	# Faces are addressed by an outward normal; panel sits just proud of the
	# wall so it doesn't z-fight.
	_decorate_face(Vector3(0, 0, 1), half, body_cy, s, panel_mat, glow_mat, true)
	_decorate_face(Vector3(0, 0, -1), half, body_cy, s, panel_mat, glow_mat, false)
	_decorate_face(Vector3(1, 0, 0), half, body_cy, s, panel_mat, glow_mat, false)
	_decorate_face(Vector3(-1, 0, 0), half, body_cy, s, panel_mat, glow_mat, false)

	# --- Hinged lid. A pivot at the rear-top edge so the lid swings up/back
	# like the reference open box. The lid slab is offset forward of the pivot
	# so it caps the crate when closed (rotation 0).
	_lid = Node3D.new()
	_lid.name = "LidHinge"
	_lid.position = Vector3(0.0, body_top, -half)  # rear-top edge
	add_child(_lid)
	var lid_slab: MeshInstance3D = MeshInstance3D.new()
	lid_slab.name = "LidSlab"
	var lid_mesh: BoxMesh = BoxMesh.new()
	lid_mesh.size = Vector3(s + 0.02, LID_H, s + 0.02)
	lid_slab.mesh = lid_mesh
	lid_slab.material_override = body_mat
	# Center of the slab sits forward (+Z) of the hinge by half the depth, and
	# up by half its height, so the closed lid rests flush on top of the body.
	lid_slab.position = Vector3(0.0, LID_H * 0.5, s * 0.5)
	_lid.add_child(lid_slab)
	# Recessed glow panel on the lid's top, framed like the walls.
	_decorate_lid_top(lid_slab, s, panel_mat, glow_mat)
	# Lid-edge corner brackets (slab-local frame) so the closed crate reads as
	# one block — they sit above the body's vertical corner posts when closed.
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			var lx: float = sx2 * (half - BRACKET_T * 0.5 + 0.005)
			var lz: float = sz2 * (half - BRACKET_T * 0.5 + 0.005)
			_box_on(lid_slab, Vector3(lx, 0.0, lz), Vector3(BRACKET_T, LID_H + 0.01, BRACKET_T), bracket_mat)

func _mat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	return m

func _glow_mat() -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = ACCENT
	m.emission_enabled = true
	m.emission = ACCENT
	m.emission_energy_multiplier = ACCENT_ENERGY
	m.metallic = 0.0
	m.roughness = 0.4
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

# Like _box but parented to an arbitrary node (used for lid children so they
# swing with the hinge).
func _box_on(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

# Inset recessed panel + glowing border frame + four corner studs on one wall
# face. `n` is the outward unit normal (±X or ±Z). `with_port` adds a round
# emissive port (the front face only).
func _decorate_face(n: Vector3, half: float, cy: float, s: float, panel_mat: StandardMaterial3D, glow_mat: StandardMaterial3D, with_port: bool) -> void:
	var face_c: Vector3 = n * (half + 0.001)
	face_c.y = cy
	# Inward axes spanning the face (tangent + up).
	var tangent: Vector3 = Vector3(n.z, 0.0, -n.x)  # perpendicular in-plane horizontal
	var up: Vector3 = Vector3(0.0, 1.0, 0.0)
	var panel_w: float = s * 0.62
	var panel_h: float = s * 0.62
	# Recessed central panel (slightly proud so it's visible, darker than body).
	var panel: MeshInstance3D = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	# Thin slab oriented so its thin axis is along the normal.
	pm.size = _axis_size(n, 0.025, panel_w, panel_h)
	panel.mesh = pm
	panel.material_override = panel_mat
	panel.position = face_c + n * 0.012
	add_child(panel)
	# Glowing frame: four thin emissive bars around the panel edge.
	var fw: float = 0.035
	var hw: float = panel_w * 0.5
	var hh: float = panel_h * 0.5
	var frame_c: Vector3 = face_c + n * 0.02
	_bar(frame_c + up * hh, n, _axis_size(n, 0.03, panel_w, fw), glow_mat)
	_bar(frame_c - up * hh, n, _axis_size(n, 0.03, panel_w, fw), glow_mat)
	_bar(frame_c + tangent * hw, n, _axis_size(n, 0.03, fw, panel_h), glow_mat)
	_bar(frame_c - tangent * hw, n, _axis_size(n, 0.03, fw, panel_h), glow_mat)
	# Four glowing corner studs near the face corners.
	var sw: float = s * 0.40
	var sh: float = s * 0.40
	for su in [-1.0, 1.0]:
		for st in [-1.0, 1.0]:
			var stud_c: Vector3 = face_c + up * (su * sh) + tangent * (st * sw) + n * 0.02
			_stud(stud_c, n, glow_mat)
	if with_port:
		# A round emissive port low-center on the front face.
		var port: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.09
		cyl.bottom_radius = 0.09
		cyl.height = 0.04
		port.mesh = cyl
		port.material_override = glow_mat
		port.position = face_c + n * 0.02 - up * (s * 0.12)
		# Lay the cylinder flat against the face: its local +Y must align to n.
		port.basis = _basis_y_to(n)
		add_child(port)

func _bar(center: Vector3, n: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	add_child(mi)

func _stud(center: Vector3, n: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = _axis_size(n, 0.03, 0.06, 0.06)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = center
	add_child(mi)

# Build a Vector3 size with `depth` along the |n| axis and `a`/`b` along the
# two in-plane axes (a=horizontal-tangent, b=vertical).
func _axis_size(n: Vector3, depth: float, a: float, b: float) -> Vector3:
	if absf(n.x) > 0.5:
		return Vector3(depth, b, a)
	return Vector3(a, b, depth)

# Orthonormal basis whose local +Y points along `dir` (for flat cylinders).
func _basis_y_to(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)

# Glow-framed recessed panel on top of the lid slab (parented to the slab so
# it swings with the lid). Local axes: X tangent, Z tangent, +Y is the top.
func _decorate_lid_top(slab: Node3D, s: float, panel_mat: StandardMaterial3D, glow_mat: StandardMaterial3D) -> void:
	var top_y: float = LID_H * 0.5
	var pw: float = s * 0.60
	var panel: MeshInstance3D = MeshInstance3D.new()
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(pw, 0.025, pw)
	panel.mesh = pm
	panel.material_override = panel_mat
	panel.position = Vector3(0.0, top_y + 0.012, 0.0)
	slab.add_child(panel)
	var fw: float = 0.035
	var hw: float = pw * 0.5
	var fy: float = top_y + 0.02
	_box_on(slab, Vector3(0.0, fy, hw), Vector3(pw, 0.03, fw), glow_mat)
	_box_on(slab, Vector3(0.0, fy, -hw), Vector3(pw, 0.03, fw), glow_mat)
	_box_on(slab, Vector3(hw, fy, 0.0), Vector3(fw, 0.03, pw), glow_mat)
	_box_on(slab, Vector3(-hw, fy, 0.0), Vector3(fw, 0.03, pw), glow_mat)

func _on_interact(_by: Node) -> void:
	if _looted:
		GameState.add_log("Already emptied this crate.")
		return
	_looted = true
	prompt = "Empty crate"
	_pop_lid()
	match fuse_type:
		"small":
			GameState.find_small_fuse()
		"large":
			GameState.find_large_fuse()
		"bus":
			GameState.find_bus_fuse()
		_:
			GameState.find_rations()

# Swing the hinged lid up and back about its rear-top edge so the open crate
# reads as emptied — matching the reference open box. Honors instant_mode so
# headless playthrough asserts don't race a tween.
func _pop_lid() -> void:
	if _lid == null or not is_instance_valid(_lid):
		return
	var open_angle: float = deg_to_rad(-112.0)  # swing up and back over the rear
	var router: Node = get_node_or_null("/root/SceneRouter")
	if router != null and router.get("instant_mode") == true:
		_lid.rotation.x = open_angle
		return
	var t: Tween = create_tween()
	t.tween_property(_lid, "rotation:x", open_angle, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
