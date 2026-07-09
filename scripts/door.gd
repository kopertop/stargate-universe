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
# When set, takes precedence over target_scene: door routes to scenes/room.tscn
# with this id stashed in GameState.next_room_id. target_scene remains for
# hand-authored scenes (gate_room.tscn).
@export var target_room_id: String = ""
# Room this door lives IN (the source side of the edge). Set by room.gd /
# gate_room.gd when the door is stamped. Used to mark the door as traversed
# in GameState so the Kino map can dim its pip.
@export var source_room_id: String = ""
@export var target_spawn: String = ""
@export var locked: bool = false
@export var lock_message: String = "LOCKED — power is offline."
@export var open_prompt: String = "Open"
@export var transition_prompt: String = "Enter"
@export var requires_kino: bool = false
@export var requires_kino_message: String = "I need the Kino Remote first."

# Merged-deck physical door (scenes/deck.tscn). When true the door never
# scene-transitions: E toggles the leaves open/shut IN PLACE, the state
# persists in ShipState under `door_id` (GameState.door_key(a, b) format),
# and remote open/close/lock commands from the control-room console arrive
# via ShipState.door_changed. target_room_id may still be set — it only
# feeds the plaque text in this mode.
@export var physical_mode: bool = false
@export var door_id: String = ""

# Plaque shown above the door's frame: the destination room's display name.
# Leave empty to auto-derive — `target_room_id` looks up `ShipLayout.room(id).name`
# (the canonical JSON name); `target_scene` falls back to title-casing the
# basename. Set explicitly for overrides like "Hull Breach — Compartment 14B".
@export var plaque_label: String = ""

# Visual tunables — kept in sync with the BoxShape3D on door.tscn (1.6 × 2.2 × 0.4).
const FRAME_WIDTH: float = 1.8
const FRAME_HEIGHT: float = 2.4
const FRAME_DEPTH: float = 0.35
const LEAF_WIDTH: float = 0.78
const LEAF_HEIGHT: float = 2.05
const LEAF_THICKNESS: float = 0.14
const OPEN_OFFSET: float = 0.86          # how far each leaf slides outward
const TOGGLE_DURATION: float = 0.55
const PLAQUE_DECODE_DURATION: float = 1.4   # seconds for the obfuscated→real reveal

# Pure scramble cipher (#61). Loaded by path rather than via the `AncientText`
# class_name, which may not be registered in the same headless -s run.
const ANCIENT_TEXT: GDScript = preload("res://scripts/ancient_text.gd")

var _is_open: bool = false
var _left_leaf: Node3D
var _right_leaf: Node3D
var _status_mat: StandardMaterial3D
var _tween: Tween

# Plaque Label3D nodes (mirrored on both sides) + the resolved destination name
# they decode to. Held so GameState.room_deciphered can animate them in place.
var _plaque_labels: Array[Label3D] = []
var _plaque_resolved: String = ""

func _ready() -> void:
	super()
	# Block player walk-through: Interactable._ready() sets layer to 4 (interactable
	# only). Doors also need layer 1 so the player capsule stops at the door instead
	# of clipping past it — otherwise they walk straight through the wall archway
	# beyond the door and, in the gate room, off the edge of the floor.
	collision_layer = 1 | 4
	_build_visual()
	# Physical doors restore their persisted state before the first prompt /
	# status-light refresh, and stay subscribed for remote (console) commands.
	if physical_mode and door_id != "":
		_is_open = ShipState.is_door_open(door_id)
		_apply_leaf_positions(_is_open, false)
		_apply_passability()
		ShipState.door_changed.connect(_on_ship_door_changed)
	_refresh_prompt()
	_refresh_status_light()
	# Decode the plaque in place when the destination room is DECIPHERED (the
	# on-foot player has walked into it) — NOT merely discovered remotely by a
	# Kino. Only meaningful for room-id transition doors (the obfuscated ones).
	if target_room_id != "" and not _plaque_labels.is_empty():
		GameState.room_deciphered.connect(_on_room_deciphered)

func _refresh_prompt() -> void:
	if _effective_locked():
		prompt = lock_message
	elif requires_kino and not Inventory.has("kino_remote"):
		prompt = requires_kino_message
	elif _is_transition_door():
		# Don't leak an un-deciphered room's name in the interact prompt (the
		# plaque above already shows it as glyphs). Generic until the player has
		# physically entered the destination; the real name returns afterward.
		if target_room_id != "" and not GameState.is_deciphered(target_room_id):
			prompt = "to Enter Room"
		else:
			prompt = transition_prompt
	elif _is_open:
		prompt = "Close"
	else:
		prompt = open_prompt

