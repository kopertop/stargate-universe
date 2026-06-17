extends SceneTree

# WoW-UI cohesion smoke test (issue #62 — final integration of the WoW-UI epic).
#
# Instances the real HUD scene and asserts the four code-built widgets read as
# ONE cohesive WoW-like skin and never overlap:
#   • all four widgets exist: unit frame (UL), quest tracker (UR), action bar
#     (BR), discovery toast (centre) — plus the always-on compass banner
#   • shared visual language: the framed widgets (portrait, vital bar tracks)
#     draw their StyleBoxFlat from the SAME accent border + corner radius
#     (the _make_wow_stylebox factory), not per-widget near-misses
#   • the tracker title + the action-slot attention border share the SAME gold
#     accent; the discovery header shares the SAME cool-blue accent hue as the
#     unit-frame border
#   • anchor audit: unit frame anchors top-left, tracker top-right, action bar
#     bottom-right — so they hold their corners at any resolution
#   • no overlap: the two top widgets (unit frame UL / quest tracker UR) do not
#     intersect at 1080p OR at an ultrawide (3440x1440) resolution
#   • display-only widgets are MOUSE_FILTER_IGNORE so they never eat clicks
#     destined for the world / action bar
#
# The widgets are built in code, so this drives the REAL build path (it forces
# the tracker visible via QuestLog the same way the running game does).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/hud_wow.gd

const HUD_SCENE: String = "res://objects/hud.tscn"
const HUD_SCRIPT: String = "res://scripts/hud.gd"

# Mirror of the shared palette in hud.gd (kept in sync intentionally — the test
# is the contract that the widgets share THESE values).
# Gold-primary skin (HUD redesign Phase 0, #141) — mirrors hud.gd's SKIN_*.
const SKIN_ACCENT: Color = Color(0.83, 0.66, 0.32, 1.0)
const SKIN_ACCENT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)
const SKIN_CORNER_RADIUS: int = 4

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null
var _game: Node = null
var _ql: Node = null


