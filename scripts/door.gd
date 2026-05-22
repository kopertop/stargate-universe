class_name Door
extends Interactable

# Destiny-style blast door. Visible bi-fold mesh built procedurally so every Door
# instance in any scene gets the same SGU look without an external .glb dependency.
#
# Two flavors of behavior:
#   - target_scene set → press E transitions to that scene at the named spawn point
#     (door fades with scene-router; no in-place animation needed).
#   - target_scene blank → press E toggles the leaves open/closed (visual only).
#
# Orientation: leaves face +Z/-Z, seam runs along the Z axis (door swings out
# along X). Place the Door with a Y-rotation in the scene to face the right way.

@export var target_scene: String = ""
@export var target_spawn: String = ""
@export var locked: bool = false
@export var lock_message: String = "LOCKED — power is offline."
@export var open_prompt: String = "Open"
@export var transition_prompt: String = "Enter"
@export var requires_kino: bool = false
@export var requires_kino_message: String = "I need the Kino Remote first."

# Plaque shown above the door's frame: the destination room's display name.
# Leave empty to auto-derive from target_scene (e.g. crew_quarters.tscn →
# "Crew Quarters"). Set explicitly to override for canonical names like
# "Gate Room" or "Hull Breach — Compartment 14B".
@export var plaque_label: String = ""

# Canonical display names for scenes whose snake_case filename doesn't title
# -case cleanly. Keep in sync with the GameState.discover_room calls in each
# scene's controller script.
const PLAQUE_OVERRIDES: Dictionary = {
	"destiny_corridor": "Main Corridor",
	"gate_room": "Gate Room",
	"hull_breach": "Hull Breach",
	"eli_quarters": "Eli's Quarters",
	"corridor_crew": "Crew Corridor",
	"corridor_mess": "Mess Corridor",
}

# Visual tunables — kept in sync with the BoxShape3D on door.tscn (1.6 × 2.2 × 0.4).
const FRAME_WIDTH: float = 1.8
const FRAME_HEIGHT: float = 2.4
const FRAME_DEPTH: float = 0.35
const LEAF_WIDTH: float = 0.78
const LEAF_HEIGHT: float = 2.05
const LEAF_THICKNESS: float = 0.14
const OPEN_OFFSET: float = 0.86          # how far each leaf slides outward
const TOGGLE_DURATION: float = 0.55

var _is_open: bool = false
var _left_leaf: Node3D
var _right_leaf: Node3D
var _status_mat: StandardMaterial3D
var _tween: Tween

func _ready() -> void:
	super()
	# Block player walk-through: Interactable._ready() sets layer to 4 (interactable
	# only). Doors also need layer 1 so the player capsule stops at the door instead
	# of clipping past it — otherwise they walk straight through the wall archway
	# beyond the door and, in the gate room, off the edge of the floor.
	collision_layer = 1 | 4
	_build_visual()
	_refresh_prompt()
	_refresh_status_light()

func _refresh_prompt() -> void:
	if locked:
		prompt = lock_message
	elif requires_kino and not GameState.kino_acquired:
		prompt = requires_kino_message
	elif target_scene != "":
		prompt = transition_prompt
	elif _is_open:
		prompt = "Close"
	else:
		prompt = open_prompt

func _on_interact(by: Node) -> void:
	if locked:
		return
	if requires_kino and not GameState.kino_acquired:
		return
	if target_scene != "":
		_transition(by)
	else:
		_toggle()

func _toggle() -> void:
	_is_open = not _is_open
	_refresh_prompt()
	_refresh_status_light()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	var left_target: float = -OPEN_OFFSET if _is_open else 0.0
	var right_target: float = OPEN_OFFSET if _is_open else 0.0
	if _left_leaf != null:
		var lp: Vector3 = _left_leaf.position
		_tween.tween_property(_left_leaf, "position",
			Vector3(-LEAF_WIDTH * 0.5 + left_target, lp.y, lp.z), TOGGLE_DURATION)
	if _right_leaf != null:
		var rp: Vector3 = _right_leaf.position
		_tween.tween_property(_right_leaf, "position",
			Vector3(LEAF_WIDTH * 0.5 + right_target, rp.y, rp.z), TOGGLE_DURATION)

