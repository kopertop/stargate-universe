extends SceneTree

# HUD interface-size smoke test (#141). Verifies the HUD scales uniformly from the
# Settings.hud_scale value while staying pinned to the viewport edges:
#   • _apply_hud_scale sets the HUD root scale to the Settings value
#   • the root size is viewport/scale, so scale*size == viewport (rendered rect
#     covers the screen → edge-anchored children land on the real screen edge)
#   • the Settings clamp bounds are honoured
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/hud_scale.gd

const HUD_SCENE: String = "res://objects/hud.tscn"

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null


func _initialize() -> void:
	print("=== hud_scale smoke test ===")
	call_deferred("_run")


func _run() -> void:
	var settings: Node = root.get_node_or_null("/root/Settings")
	_expect(settings != null, "Settings autoload present")
	if settings == null:
		_report()
		return

	var scene: PackedScene = load(HUD_SCENE) as PackedScene
	_expect(scene != null, "hud.tscn loads")
	if scene == null:
		_report()
		return
	_hud = scene.instantiate()
	root.add_child(_hud)
	await process_frame

	var vp: Vector2 = Vector2(root.get_viewport().get_visible_rect().size)
	_expect(_hud.has_method("_apply_hud_scale"), "hud exposes _apply_hud_scale")

	for s in [0.8, 1.0, 1.4]:
		settings.set("hud_scale", s)
		_hud.call("_apply_hud_scale")
		await process_frame
		var ctrl: Control = _hud as Control
		_expect(is_equal_approx(ctrl.scale.x, s) and is_equal_approx(ctrl.scale.y, s),
			"scale %0.2f: HUD root scale matches" % s)
		# size * scale must cover the viewport so edge anchors map to screen edges.
		var covered: Vector2 = ctrl.size * ctrl.scale
		_expect(absf(covered.x - vp.x) < 2.0 and absf(covered.y - vp.y) < 2.0,
			"scale %0.2f: size*scale covers the viewport (%.0fx%.0f)" % [s, covered.x, covered.y])

	# Clamp bounds (literals mirror Settings.HUD_SCALE_MIN/MAX — Object.get skips
	# consts, so we can't read them dynamically; keep these in sync with settings.gd).
	const SCALE_MAX: float = 1.6
	const SCALE_MIN: float = 0.7
	settings.call("set_hud_scale", 99.0)
	_expect(float(settings.get("hud_scale")) <= SCALE_MAX + 0.001,
		"set_hud_scale clamps to HUD_SCALE_MAX")
	settings.call("set_hud_scale", 0.0)
	_expect(float(settings.get("hud_scale")) >= SCALE_MIN - 0.001,
		"set_hud_scale clamps to HUD_SCALE_MIN")
	settings.set("hud_scale", 1.0)

	_finish()


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
