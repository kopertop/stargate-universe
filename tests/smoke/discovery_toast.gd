extends SceneTree

# Smoke test for the center-screen room discovery toast (issue #63).
#
# Instances the real HUD scene, drives GameState.room_deciphered /
# current_room_changed, and asserts the toast lifecycle. The toast now fires on
# DECIPHER (the on-foot player walked in), NOT on remote Kino discovery:
#   • the very first decipher of the run (Gate Room on boot) shows NOTHING
#   • the first PLAYER-driven decipher shows the toast with the resolved
#     ShipLayout display name in the AncientText room-name line
#   • re-decipher does not re-show after the toast has been hidden
#   • a room change to a DIFFERENT room hides an in-flight toast instantly
#   • a room change INTO the room the toast is for does NOT hide it (entering a
#     room fires discover_room then set_current_room(SAME id))
#
# Runs under SceneRouter.instant_mode so the AncientText decode resolves on the
# same frame and the sting SFX is skipped (no audio queued headless). The HUD's
# internal nodes are reached by name (DiscoveryToast/.../RoomName) and the
# RoomName label is duck-typed (its `text` reflects the resolved name).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/discovery_toast.gd

const HUD_SCENE: String = "res://objects/hud.tscn"

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null
var _router: Node = null
var _game: Node = null
var _layout: Node = null
var _prev_instant: bool = false


func _initialize() -> void:
	print("=== discovery_toast smoke test ===")
	# Autoloads aren't reachable on /root in _initialize (no frame has ticked);
	# defer everything past frame 0.
	call_deferred("_run_checks")


func _run_checks() -> void:
	_router = root.get_node_or_null("/root/SceneRouter")
	_game = root.get_node_or_null("/root/GameState")
	_layout = root.get_node_or_null("/root/ShipLayout")
	_expect(_router != null, "SceneRouter autoload present")
	_expect(_game != null, "GameState autoload present")
	_expect(_layout != null, "ShipLayout autoload present")
	if _router == null or _game == null or _layout == null:
		_report()
		return

	# Decode + audio short-circuit: instant_mode resolves the toast on the same
	# frame and skips the sting so nothing is queued on the audio bus headless.
	_prev_instant = _router.get("instant_mode")
	_router.set("instant_mode", true)

	# Clean slate so the boot-suppression branch is exercised deterministically.
	# The HUD's mount guard keys on rooms_deciphered (the toast trigger).
	_game.set("rooms_discovered", [] as Array[String])
	_game.set("rooms_deciphered", [] as Array[String])

	var scene: PackedScene = load(HUD_SCENE) as PackedScene
	_expect(scene != null, "objects/hud.tscn loads")
	if scene == null:
		_finish()
		return
	_hud = scene.instantiate()
	root.add_child(_hud)
	await process_frame

	var toast: Node = _hud.get_node_or_null("DiscoveryToast")
	_expect(toast != null, "HUD builds the DiscoveryToast overlay")
	var name_label: Node = null
	if toast != null:
		name_label = toast.get_node_or_null("Stack/RoomName")
	_expect(name_label != null, "DiscoveryToast has a RoomName line")
	_expect(name_label is RichTextLabel, "RoomName is a RichTextLabel (per-char decode)")
	if toast == null or name_label == null:
		_finish()
		return

	# --- 1. Gate Room boot decipher is suppressed. --------------------------
	_game.decipher_room("gate_room")
	await process_frame
	_expect(not toast.visible, "boot Gate Room decipher shows NO toast")

	# --- 2. First player-driven decipher shows the toast + resolved name. ---
	_game.decipher_room("engineering_bay")
	await process_frame
	var expected: String = String(_layout.room("engineering_bay").get("name", "engineering_bay"))
	_expect(expected == "Engineering Bay", "ShipLayout resolves engineering_bay → 'Engineering Bay'")
	# Under instant_mode the toast resolves + hides on the same frame, but the
	# RoomName label must have been assigned the resolved name (parsed = visible
	# text without bbcode tags).
	_expect(name_label.call("get_parsed_text") == expected,
		"RoomName line shows the resolved ShipLayout name")
	# instant_mode hides immediately (no 3s tween wait headless).
	_expect(not toast.visible, "under instant_mode the toast resolves + hides same frame")

	# --- 3. Visible-toast lifecycle under the ANIMATED (non-instant) path. --
	_router.set("instant_mode", false)
	_game.decipher_room("hydroponics")
	await process_frame
	_expect(toast.visible, "animated path: a new decipher shows the toast")
	var hydro_name: String = String(_layout.room("hydroponics").get("name", "hydroponics"))
	# Parsed (visible) text length is preserved at every frame: resolved prefix +
	# upper-cased glyph suffix == same character count as the real name.
	_expect(name_label.call("get_parsed_text").length() == hydro_name.length(),
		"RoomName decode preserves the resolved-name length")

	# Mid-decode the UNRESOLVED suffix must be wrapped in the Ancient font tag
	# (per-character glyph→Latin reveal), NOT random ASCII punctuation. Regression
	# guard for "the blip shows random chars / decodes in one jump".
	var raw: String = String(name_label.get("text"))
	_expect(raw.contains("[font=") and raw.contains("anquietas"),
		"toast decode wraps unresolved letters in the Ancient font tag")
	var visible: String = name_label.call("get_parsed_text")
	var letters_only: bool = true
	for i in visible.length():
		var c: String = visible[i].to_upper()
		if c != " " and (c < "A" or c > "Z"):
			letters_only = false
	_expect(letters_only, "toast decode visible text is letters/spaces only, no ASCII punctuation")
	# One letter in, the reveal has NOT jumped to the full readable name.
	_expect(raw.contains("[font="), "decode is mid-reveal (still has glyphs), not a single jump to English")

	# --- 4. Entering the SAME room (set_current_room) must NOT hide it. -----
	_game.set_current_room("hydroponics")
	await process_frame
	_expect(toast.visible, "current_room_changed INTO the toast's own room keeps it shown")

	# --- 5. Moving to a DIFFERENT room short-circuits the fade. -------------
	_game.set_current_room("control_interface_room")
	await process_frame
	_expect(not toast.visible, "current_room_changed to a DIFFERENT room hides the toast instantly")

	# --- 6. Re-deciphering the SAME (already-shown) room: decipher_room is ---
	# idempotent and won't re-emit, so the toast stays hidden.
	_game.decipher_room("hydroponics")
	await process_frame
	_expect(not toast.visible, "re-deciphering an already-deciphered room shows nothing")

	_finish()


func _finish() -> void:
	if _hud != null and is_instance_valid(_hud):
		root.remove_child(_hud)
		_hud.free()
	if _router != null:
		_router.set("instant_mode", _prev_instant)
	_report()


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