func _transition(by: Node) -> void:
	# Walk-through sequence: open the leaves, drive the player up to (and a bit
	# past) the door's center, then trigger the cross-fade. The matching spawn-
	# side auto-walk lives in scene_router._place_player_at_spawn so the player
	# appears to step out of the new scene's doorway rather than teleport in.
	if not (by is CharacterBody3D and by.has_method("auto_walk_to")):
		if by is CharacterBody3D and by.has_method("set_input_locked"):
			by.set_input_locked(true)
		SceneRouter.change_to(target_scene, target_spawn)
		return
	# Strip the player-blocker bit (1) off the collision layer so the capsule
	# can pass through the door collider; keep layer 4 so the interact ray
	# still finds us mid-walk (harmless — interact is locked).
	collision_layer = 4
	# Snap the leaves open visually (the tween would lag behind the walk).
	if not _is_open:
		_is_open = true
		_refresh_status_light()
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.set_trans(Tween.TRANS_QUAD)
		_tween.set_ease(Tween.EASE_OUT)
		if _left_leaf != null:
			_tween.tween_property(_left_leaf, "position",
				Vector3(-LEAF_WIDTH * 0.5 - OPEN_OFFSET, _left_leaf.position.y, _left_leaf.position.z), 0.18)
		if _right_leaf != null:
			_tween.tween_property(_right_leaf, "position",
				Vector3(LEAF_WIDTH * 0.5 + OPEN_OFFSET, _right_leaf.position.y, _right_leaf.position.z), 0.18)
	var player_n: Node3D = by as Node3D
	var to_door: Vector3 = global_position - player_n.global_position
	to_door.y = 0.0
	var dist_to_door: float = to_door.length()
	# Rooms have SOLID exterior walls — the door's StaticBody3D sits as a
	# decorative recess in front of the wall, not a hole through it. Walking
	# PAST the door means slamming into the wall, which prevented auto_walk
	# from ever finishing (signal never emitted → fade never started).
	# Instead, walk UP TO the door (stop 0.5m short on the room side) and let
	# the cross-fade sell the "step through" illusion. The receiving scene's
	# spawn-marker walk handles the "step out into the next room" half.
	const APPROACH_OFFSET: float = 0.5
	if dist_to_door < APPROACH_OFFSET + 0.2:
		SceneRouter.change_to(target_scene, target_spawn)
		return
	var forward: Vector3 = to_door.normalized()
	# Target = APPROACH_OFFSET metres BEFORE the door (room side), not past it.
	# `forward` points from player toward door; subtracting puts the target on
	# the player-side of the door, clear of the solid wall behind.
	var target: Vector3 = global_position - forward * APPROACH_OFFSET
	by.call("auto_walk_to", target, 5.5)
	await by.auto_walk_finished
	SceneRouter.change_to(target_scene, target_spawn)

func unlock() -> void:
	locked = false
	_refresh_prompt()
	_refresh_status_light()

# ----- visual build ----------------------------------------------------------

