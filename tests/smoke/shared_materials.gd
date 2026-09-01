extends SceneTree

# Smoke test for the SharedMaterials cached material factory.
#
# Verifies:
#   • get_flat: identical params return the SAME cached instance.
#   • get_emis: identical params return the SAME cached instance.
#   • get_flat_mutable: returns a DIFFERENT object than get_flat.
#   • Different params return different objects.
#
# Run with:
#   godot --headless --quit-after 60 -s res://tests/smoke/shared_materials.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== shared_materials smoke test ===")
	call_deferred("_run")


func _run() -> void:
	var col_a: Color = Color(0.8, 0.2, 0.2)
	var col_b: Color = Color(0.2, 0.8, 0.2)
	var met: float = 0.1
	var rou: float = 0.5
	var energy: float = 1.5

	# (a) get_flat: same params → same object reference
	var flat1: StandardMaterial3D = SharedMaterials.get_flat(col_a, met, rou)
	var flat2: StandardMaterial3D = SharedMaterials.get_flat(col_a, met, rou)
	_expect(flat1 == flat2,
		"get_flat: identical params return the same instance")

	# (b) get_emis: same params → same object reference
	var emis1: StandardMaterial3D = SharedMaterials.get_emis(col_a, energy, met, rou)
	var emis2: StandardMaterial3D = SharedMaterials.get_emis(col_a, energy, met, rou)
	_expect(emis1 == emis2,
		"get_emis: identical params return the same instance")

	# (c) get_flat_mutable returns a DIFFERENT object than get_flat
	var flat_mut: StandardMaterial3D = SharedMaterials.get_flat_mutable(col_a, met, rou)
	_expect(flat_mut != flat1,
		"get_flat_mutable returns a different object than get_flat")

	# (d) different params return different objects
	var flat_other: StandardMaterial3D = SharedMaterials.get_flat(col_b, met, rou)
	_expect(flat_other != flat1,
		"get_flat: different params return different objects")

	var emis_other: StandardMaterial3D = SharedMaterials.get_emis(col_b, energy, met, rou)
	_expect(emis_other != emis1,
		"get_emis: different params return different objects")

	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("")
	print("=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)