func _on_interact(by: Node) -> void:
	if _effective_locked():
		return
	if requires_kino and not Inventory.has("kino_remote"):
		return
	if _is_transition_door():
		_transition(by)
	elif physical_mode and door_id != "":
		# Route the toggle through the registry — the door_changed signal
		# animates us, so a console-driven change and a hand-toggle share one
		# code path (and the state persists across scene reloads + saves).
		ShipState.set_door_open(door_id, not _is_open)
	else:
		_toggle()


# Legacy `locked` export (elevator power gate) OR'd with the persistent
# ShipState lock the control-room console drives.
func _effective_locked() -> bool:
	if locked:
		return true
	return physical_mode and door_id != "" and ShipState.is_door_locked(door_id)


func _is_transition_door() -> bool:
	if physical_mode:
		return false
	return target_scene != "" or target_room_id != ""

func _toggle() -> void:
	_is_open = not _is_open
	_refresh_prompt()
	_refresh_status_light()
	_apply_leaf_positions(_is_open, true)


# Remote command from the control-room console (or any other ShipState
# writer). Locking an open door also arrives here as open=false.
func _on_ship_door_changed(changed_id: String, open: bool, _locked_state: bool) -> void:
	if changed_id != door_id:
		return
	if open != _is_open:
		_is_open = open
		_apply_leaf_positions(_is_open, is_inside_tree())
		# Pneumatic-ish servo cue — menu_open/close are the closest kit sounds
		# until a dedicated blast-door sample lands (see sounds/AGENTS.md).
		Audio.play("res://sounds/menu_open.ogg" if _is_open else "res://sounds/menu_close.ogg")
	_apply_passability()
	_refresh_prompt()
	_refresh_status_light()


# Physical doors block the player capsule only while shut; open doors keep
# layer 4 so the interact ray can still close them from either side.
func _apply_passability() -> void:
	if not physical_mode:
		return
	collision_layer = 4 if _is_open else (1 | 4)


# Slide both leaves to the open/shut pose — tweened in play, snapped when
# `animate` is false (initial state restore, headless tests).
func _apply_leaf_positions(open: bool, animate: bool) -> void:
	var left_target: float = -OPEN_OFFSET if open else 0.0
	var right_target: float = OPEN_OFFSET if open else 0.0
	var left_pos: Vector3 = Vector3(-LEAF_WIDTH * 0.5 + left_target, 0.0, 0.0)
	var right_pos: Vector3 = Vector3(LEAF_WIDTH * 0.5 + right_target, 0.0, 0.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		if _left_leaf != null:
			_left_leaf.position = Vector3(left_pos.x, _left_leaf.position.y, _left_leaf.position.z)
		if _right_leaf != null:
			_right_leaf.position = Vector3(right_pos.x, _right_leaf.position.y, _right_leaf.position.z)
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_IN_OUT)
	if _left_leaf != null:
		var lp: Vector3 = _left_leaf.position
		_tween.tween_property(_left_leaf, "position",
			Vector3(left_pos.x, lp.y, lp.z), TOGGLE_DURATION)
	if _right_leaf != null:
		var rp: Vector3 = _right_leaf.position
		_tween.tween_property(_right_leaf, "position",
			Vector3(right_pos.x, rp.y, rp.z), TOGGLE_DURATION)

func _transition(by: Node) -> void:
	# Walk-through sequence: open the leaves, drive the player up to (and a bit
	# past) the door's center, then trigger the cross-fade. The matching spawn-
	# side auto-walk lives in scene_router._place_player_at_spawn so the player
	# appears to step out of the new scene's doorway rather than teleport in.
	if not (by is CharacterBody3D and by.has_method("auto_walk_to")):
		if by is CharacterBody3D and by.has_method("set_input_locked"):
			by.set_input_locked(true)
		_route_to_destination()
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
	# Walls behind doors are SOLID — walk UP TO the door (stop short on the
	# room side) and let the cross-fade sell the "step through". The arrival
	# scene's spawn-marker walk handles "step out into the next room".
	const APPROACH_OFFSET: float = 0.5
	if dist_to_door < APPROACH_OFFSET + 0.2:
		_route_to_destination()
		return
	var forward: Vector3 = to_door.normalized()
	var target: Vector3 = global_position - forward * APPROACH_OFFSET
	by.call("auto_walk_to", target, 5.5)
	await by.auto_walk_finished
	_route_to_destination()


# gate_room is the lone artisan scene — every other room_id routes through
# the data-driven scenes/room.tscn. target_scene is the legacy fallback.
func _route_to_destination() -> void:
	if source_room_id != "" and target_room_id != "":
		GameState.mark_door_traversed(source_room_id, target_room_id)
	if target_room_id != "":
		if target_room_id == "gate_room":
			SceneRouter.change_to("res://scenes/gate_room.tscn", target_spawn)
		elif ShipState.merged_decks_enabled:
			# Merged-deck flow: land on the destination room's floor scene at
			# the deck-stamped arrival marker beside the door we came through.
			GameState.next_room_id = target_room_id
			SceneRouter.change_to("res://scenes/deck.tscn", _deck_spawn_key())
		else:
			GameState.next_room_id = target_room_id
			SceneRouter.change_to("res://scenes/room.tscn", target_spawn)
	else:
		SceneRouter.change_to(target_scene, target_spawn)


