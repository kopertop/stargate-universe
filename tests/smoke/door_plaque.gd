extends SceneTree

# Smoke test for door-plaque Ancient-text obfuscation (issues #64, decipher-on-entry).
#
# A transition door whose destination room is NOT DECIPHERED (the on-foot player
# hasn't walked into it — a Kino may have discovered it remotely) renders its
# plaque in the Ancient glyph FONT: the real room name, upper-cased, drawn in
# anquietas so it reads as a consistent cipher. Once the destination is
# DECIPHERED the plaque decodes to the real (readable-font) name. A door to an
# already-deciphered room shows the real name immediately, and the
# reverse-stamped two-way doors obey the same rule because they go through the
# same _add_plaque path keyed on target_room_id.
#
# The door is instantiated directly (not the whole room) so the unit under test
# — _apply_plaque_lock_state / _on_room_deciphered driving the held Label3D refs
# — is exercised deterministically. The live GameState autoload supplies
# rooms_deciphered + room_deciphered.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/door_plaque.gd

const DOOR_SCENE: String = "res://objects/door.tscn"
const ANCIENT_TEXT: String = "res://scripts/ancient_text.gd"

var _failures: Array[String] = []
var _passes: int = 0
var _door_scene: PackedScene
var _ancient: GDScript
var _ancient_font: Font = null
var _gs: Node


func _initialize() -> void:
	print("=== door_plaque smoke test ===")
	_door_scene = load(DOOR_SCENE) as PackedScene
	_ancient = load(ANCIENT_TEXT) as GDScript
	_gs = root.get_node_or_null("GameState")
	_expect(_door_scene != null, "objects/door.tscn loads")
	_expect(_ancient != null, "scripts/ancient_text.gd loads")
	_expect(_gs != null, "GameState autoload attached")
	if _door_scene == null or _ancient == null or _gs == null:
		_report()
		return

	# The Ancient glyph font drives the locked state. The asset must be present
	# (imported) for these tests — set_locked falls back to scramble without it.
	_ancient_font = _ancient.ancient_font()
	_expect(_ancient_font != null, "ancient_anquietas font loads (locked plaques use it)")

	_gs.call("reset")

	# Building a door runs its _ready (visual + plaque), which only fires once
	# the node enters the tree on the first idle frame — add_child during
	# _initialize defers it. Run the node-building checks past frame 0 (and
	# await process_frame is only safe outside _initialize).
	call_deferred("_run_checks")


func _run_checks() -> void:
	await process_frame
	await _test_undeciphered_door_shows_glyph_font()
	await _test_already_deciphered_door_shows_real_name()
	await _test_decipher_decodes_in_place()
	await _test_reverse_stamped_door_obfuscates()
	_report()


# Build a transition door to `target` with a known plaque name, add to tree so
# _ready runs (_build_visual + plaque), then settle one frame. Returns the door.
func _make_door(target: String, plaque: String) -> Node:
	var door: Node = _door_scene.instantiate()
	door.set("target_room_id", target)
	door.set("source_room_id", "control_interface_room")
	door.set("plaque_label", plaque)
	root.add_child(door)
	await process_frame
	return door


# Collect the plaque Label3D nodes under the door (mirrored pair).
func _plaque_labels(door: Node) -> Array[Label3D]:
	var out: Array[Label3D] = []
	for n in _all_descendants(door):
		if n is Label3D:
			out.append(n as Label3D)
	return out


func _all_descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out


# --- 1. undeciphered destination → real name in the Ancient FONT ------------
# The cipher is now the FONT, not scrambled text: the label shows the real name
# (upper-cased) rendered in anquietas. Plain English is never shown.
func _test_undeciphered_door_shows_glyph_font() -> void:
	var plaque: String = "Mess Hall"
	var door: Node = await _make_door("mess_hall_undeciph", plaque)
	var labels: Array[Label3D] = _plaque_labels(door)
	_expect(labels.size() == 2, "undeciphered door builds a mirrored plaque pair")
	for lbl in labels:
		_expect(lbl.font == _ancient_font, "undeciphered plaque is drawn in the Ancient font")
		_expect(lbl.text == plaque.to_upper(), "undeciphered plaque text is the upper-cased real name")
		_expect(lbl.text != plaque, "undeciphered plaque is not the readable mixed-case name")
	door.free()


# --- 2. already-deciphered destination → readable name + default font -------
func _test_already_deciphered_door_shows_real_name() -> void:
	_gs.call("decipher_room", "mess_hall_deciph")
	var plaque: String = "Mess Hall"
	var door: Node = await _make_door("mess_hall_deciph", plaque)
	var labels: Array[Label3D] = _plaque_labels(door)
	_expect(labels.size() == 2, "deciphered door builds a mirrored plaque pair")
	for lbl in labels:
		_expect(lbl.text == plaque, "already-deciphered plaque shows the real name immediately")
		_expect(lbl.font == null, "already-deciphered plaque uses the default (readable) font")
	door.free()


# --- 3. deciphering the room decodes the plaque in place --------------------
# In headless / instant_mode the reveal is synchronous (no tween) and settles on
# the real name in the readable font — no timing dependence.
func _test_decipher_decodes_in_place() -> void:
	var router: Node = root.get_node_or_null("SceneRouter")
	var prev_instant: bool = false
	if router != null:
		prev_instant = router.get("instant_mode") == true
		router.set("instant_mode", true)
	var plaque: String = "Hydroponics"
	var door: Node = await _make_door("hydroponics_live", plaque)
	# Pre-condition: locked in the Ancient font (not yet deciphered).
	for lbl in _plaque_labels(door):
		_expect(lbl.font == _ancient_font, "live door starts in the Ancient font before decipher")
	# Act: decipher the destination room (the player walked in).
	_gs.call("decipher_room", "hydroponics_live")
	# Assert: decoded in place to the real name in the readable font.
	for lbl in _plaque_labels(door):
		_expect(lbl.text == plaque, "deciphering destination decodes plaque to real name in place")
		_expect(lbl.font == null, "decoded plaque reverts to the readable font")
	if router != null:
		router.set("instant_mode", prev_instant)
	door.free()


# --- 4. reverse-stamped two-way doors obey the same rule --------------------
# room.gd stamps the return-side door with target_room_id = the room we came
# from + plaque_label = its humanized name, then erases the outgoing plaque.
# The obfuscation keys on target_room_id, so the reverse door obfuscates too.
func _test_reverse_stamped_door_obfuscates() -> void:
	var plaque: String = "Control Interface Room"
	var door: Node = await _make_door("control_interface_room_rev", plaque)
	for lbl in _plaque_labels(door):
		_expect(lbl.font == _ancient_font, "reverse-stamped door to undeciphered room uses the Ancient font")
		_expect(lbl.text == plaque.to_upper(), "reverse-stamped door shows the upper-cased real name")
	# Decipher it → decodes.
	var router: Node = root.get_node_or_null("SceneRouter")
	var prev_instant: bool = false
	if router != null:
		prev_instant = router.get("instant_mode") == true
		router.set("instant_mode", true)
	_gs.call("decipher_room", "control_interface_room_rev")
	for lbl in _plaque_labels(door):
		_expect(lbl.text == plaque, "reverse-stamped door decodes to real name on decipher")
		_expect(lbl.font == null, "reverse-stamped door reverts to the readable font")
	if router != null:
		router.set("instant_mode", prev_instant)
	door.free()


# --- harness ----------------------------------------------------------------
func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _report() -> void:
	print("passes: %d  failures: %d" % [_passes, _failures.size()])
	for f in _failures:
		print("  FAIL: " + f)
	quit(0 if _failures.is_empty() else 1)