func _build_visual() -> void:
	# Visual root sits at the same origin as the StaticBody3D; collider on
	# door.tscn covers (1.6 × 2.2 × 0.4) centred at y=1.1 — frame matches.
	var visual: Node3D = Node3D.new()
	visual.name = "Visual"
	add_child(visual)

	var frame_mat: StandardMaterial3D = _make_material(Color(0.18, 0.18, 0.21, 1.0), 0.55, 0.45)
	var leaf_mat: StandardMaterial3D = _make_material(Color(0.30, 0.28, 0.32, 1.0), 0.45, 0.55)
	var bronze_mat: StandardMaterial3D = _make_material(Color(0.42, 0.26, 0.10, 1.0), 0.80, 0.30)
	bronze_mat.emission_enabled = true
	bronze_mat.emission = Color(1.0, 0.50, 0.18, 1.0)
	bronze_mat.emission_energy_multiplier = 0.4
	_status_mat = _make_material(Color(0.55, 0.18, 0.10, 1.0), 0.0, 0.25)
	_status_mat.emission_enabled = true
	_status_mat.emission = Color(1.0, 0.25, 0.10, 1.0)
	_status_mat.emission_energy_multiplier = 3.0

	# Frame jamb — left + right vertical pillars, top header, bottom threshold.
	var jamb_w: float = 0.18
	var header_h: float = 0.25
	var center_y: float = FRAME_HEIGHT * 0.5
	# left jamb
	_attach_visual_box(visual,
		Vector3(-(FRAME_WIDTH * 0.5 - jamb_w * 0.5), center_y, 0.0),
		Vector3(jamb_w, FRAME_HEIGHT, FRAME_DEPTH), frame_mat)
	# right jamb
	_attach_visual_box(visual,
		Vector3((FRAME_WIDTH * 0.5 - jamb_w * 0.5), center_y, 0.0),
		Vector3(jamb_w, FRAME_HEIGHT, FRAME_DEPTH), frame_mat)
	# top header
	_attach_visual_box(visual,
		Vector3(0.0, FRAME_HEIGHT - header_h * 0.5, 0.0),
		Vector3(FRAME_WIDTH, header_h, FRAME_DEPTH), frame_mat)
	# threshold
	_attach_visual_box(visual,
		Vector3(0.0, 0.04, 0.0),
		Vector3(FRAME_WIDTH, 0.08, FRAME_DEPTH), frame_mat)
	# Bronze trim — thin emissive bar across the top header (signature SGU look).
	_attach_visual_box(visual,
		Vector3(0.0, FRAME_HEIGHT - header_h - 0.04, FRAME_DEPTH * 0.5 + 0.005),
		Vector3(FRAME_WIDTH - jamb_w * 2.0, 0.06, 0.02), bronze_mat)
	_attach_visual_box(visual,
		Vector3(0.0, FRAME_HEIGHT - header_h - 0.04, -FRAME_DEPTH * 0.5 - 0.005),
		Vector3(FRAME_WIDTH - jamb_w * 2.0, 0.06, 0.02), bronze_mat)
	# Status light — small emissive lozenge centred on the header, both sides.
	_attach_visual_box(visual,
		Vector3(0.0, FRAME_HEIGHT - header_h * 0.5, FRAME_DEPTH * 0.5 + 0.01),
		Vector3(0.24, 0.10, 0.03), _status_mat)
	_attach_visual_box(visual,
		Vector3(0.0, FRAME_HEIGHT - header_h * 0.5, -FRAME_DEPTH * 0.5 - 0.01),
		Vector3(0.24, 0.10, 0.03), _status_mat)

	# Two leaves — each is a Node3D pivot containing the actual MeshInstances so
	# we can tween the pivot's X position to slide it outward.
	_left_leaf = Node3D.new()
	_left_leaf.name = "LeftLeaf"
	_left_leaf.position = Vector3(-LEAF_WIDTH * 0.5, 0.0, 0.0)
	visual.add_child(_left_leaf)
	_build_leaf(_left_leaf, leaf_mat, bronze_mat, +1.0)

	_right_leaf = Node3D.new()
	_right_leaf.name = "RightLeaf"
	_right_leaf.position = Vector3(LEAF_WIDTH * 0.5, 0.0, 0.0)
	visual.add_child(_right_leaf)
	_build_leaf(_right_leaf, leaf_mat, bronze_mat, -1.0)

	# Destination plaque — only meaningful for transition doors. Toggle-only
	# doors (target_scene blank) get no plaque.
	if target_scene != "":
		_add_plaque(visual, frame_mat)


# Plaque sits on the wall plane above the frame so it reads as ship signage
# rather than competing with the bronze trim / status-light hardware on the
# door itself. Mirrored on both sides like the status light.
func _add_plaque(visual: Node3D, frame_mat: StandardMaterial3D) -> void:
	var label_text: String = _resolve_plaque_text()
	if label_text == "":
		return
	var plaque_w: float = FRAME_WIDTH - 0.1
	var plaque_h: float = 0.30
	var plaque_y: float = FRAME_HEIGHT + plaque_h * 0.5 + 0.08
	var plate_depth: float = 0.04
	# Dark backing plate so the white text reads against any wall colour.
	var plate_mat: StandardMaterial3D = _make_material(Color(0.08, 0.09, 0.11, 1.0), 0.30, 0.55)
	for side in [1.0, -1.0]:
		var z: float = side * (FRAME_DEPTH * 0.5 + plate_depth * 0.5)
		_attach_visual_box(visual,
			Vector3(0.0, plaque_y, z),
			Vector3(plaque_w, plaque_h, plate_depth), plate_mat)
		var label: Label3D = Label3D.new()
		label.text = label_text
		label.font_size = 64
		label.outline_size = 8
		label.modulate = Color(0.92, 0.94, 0.98, 1.0)
		label.outline_modulate = Color(0.04, 0.05, 0.07, 1.0)
		label.pixel_size = 0.0035
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = false
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Sit the label just in front of the backing plate so the text doesn't
		# z-fight the plate surface.
		label.position = Vector3(0.0, plaque_y, z + side * (plate_depth * 0.5 + 0.005))
		# Rotate the back-side label 180° around Y so its text reads from -Z too.
		if side < 0.0:
			label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		visual.add_child(label)