# Deck arrival markers are namespaced "Deck_<room>_From_<room>" (deck.gd stamps
# them) — per-pair unique across the whole floor, unlike the per-room-scene
# "From<Camel>" convention where several rooms can hold same-named markers.
func _deck_spawn_key() -> String:
	if source_room_id == "":
		return ""
	return "Deck_%s_From_%s" % [target_room_id, source_room_id]


func unlock() -> void:
	locked = false
	_refresh_prompt()
	_refresh_status_light()


func is_open() -> bool:
	return _is_open

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

	# Destination plaque — any door that knows where it leads gets one:
	# transition doors AND merged-deck physical doors (their target_room_id
	# feeds the sign). Plain toggle doors (no target at all) get no plaque.
	if target_scene != "" or target_room_id != "" or plaque_label != "":
		_add_plaque(visual, frame_mat)


# Plaque sits on the wall plane above the frame so it reads as ship signage
# rather than competing with the bronze trim / status-light hardware on the
# door itself. Mirrored on both sides like the status light.
func _add_plaque(visual: Node3D, frame_mat: StandardMaterial3D) -> void:
	_plaque_resolved = _resolve_plaque_text()
	if _plaque_resolved == "":
		return
	# Obfuscation only applies to data-driven room destinations: a room-id door
	# to an un-DECIPHERED neighbour shows the name in the Ancient glyph font (a
	# consistent cipher) until the player walks into that room. Hand-authored
	# target_scene doors (gate_room) have no room-id to gate on, so they always
	# read plainly. The per-label locked/readable state is applied after both
	# mirrored labels exist (see _apply_plaque_lock_state below).
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
		label.text = _plaque_resolved
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
		_plaque_labels.append(label)
	# Now that both mirrored labels exist, set each to its locked (Ancient
	# glyph) or readable state based on whether the destination is deciphered.
	_apply_plaque_lock_state()


# Priority: explicit plaque_label → ProceduralShip row name → title-cased id/scene.
func _resolve_plaque_text() -> String:
	if plaque_label != "":
		return plaque_label
	if target_room_id != "":
		var row: Dictionary = ProceduralShip.room(target_room_id)
		if not row.is_empty() and row.has("name"):
			return String(row["name"])
		return _title_case_snake(target_room_id)
	if target_scene != "":
		return _title_case_snake(target_scene.get_file().get_basename())
	return ""


# Put every mirrored plaque label into its locked (Ancient glyph) or readable
# state. Locked = the real name rendered in the Ancient font (a consistent
# cipher) for an un-deciphered destination; readable = plain English for a
# deciphered destination or a non-room-id door. Deterministic, no tween — safe
# for instant_mode/headless and for re-entering an already-deciphered room.
func _apply_plaque_lock_state() -> void:
	var readable: bool = _destination_deciphered()
	for label: Label3D in _plaque_labels:
		if label == null:
			continue
		if readable:
			ANCIENT_TEXT.set_readable_font(label)
			label.text = _plaque_resolved
		else:
			ANCIENT_TEXT.set_locked(label, _plaque_resolved)


# True when the plaque should read in plain English: non-room-id doors (no room
# to decipher) and room-id doors whose target room has been entered on foot.
func _destination_deciphered() -> bool:
	if target_room_id == "":
		return true
	return GameState.is_deciphered(target_room_id)


# Live reveal: when the room this door points at is DECIPHERED (entered on
# foot), decode every mirrored plaque label. The shared AncientText.decode()
# churns shuffling Lantean glyphs in the Ancient font and then flips to the
# readable name — honors instant_mode / headless (settles immediately) so
# captures and the playthrough never depend on timing.
func _on_room_deciphered(room_id: String) -> void:
	if room_id != target_room_id:
		return
	if _plaque_resolved == "" or _plaque_labels.is_empty():
		return
	for label: Label3D in _plaque_labels:
		if label != null:
			ANCIENT_TEXT.decode(label, _plaque_resolved, self, PLAQUE_DECODE_DURATION)
	# Destination now known — let the interact prompt name it too.
	_refresh_prompt()


func _title_case_snake(s: String) -> String:
	var parts: PackedStringArray = s.split("_", false)
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
	if _effective_locked():
		c = Color(1.0, 0.20, 0.10, 1.0)    # red — locked
	elif _is_open:
		c = Color(0.30, 1.0, 0.55, 1.0)    # green — passable
	elif _is_transition_door():
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
