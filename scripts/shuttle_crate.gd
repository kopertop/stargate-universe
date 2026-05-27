class_name ShuttleCrate
extends Interactable

# A lootable supply crate in the Shuttle Dock. Searching it once yields its
# contents. `fuse_type` decides what's inside:
#   "small"   — the Small Fuse the jammed door panel needs
#   "large"   — a Large Fuse (wrong size for the door; flavor / future use)
#   "rations" — ration packs (added to the shared resource pool)
# Every crate holds something so none is a dead end.
#
# The crate owns its own body + lid meshes (built in _ready) so it can slide
# the lid off and prop it against the side when looted — a visible "emptied"
# cue. Clips like the consoles (layer 1|4) so the player can't walk through it.

@export var fuse_type: String = ""

const BODY_SIZE: Vector3 = Vector3(0.86, 0.86, 0.86)
const LID_SIZE: Vector3 = Vector3(0.92, 0.16, 0.92)
const LID_CLOSED_Y: float = 0.78

var _looted: bool = false
var _lid: MeshInstance3D = null

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

	# Open-topped container: four wall panels + a floor, no top face, so once
	# the lid pops off the player sees an empty interior rather than a solid
	# square. Panels share one (non-emissive) material — ShipAlert's emissive
	# tint pass skips them, so they revert cleanly when the alert clears.
	var wall_mat: StandardMaterial3D = _mat(Color(0.46, 0.39, 0.26), 0.3, 0.6)
	var inner_mat: StandardMaterial3D = _mat(Color(0.16, 0.13, 0.09), 0.2, 0.7)
	var s: float = BODY_SIZE.x
	var t: float = 0.08
	var cy: float = s * 0.5 + 0.02
	var half: float = s * 0.5
	var base_y: float = cy - s * 0.5
	# Outer floor + a slightly-raised darker inner floor (reads as the bottom).
	_box(Vector3(0.0, base_y + t * 0.5, 0.0), Vector3(s, t, s), wall_mat)
	_box(Vector3(0.0, base_y + t + 0.02, 0.0), Vector3(s - 2.0 * t, 0.04, s - 2.0 * t), inner_mat)
	# Four walls rising to the open rim.
	_box(Vector3(-half + t * 0.5, cy, 0.0), Vector3(t, s, s), wall_mat)
	_box(Vector3(half - t * 0.5, cy, 0.0), Vector3(t, s, s), wall_mat)
	_box(Vector3(0.0, cy, -half + t * 0.5), Vector3(s - 2.0 * t, s, t), wall_mat)
	_box(Vector3(0.0, cy, half - t * 0.5), Vector3(s - 2.0 * t, s, t), wall_mat)

	_lid = MeshInstance3D.new()
	_lid.name = "Lid"
	var lid_mesh: BoxMesh = BoxMesh.new()
	lid_mesh.size = LID_SIZE
	_lid.mesh = lid_mesh
	_lid.material_override = _mat(Color(0.30, 0.26, 0.18), 0.4, 0.55)
	_lid.position = Vector3(0.0, LID_CLOSED_Y, 0.0)
	add_child(_lid)

func _mat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

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
		_:
			GameState.find_rations()

# Shove the lid off the lip and topple it into a lean against the crate's -X
# (player-facing) side so the open crate reads as emptied. Two stages: a quick
# nudge up over the lip, then a slide-down-and-tilt so it props standing.
func _pop_lid() -> void:
	if _lid == null or not is_instance_valid(_lid):
		return
	# Lid stands on its long edge once tilted; half of LID_SIZE.x is its
	# standing half-height, so its base rests on the floor.
	var lean_pos: Vector3 = Vector3(-(BODY_SIZE.x * 0.5 + 0.10), LID_SIZE.x * 0.5, 0.0)
	var t: Tween = create_tween()
	t.tween_property(_lid, "position", Vector3(-0.18, LID_CLOSED_Y + 0.12, 0.0), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_lid, "position", lean_pos, 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_lid, "rotation:z", deg_to_rad(78.0), 0.42).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