# Auto-derive the plaque text from target_scene unless plaque_label was set
# explicitly. Falls back to title-casing the snake_case filename.
func _resolve_plaque_text() -> String:
	if plaque_label != "":
		return plaque_label
	if target_scene == "":
		return ""
	var basename: String = target_scene.get_file().get_basename()
	if PLAQUE_OVERRIDES.has(basename):
		return PLAQUE_OVERRIDES[basename]
	var parts: PackedStringArray = basename.split("_", false)
	var out: PackedStringArray = PackedStringArray()
	for p in parts:
		if p.length() == 0:
			continue
		out.append(p.substr(0, 1).to_upper() + p.substr(1))
	return " ".join(out)


func _build_leaf(pivot: Node3D, leaf_mat: StandardMaterial3D, bronze_mat: StandardMaterial3D, inner_sign: float) -> void:
	# `inner_sign` is +1 for the left leaf (seam on the +X edge) and -1 for the right.
	# Used to put the chevron point on the seam-facing side.
	var leaf_y: float = LEAF_HEIGHT * 0.5 + 0.08
	# Body slab (centred at local origin so pivot tween moves the whole leaf).
	_attach_visual_box(pivot, Vector3(0.0, leaf_y, 0.0),
		Vector3(LEAF_WIDTH - 0.04, LEAF_HEIGHT, LEAF_THICKNESS), leaf_mat)
	# Bronze chevron trim — 3 angled bronze bars climbing the seam edge.
	var chev_x: float = inner_sign * (LEAF_WIDTH * 0.5 - 0.10)
	for i in 3:
		var y: float = 0.6 + float(i) * 0.45
		_attach_visual_box(pivot,
			Vector3(chev_x - inner_sign * 0.08, y, LEAF_THICKNESS * 0.5 + 0.01),
			Vector3(0.32, 0.05, 0.025), bronze_mat)
		_attach_visual_box(pivot,
			Vector3(chev_x - inner_sign * 0.08, y, -LEAF_THICKNESS * 0.5 - 0.01),
			Vector3(0.32, 0.05, 0.025), bronze_mat)
	# Outer-edge accent stripe (vertical bronze bar opposite the seam).
	_attach_visual_box(pivot,
		Vector3(-inner_sign * (LEAF_WIDTH * 0.5 - 0.08), leaf_y, LEAF_THICKNESS * 0.5 + 0.01),
		Vector3(0.04, LEAF_HEIGHT - 0.4, 0.025), bronze_mat)
	_attach_visual_box(pivot,
		Vector3(-inner_sign * (LEAF_WIDTH * 0.5 - 0.08), leaf_y, -LEAF_THICKNESS * 0.5 - 0.01),
		Vector3(0.04, LEAF_HEIGHT - 0.4, 0.025), bronze_mat)


func _refresh_status_light() -> void:
	if _status_mat == null:
		return
	var c: Color
	if locked:
		c = Color(1.0, 0.20, 0.10, 1.0)    # red — locked
	elif _is_open:
		c = Color(0.30, 1.0, 0.55, 1.0)    # green — passable
	elif target_scene != "":
		c = Color(0.30, 0.85, 1.0, 1.0)    # cyan — transition
	else:
		c = Color(1.0, 0.55, 0.18, 1.0)    # amber — closed, openable
	_status_mat.albedo_color = c * 0.5
	_status_mat.emission = c


func _make_material(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m


func _attach_visual_box(parent: Node3D, pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
