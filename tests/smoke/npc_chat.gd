extends Node

# Smoke test for passive NPC ambient chat bubbles (issue #35).
#
# Run as a SCENE (autoloads active) so npc.gd — which references the GameState
# autoload singleton — compiles. The bare GameState identifier does NOT resolve
# under `-s` (see memory: Godot SceneTree-script gotchas), so this rides the
# scene-test path like playthrough/resume.
#
#   godot --headless --quit-after 600 res://tests/smoke/npc_chat.tscn
#
# Asserts the personality-pool + bubble API on npc.gd:
#   • next_ambient_line() cycles the ambient pool deterministically and wraps.
#   • An NPC with no pools reports no ambient chatter and yields "".
#   • alert_lines override the ambient pool when the alert flag is active
#     (driven via the injectable alert_active arg — no need to mutate the world).
#   • show_ambient_bubble() lazily builds a single billboarded Label3D child and
#     toggles visibility through the public is_ambient_bubble_visible() API.

const NpcScript: Script = preload("res://scripts/npc.gd")

var _failures: Array[String] = []
var _passes: int = 0


func _ready() -> void:
	print("=== npc_chat smoke test ===")

	_test_ambient_pool_cycles_and_wraps()
	_test_empty_pools_report_no_chatter()
	_test_alert_lines_override_when_alert_active()
	_test_bubble_builds_one_label_and_toggles_visibility()

	_report()


# Build a bare Npc body, attach the script, set pools, add to the tree so
# is_inside_tree()-gated paths (add_child) are valid.
func _make_npc(ambient: Array[String], alert: Array[String]) -> Node:
	var body: StaticBody3D = StaticBody3D.new()
	body.set_script(NpcScript)
	body.set("character_name", "Tester")
	if not ambient.is_empty():
		body.set("ambient_lines", ambient)
	if not alert.is_empty():
		body.set("alert_lines", alert)
	add_child(body)
	return body


func _test_ambient_pool_cycles_and_wraps() -> void:
	var npc: Node = _make_npc(["a", "b", "c"], [])
	_expect(npc.call("_has_ambient_chatter") == true, "ambient pool -> has chatter")
	_expect(String(npc.call("next_ambient_line", 0)) == "a", "first ambient line is 'a'")
	_expect(String(npc.call("next_ambient_line", 0)) == "b", "second ambient line is 'b'")
	_expect(String(npc.call("next_ambient_line", 0)) == "c", "third ambient line is 'c'")
	_expect(String(npc.call("next_ambient_line", 0)) == "a", "ambient pool wraps back to 'a'")
	npc.free()


func _test_empty_pools_report_no_chatter() -> void:
	var npc: Node = _make_npc([], [])
	_expect(npc.call("_has_ambient_chatter") == false, "no pools -> no chatter")
	_expect(String(npc.call("next_ambient_line", 0)) == "", "no pools -> empty line")
	_expect(npc.call("is_ambient_bubble_visible") == false, "no pools -> bubble hidden")
	npc.free()


func _test_alert_lines_override_when_alert_active() -> void:
	var npc: Node = _make_npc(["small talk"], ["ALARM!"])
	# alert_active is injectable (0 = inactive, 1 = active) so both branches are
	# testable without mutating the live air-crisis world state.
	_expect(String(npc.call("next_ambient_line", 0)) == "small talk",
		"alert inactive -> ambient pool chosen")
	_expect(String(npc.call("next_ambient_line", 1)) == "ALARM!",
		"alert active -> alert pool overrides ambient")
	# An NPC with an EMPTY ambient pool but alert lines stays silent off-alert.
	var sentry: Node = _make_npc([], ["CONTACT!"])
	_expect(String(sentry.call("next_ambient_line", 0)) == "",
		"alert-only NPC stays silent when alert inactive")
	_expect(String(sentry.call("next_ambient_line", 1)) == "CONTACT!",
		"alert-only NPC speaks when alert active")
	npc.free()
	sentry.free()


func _test_bubble_builds_one_label_and_toggles_visibility() -> void:
	var npc: Node = _make_npc(["hi"], [])
	npc.call("show_ambient_bubble", "hello world")
	_expect(npc.call("is_ambient_bubble_visible") == true, "show -> bubble visible")
	var bubble: Node = npc.get_node_or_null("AmbientBubble")
	_expect(bubble != null and bubble is Label3D, "show builds a Label3D child")
	if bubble is Label3D:
		_expect((bubble as Label3D).text == "hello world", "bubble text matches")
		_expect((bubble as Label3D).visible == true, "bubble Label3D visible")
	# Showing again must NOT create a second Label3D — lazily reuse the one.
	npc.call("show_ambient_bubble", "again")
	var count: int = 0
	for c in npc.get_children():
		if c is Label3D and c.name == "AmbientBubble":
			count += 1
	_expect(count == 1, "second show reuses the single bubble node")
	npc.call("_hide_ambient_bubble")
	_expect(npc.call("is_ambient_bubble_visible") == false, "hide -> bubble hidden")
	if bubble is Label3D:
		_expect((bubble as Label3D).visible == false, "hidden bubble Label3D invisible")
	npc.free()


func _expect(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS: ", label)
	else:
		_failures.append(label)
		print("  FAIL: ", label)


func _report() -> void:
	print("--- npc_chat: %d passed, %d failed ---" % [_passes, _failures.size()])
	if _failures.is_empty():
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  ✗ ", f)
		get_tree().quit(1)
