extends SceneTree

# Smoke test for the WoW-style player unit frame (issue #65).
#
# Instances the real HUD scene and asserts the upper-left unit frame:
#   • the UnitFrame node exists with a portrait, name plate, and the two bars
#   • the Eli portrait TextureRect.texture is non-null after the bind (the PNG
#     ships in sprites/portraits/), proving the shared PortraitLoader works
#   • the relocated Health + Oxygen bars track GameState.health / oxygen live
#   • the old bottom-left Status VBox is GONE
#   • the critical-health cue turns the fill red below the threshold and reverts
#     above it
#
# Reached by name (UnitFrame/Vitals/Health etc.); the bars are duck-typed via
# their `value` and the fill StyleBoxFlat via get_theme_stylebox.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/unit_frame.gd

const HUD_SCENE: String = "res://objects/hud.tscn"
const CRITICAL_RED: Color = Color(0.95, 0.3, 0.3, 0.98)
const CALM_GREEN: Color = Color(0.35, 0.85, 0.45, 0.95)

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null
var _game: Node = null


func _initialize() -> void:
	print("=== unit_frame smoke test ===")
	# Autoloads aren't reachable on /root in _initialize (no frame has ticked);
	# defer everything past frame 0.
	call_deferred("_run_checks")


func _run_checks() -> void:
	_game = root.get_node_or_null("/root/GameState")
	_expect(_game != null, "GameState autoload present")
	if _game == null:
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

	# --- structure --------------------------------------------------------
	var frame: Node = _hud.get_node_or_null("UnitFrame")
	_expect(frame != null, "HUD builds the upper-left UnitFrame")
	_expect(_hud.get_node_or_null("Status") == null,
		"old bottom-left Status VBox is removed")
	if frame == null:
		_finish()
		return

	var portrait: TextureRect = frame.get_node_or_null("PortraitFrame/Portrait") as TextureRect
	_expect(portrait != null, "UnitFrame has a Portrait TextureRect")
	var name_label: Label = frame.get_node_or_null("Vitals/PlayerName") as Label
	_expect(name_label != null and name_label.text == "Eli Wallace",
		"UnitFrame name plate reads 'Eli Wallace'")
	var health_bar: ProgressBar = frame.get_node_or_null("Vitals/Health") as ProgressBar
	var oxygen_bar: ProgressBar = frame.get_node_or_null("Vitals/Oxygen") as ProgressBar
	_expect(health_bar != null, "UnitFrame has a Health bar")
	_expect(oxygen_bar != null, "UnitFrame has an Oxygen bar")
	if portrait == null or health_bar == null or oxygen_bar == null:
		_finish()
		return

	# --- portrait renders -------------------------------------------------
	_expect(portrait.texture != null,
		"Eli portrait TextureRect.texture is non-null after bind")

	# --- bars track GameState live ----------------------------------------
	_set_health(64.0)
	await process_frame
	_expect(is_equal_approx(health_bar.value, 64.0),
		"Health bar tracks GameState.health (64)")
	_set_oxygen(42.0)
	await process_frame
	_expect(is_equal_approx(oxygen_bar.value, 42.0),
		"Oxygen bar tracks GameState.oxygen (42)")

	# --- critical-health cue ----------------------------------------------
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_expect(fill != null, "Health bar has a fill StyleBoxFlat")
	if fill != null:
		_set_health(20.0)  # below 30% of MAX_HEALTH
		await process_frame
		_expect(_color_near(fill.bg_color, CRITICAL_RED),
			"low health turns the fill red (critical cue)")
		_set_health(90.0)
		await process_frame
		_expect(_color_near(fill.bg_color, CALM_GREEN),
			"recovered health reverts the fill to calm green")

	_finish()


# Set health via the public mutator if present; otherwise emit the signal the
# HUD listens to directly so the test doesn't depend on a specific API name.
func _set_health(v: float) -> void:
	if _game.has_method("set_health"):
		_game.call("set_health", v)
		return
	_game.set("health", v)
	if _game.has_signal("health_changed"):
		_game.emit_signal("health_changed", v)


func _set_oxygen(v: float) -> void:
	if _game.has_method("set_oxygen"):
		_game.call("set_oxygen", v)
		return
	_game.set("oxygen", v)
	if _game.has_signal("oxygen_changed"):
		_game.emit_signal("oxygen_changed", v)


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
