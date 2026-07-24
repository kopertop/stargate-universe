extends SceneTree

# Cast → Mixamo host keys (Eli / Swat / YBot / XBot).
# Run: godot --headless -s res://tests/smoke/mixamo_host_catalog.gd

var _passes: int = 0
var _fails: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== mixamo_host_catalog smoke ===")
	var Catalog: Script = load("res://scripts/mixamo_host_catalog.gd") as Script
	_check(Catalog != null, "load MixamoHostCatalog")
	if Catalog == null:
		_finish()
		return

	_expect_host(Catalog, "Eli", "eli")
	_expect_host(Catalog, "Lt Scott", "swat")
	_expect_host(Catalog, "Sgt Greer", "greer")
	_expect_host(Catalog, "Colonel Young", "swat")
	_expect_host(Catalog, "Soldier 2", "swat")
	_expect_host(Catalog, "Dr Rush", "ybot")
	_expect_host(Catalog, "Chloe Armstrong", "xbot")
	_expect_host(Catalog, "Dr Park", "xbot")
	_expect_host(Catalog, "Lt James", "xbot") # TJ — military female
	_expect_host(Catalog, "Camille Wray", "xbot")

	# Resolve must return an existing pack path when any combat GLB is present.
	var path: String = str(Catalog.call("resolve_glb_for", "Eli"))
	if path == "":
		print("  SKIP  no Mixamo combat packs on disk")
		_passes += 1
	else:
		_check(ResourceLoader.exists(path), "Eli resolves to existing pack: %s" % path)
		if ResourceLoader.exists("res://models/mixamo_openbot/Eli_rifle_combat.glb"):
			_check(path.contains("Eli_rifle_combat"), "Eli pack is Eli_rifle_combat.glb (%s)" % path)
		var greer: String = str(Catalog.call("resolve_glb_for", "Sgt Greer"))
		if ResourceLoader.exists("res://models/mixamo_openbot/Greer_rifle_combat.glb"):
			_check(greer.contains("Greer_rifle_combat"), "Greer pack is Greer_rifle_combat.glb (%s)" % greer)
		else:
			_check(greer.contains("Swat") or greer.contains("YBot"),
				"Greer falls back without Greer pack (%s)" % greer)
		var rush: String = str(Catalog.call("resolve_glb_for", "Dr Rush"))
		_check(rush.contains("YBot") or rush.contains("Swat") or rush.contains("Eli"),
			"Rush resolves male non-soldier pack (%s)" % rush)
		var chloe: String = str(Catalog.call("resolve_glb_for", "Chloe Armstrong"))
		if ResourceLoader.exists("res://models/mixamo_openbot/XBot_rifle_combat.glb"):
			_check(chloe.contains("XBot"), "Chloe resolves XBot when pack present (%s)" % chloe)
		else:
			_check(
				chloe.contains("YBot") or chloe.contains("Swat"),
				"Chloe falls back without XBot (%s)" % chloe
			)

	_finish()


func _expect_host(Catalog: Script, character: String, expected: String) -> void:
	var got: String = str(Catalog.call("host_key_for", character))
	_check(got == expected, "%s → %s (got %s)" % [character, expected, got])


func _check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_fails += 1
		print("  FAIL  %s" % label)


func _finish() -> void:
	print("=== mixamo_host_catalog: %d pass, %d fail ===" % [_passes, _fails])
	quit(0 if _fails == 0 else 1)