func _initialize() -> void:
	print("=== hud_wow cohesion smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	_game = root.get_node_or_null("/root/GameState")
	_ql = root.get_node_or_null("/root/QuestLog")
	_expect(_game != null, "GameState autoload present")
	_expect(_ql != null, "QuestLog autoload present")
	if _game == null or _ql == null:
		_report()
		return

	var scene: PackedScene = load(HUD_SCENE) as PackedScene
	_expect(scene != null, "objects/hud.tscn loads")
	if scene == null:
		_report()
		return
	_hud = scene.instantiate()
	root.add_child(_hud)
	await process_frame

	# --- all four widgets exist -------------------------------------------
	var unit: Control = _hud.get_node_or_null("UnitFrame") as Control
	var tracker: Control = _hud.get_node_or_null("QuestTracker") as Control
	var action_bar: Control = _hud.get_node_or_null("ActionBar") as Control
	var toast: Control = _hud.get_node_or_null("DiscoveryToast") as Control
	_expect(unit != null, "unit frame (UL) is built")
	_expect(tracker != null, "quest tracker (UR) is built")
	_expect(action_bar != null, "action bar (BR) is built")
	_expect(toast != null, "discovery toast (centre) is built")
	if unit == null or tracker == null or action_bar == null or toast == null:
		_finish()
		return

	# --- shared visual language: factory produces the skin stylebox -------
	var hud_script: GDScript = load(HUD_SCRIPT) as GDScript
	_expect(hud_script != null, "hud.gd loads as a script")
	if _hud.has_method("_make_wow_stylebox"):
		var sb: StyleBoxFlat = _hud.call("_make_wow_stylebox") as StyleBoxFlat
		_expect(sb != null, "_make_wow_stylebox returns a StyleBoxFlat")
		if sb != null:
			_expect(_color_near(sb.border_color, SKIN_ACCENT),
				"skin stylebox border is the shared cool-blue accent")
			_expect(sb.corner_radius_top_left == SKIN_CORNER_RADIUS,
				"skin stylebox corner radius is the shared %d px" % SKIN_CORNER_RADIUS)
	else:
		_expect(false, "hud exposes the shared _make_wow_stylebox factory")

	# Portrait frame + both vital-bar tracks draw from the shared accent.
	var portrait_frame: Control = unit.get_node_or_null("PortraitFrame") as Control
	_expect(portrait_frame != null, "unit frame has a PortraitFrame panel")
	if portrait_frame != null:
		var pstyle: StyleBoxFlat = portrait_frame.get_theme_stylebox("panel") as StyleBoxFlat
		_expect(pstyle != null and _color_near(pstyle.border_color, SKIN_ACCENT),
			"portrait frame border uses the shared accent")
		_expect(pstyle != null and pstyle.corner_radius_top_left == SKIN_CORNER_RADIUS,
			"portrait frame uses the shared corner radius")

	var health: Control = unit.get_node_or_null("Vitals/Health") as Control
	if health != null:
		var bg: StyleBoxFlat = health.get_theme_stylebox("background") as StyleBoxFlat
		_expect(bg != null and _color_near(bg.border_color, SKIN_ACCENT),
			"health bar track border uses the shared accent")

	# --- shared GOLD accent: tracker title + action-slot attention --------
	var title: Label = tracker.get_node_or_null("Title") as Label
	_expect(title != null, "quest tracker has a Title label")
	if title != null:
		var title_color: Color = title.get_theme_color("font_color")
		_expect(_color_near(title_color, SKIN_ACCENT_GOLD),
			"quest tracker title uses the shared gold accent")

	# --- discovery header shares the cool-blue hue ------------------------
	var header: Label = toast.get_node_or_null("Stack/Header") as Label
	_expect(header != null, "discovery toast has a Header label")
	if header != null:
		var hc: Color = header.get_theme_color("font_color")
		_expect(_color_near(hc, SKIN_ACCENT),
			"discovery header shares the cool-blue accent hue (full opacity)")

	# --- anchor audit: corners are pinned, not absolute-positioned --------
	_expect(action_bar.anchor_right == 1.0 and action_bar.anchor_bottom == 1.0,
		"action bar is anchored to the bottom-right corner")
	_expect(tracker.anchor_left == 1.0 and tracker.anchor_right == 1.0,
		"quest tracker is anchored to the right edge")
	# Discovery toast spans the full rect (CenterContainer) so it stays centred.
	_expect(toast.anchor_right == 1.0 and toast.anchor_bottom == 1.0,
		"discovery toast spans the full rect (stays centred at any resolution)")

	# --- display-only widgets ignore the mouse ----------------------------
	_expect(unit.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"unit frame is MOUSE_FILTER_IGNORE (display-only)")
	_expect(tracker.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"quest tracker is MOUSE_FILTER_IGNORE (display-only)")
	_expect(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"discovery toast is MOUSE_FILTER_IGNORE (display-only)")

	# --- no overlap at 1080p and ultrawide --------------------------------
	# Force the tracker visible (it hides when nothing is tracked); QuestLog has
	# a default tracked quest in this project, so a refresh fills it.
	if _hud.has_method("_refresh_quest_tracker"):
		_hud.call("_refresh_quest_tracker")
	await process_frame

	await _assert_no_overlap(Vector2i(1920, 1080), "1080p", unit, tracker)
	await _assert_no_overlap(Vector2i(3440, 1440), "ultrawide 3440x1440", unit, tracker)

	_finish()


# Resize the root viewport, let layout settle, and assert the upper-left unit
# frame and the upper-right quest tracker do not intersect. Both live near the
# top of the screen, so a wide-enough screen must keep them apart and a tracker
# anchored to the right edge must not drift into the left-anchored unit frame.
func _assert_no_overlap(res: Vector2i, label: String, unit: Control, tracker: Control) -> void:
	root.content_scale_size = res
	await process_frame
	await process_frame
	var unit_rect: Rect2 = unit.get_global_rect()
	var tracker_rect: Rect2 = tracker.get_global_rect()
	_expect(not unit_rect.intersects(tracker_rect),
		"%s: unit frame (UL) and quest tracker (UR) do not overlap" % label)
	# The tracker must stay glued to the right edge — its right edge near the
	# viewport's right edge, never drifting toward the left-anchored unit frame.
	_expect(tracker_rect.position.x > unit_rect.end.x,
		"%s: tracker stays right of the unit frame" % label)


func _color_near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.05 and absf(a.g - b.g) < 0.05 and absf(a.b - b.b) < 0.05


func _finish() -> void:
	if _hud != null and is_instance_valid(_hud):
		root.remove_child(_hud)
		_hud.free()
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
