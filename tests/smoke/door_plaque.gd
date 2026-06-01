extends SceneTree

# Smoke test for door-plaque Ancient-text obfuscation (issue #64).
#
# A transition door whose destination room is UNDISCOVERED must render its
# plaque as Ancient glyphs (#61 scramble cipher), not the real room name. Once
# the destination room is discovered the plaque decodes to the real name. A
# door to an already-discovered room shows the real name immediately, and the
# reverse-stamped two-way doors obey the same rule because they go through the
# same _add_plaque path keyed on target_room_id.
#
# The door is instantiated directly (not the whole room) so the unit under test
# — _initial_plaque_text / _on_room_discovered driving the held Label3D refs —
# is exercised deterministically without per-room physics/build timing. The
# live GameState autoload supplies rooms_discovered + room_discovered.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/door_plaque.gd

const DOOR_SCENE: String = "res://objects/door.tscn"
const ANCIENT_TEXT: String = "res://scripts/ancient_text.gd"

var _failures: Array[String] = []
var _passes: int = 0
var _door_scene: PackedScene
var _ancient: GDScript
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

	_gs.call("reset")

	# Building a door runs its _ready (visual + plaque), which only fires once
	# the node enters the tree on the first idle frame — add_child during
	# _initialize defers it. Run the node-building checks past frame 0 (and
	# await process_frame is only safe outside _initialize).
	call_deferred("_run_checks")


func _run_checks() -> void:
	await process_frame
	await _test_undiscovered_door_shows_glyphs()
	await _test_already_discovered_door_shows_real_name()
	await _test_discovery_decodes_in_place()
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


# Collect the text of every plaque Label3D under the door (mirrored pair).
func _plaque_texts(door: Node) -> Array[String]:
	var out: Array[String] = []
	for n in _all_descendants(door):
		if n is Label3D:
			out.append((n as Label3D).text)
	return out


func _all_descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out


# --- 1. undiscovered destination → glyphs, never the real name --------------
func _test_undiscovered_door_shows_glyphs() -> void:
	var plaque: String = "Mess Hall"
	var door: Node = await _make_door("mess_hall_undisc", plaque)
	var texts: Array[String] = _plaque_texts(door)
	_expect(texts.size() == 2, "undiscovered door builds a mirrored plaque pair")
	var fully_scrambled: String = _ancient.scramble(plaque, 0.0)
	for t in texts:
		_expect(t != plaque, "undiscovered plaque text != real name ('%s')" % t)
		_expect(t == fully_scrambled, "undiscovered plaque == fully-obfuscated scramble")
		_expect(t.length() == plaque.length(), "obfuscated plaque preserves length")
	door.free()


# --- 2. already-discovered destination → real name immediately --------------
func _test_already_discovered_door_shows_real_name() -> void:
	_gs.call("discover_room", "mess_hall_disc", "")
	var plaque: String = "Mess Hall"
	var door: Node = await _make_door("mess_hall_disc", plaque)
	var texts: Array[String] = _plaque_texts(door)
	_expect(texts.size() == 2, "discovered door builds a mirrored plaque pair")
	for t in texts:
		_expect(t == plaque, "already-discovered plaque shows real name immediately")
	door.free()


# --- 3. discovering the room decodes the plaque in place --------------------
# In headless / instant_mode the reveal is synchronous (no tween) and settles on
# the real name — no timing dependence.
func _test_discovery_decodes_in_place() -> void:
	var router: Node = root.get_node_or_null("SceneRouter")
	var prev_instant: bool = false
	if router != null:
		prev_instant = router.get("instant_mode") == true
		router.set("instant_mode", true)
	var plaque: String = "Hydroponics"
	var door: Node = await _make_door("hydroponics_live", plaque)
	# Pre-condition: starts obfuscated.
	for t in _plaque_texts(door):
		_expect(t != plaque, "live door starts obfuscated before discovery")
	# Act: discover the destination room.
	_gs.call("discover_room", "hydroponics_live", "")
	# Assert: decoded in place to the real name.
	var after: Array[String] = _plaque_texts(door)
	for t in after:
		_expect(t == plaque, "discovering destination decodes plaque to real name in place")
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
	var texts: Array[String] = _plaque_texts(door)
	for t in texts:
		_expect(t != plaque, "reverse-stamped door to undiscovered room obfuscates")
		_expect(t == _ancient.scramble(plaque, 0.0), "reverse-stamped door uses same scramble cipher")
	# Discover it → decodes (instant_mode off here: assert the held-ref reveal).
	var router: Node = root.get_node_or_null("SceneRouter")
	var prev_instant: bool = false
	if router != null:
		prev_instant = router.get("instant_mode") == true
		router.set("instant_mode", true)
	_gs.call("discover_room", "control_interface_room_rev", "")
	for t in _plaque_texts(door):
		_expect(t == plaque, "reverse-stamped door decodes to real name on discovery")
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
