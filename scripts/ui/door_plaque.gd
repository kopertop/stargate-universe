class_name DoorPlaque
extends Node3D

# WoW UI door plaque (issue #64).
#
# A Label3D on (both sides of) a door showing the destination room's display
# name as obfuscated Ancient text until that destination is DECIPHERED (the
# on-foot player walks into it), then decoding into readable English in place.
#
# This is the reusable WoW-UI-layer widget. door.gd already builds its plaques
# inline (and that path is exercised by tests/smoke/door_plaque.gd); this
# component factors the same behaviour out so future door types / custom doors
# can attach a plaque without re-implementing the cipher wiring.
#
# Lifecycle:
#   - build(text, sides) — stamp the mirrored Label3D(s) + backing plate(s).
#   - apply_lock_state(readable) — set every label to locked (Ancient glyph
#     font) or readable (plain English). Deterministic, no tween.
#   - decode(text) — live reveal: churn shuffling Lantean glyphs in the Ancient
#     font and then flip to the readable name. Honors instant_mode / headless.
#
# Honors SceneRouter.instant_mode (resolves immediately, no tween) so headless
# tests / captures never depend on timing.
#
# @no-save: display-only node script — no state to persist. Not an autoload.

const _ANCIENT_TEXT: GDScript = preload("res://scripts/ancient_text.gd")

# Visual tunables — mirror the inline values door.gd uses so a plaque built
# via this component reads identically to one built inline.
const FONT_SIZE: int = 64
const OUTLINE_SIZE: int = 8
const PIXEL_SIZE: float = 0.0035
const TEXT_COLOR: Color = Color(0.92, 0.94, 0.98, 1.0)
const OUTLINE_COLOR: Color = Color(0.04, 0.05, 0.07, 1.0)
# Decode animation duration for the live reveal.
const DECODE_DURATION: float = 1.4

# The resolved (readable) destination name the plaque decodes to.
var _resolved_text: String = ""
# Mirrored Label3D refs (one per side the plaque is stamped on).
var _labels: Array[Label3D] = []


# Build the plaque: a dark backing plate + a Label3D per side, parented to
# `parent`. `text` is the readable destination name. `sides` lists the local-Z
# offsets (e.g. [+z, -z]) to stamp — passing both mirrors the plaque so it
# reads from either side of the door. `plate_builder(parent, pos, size)` is a
# callback the caller supplies to attach the backing plate (so this component
# doesn't assume a specific plate material / mesh helper).
#
# After build(), call apply_lock_state() to set the initial locked/readable
# state based on whether the destination is deciphered.
func build(parent: Node3D, text: String, sides: Array, frame_height: float,
		plate_depth: float, plaque_w: float, plaque_h: float,
		plate_builder: Callable) -> void:
	_resolved_text = text
	if text == "":
		return
	var plaque_y: float = frame_height + plaque_h * 0.5 + 0.08
	for side in sides:
		var z: float = side * (plate_depth * 0.5 + plate_depth * 0.5)
		# Backing plate via the caller-supplied helper.
		plate_builder.call(parent, Vector3(0.0, plaque_y, z),
			Vector3(plaque_w, plaque_h, plate_depth))
		var label: Label3D = Label3D.new()
		label.text = text
		label.font_size = FONT_SIZE
		label.outline_size = OUTLINE_SIZE
		label.modulate = TEXT_COLOR
		label.outline_modulate = OUTLINE_COLOR
		label.pixel_size = PIXEL_SIZE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = false
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Sit the label just in front of the backing plate so it doesn't
		# z-fight the plate surface.
		label.position = Vector3(0.0, plaque_y, z + side * (plate_depth * 0.5 + 0.005))
		# Rotate the back-side label 180° around Y so its text reads from -Z too.
		if side < 0.0:
			label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		parent.add_child(label)
		_labels.append(label)


# Put every mirrored label into its locked (Ancient glyph) or readable state.
# Locked = the real name rendered in the Ancient font (a consistent cipher) for
# an un-deciphered destination; readable = plain English for a deciphered
# destination. Deterministic, no tween — safe for instant_mode/headless and
# for re-entering an already-deciphered room.
func apply_lock_state(readable: bool) -> void:
	for label: Label3D in _labels:
		if label == null:
			continue
		if readable:
			_ANCIENT_TEXT.set_readable_font(label)
			label.text = _resolved_text
		else:
			_ANCIENT_TEXT.set_locked(label, _resolved_text)


# Live reveal: churn shuffling Lantean glyphs in the Ancient font and then flip
# to the readable name. Honors instant_mode / headless (settles immediately).
func decode() -> void:
	if _resolved_text == "" or _labels.is_empty():
		return
	for label: Label3D in _labels:
		if label != null:
			_ANCIENT_TEXT.decode(label, _resolved_text, self, DECODE_DURATION)


# The resolved (readable) text the plaque decodes to.
func resolved_text() -> String:
	return _resolved_text


# The mirrored Label3D refs (one per side). Exposed so a caller / test can
# inspect the live state.
func labels() -> Array[Label3D]:
	return _labels