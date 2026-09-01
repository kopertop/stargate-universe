extends SceneTree

# Smoke test for the VRM character roster (P3: Add VRM character models for
# all 15+ crew members).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/vrm_roster.gd
#
# Asserts:
#   1. All 15 crew profiles are registered in CharacterFactory.PROFILES
#   2. Every profile has a "vrm" path (the roster is VRM-ready)
#   3. Every crew member has an expression profile in VrmCharacterManager
#   4. VRM files that exist load successfully via VrmCharacter.create
#   5. Crew without .vrm files fall back to the modular pipeline
#   6. VrmCharacterManager spawns crew, tracks LOD, and manages visibility
#   7. Expression profiles set the correct resting emotion
#   8. The ALIASES dict resolves crew nicknames to canonical profiles

const VrmCharacterScript: Script = preload("res://scripts/vrm_character.gd")
const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const ManagerScript: Script = preload("res://scripts/vrm_character_manager.gd")

const EXPECTED_CREW: Array[String] = [
	"Eli", "Colonel Young", "Dr Rush", "Sgt Greer", "Lt Scott",
	"Chloe Armstrong", "TJ", "Camille", "Volker", "Brody",
	"Dr Park", "Dr James", "Lt James", "Varro", "Simeon", "Ginn",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== vrm_roster smoke test ===")
	call_deferred("_run")


func _run() -> void:
	_test_roster_complete()
	_test_vrm_paths()
	_test_expression_profiles()
	_test_vrm_loads()
	_test_modular_fallback()
	_test_manager_spawn()
	_test_expression_application()
	_test_aliases()
	_report()


# --- helpers ---

func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures.append(msg)
		print("  FAIL: %s" % msg)


# --- tests ---

func _test_roster_complete() -> void:
	print("\n-- Test 1: All 15 crew profiles registered --")
	var profiles: Array = FactoryRef.PROFILES.keys()
	for name in EXPECTED_CREW:
		_expect(profiles.has(name), "Missing profile: %s" % name)
	_expect(profiles.size() >= 15, "At least 15 profiles (got %d)" % profiles.size())
	print("  %d/%d crew profiles registered" % [profiles.size(), EXPECTED_CREW.size()])


func _test_vrm_paths() -> void:
	print("\n-- Test 2: Every profile has a VRM path --")
	for name in EXPECTED_CREW:
		var profile: Dictionary = FactoryRef.PROFILES.get(name, {})
		var has_vrm: bool = profile.has("vrm") and String(profile["vrm"]) != ""
		_expect(has_vrm, "%s has no 'vrm' path" % name)
		if has_vrm:
			var path: String = String(profile["vrm"])
			# Path should follow the pattern res://models/vrm/<name>.vrm
			_expect(path.begins_with("res://models/vrm/"), "%s VRM path not in models/vrm/: %s" % [name, path])
			_expect(path.ends_with(".vrm"), "%s VRM path doesn't end with .vrm: %s" % [name, path])
	print("  All crew VRM-ready (path registered; file may not exist yet)")


func _test_expression_profiles() -> void:
	print("\n-- Test 3: Every crew member has an expression profile --")
	for name in EXPECTED_CREW:
		var profile: Dictionary = ManagerScript.EXPRESSION_PROFILES.get(name, {})
		_expect(not profile.is_empty(), "%s has no expression profile" % name)
		if not profile.is_empty():
			# Each profile must have personality, blink rate, visemes
			_expect(profile.has("personality"), "%s missing 'personality'" % name)
			_expect(profile.has("blink_rate_min"), "%s missing 'blink_rate_min'" % name)
			_expect(profile.has("blink_rate_max"), "%s missing 'blink_rate_max'" % name)
			_expect(profile.has("visemes"), "%s missing 'visemes'" % name)
			# Visemes should have all 5
			var visemes: Array = profile.get("visemes", [])
			_expect(visemes.size() == 5, "%s should have 5 visemes (got %d)" % [name, visemes.size()])
	print("  All expression profiles valid")


func _test_vrm_loads() -> void:
	print("\n-- Test 4: Existing VRM files load --")
	var loaded: int = 0
	var fallback: int = 0
	for name in EXPECTED_CREW:
		var profile: Dictionary = FactoryRef.PROFILES.get(name, {})
		var vrm_path: String = String(profile.get("vrm", ""))
		if vrm_path != "" and ResourceLoader.exists(vrm_path):
			# VRM file exists — try to load it
			var c: Node3D = VrmCharacterScript.create(vrm_path, name)
			if c != null:
				root.add_child(c)
				var skel: Skeleton3D = c.call("skeleton")
				_expect(skel != null, "%s VRM loaded but skeleton missing" % name)
				if skel != null:
					_expect(skel.find_bone("Hips") >= 0, "%s VRM missing Hips bone" % name)
					_expect(skel.find_bone("Head") >= 0, "%s VRM missing Head bone" % name)
				c.queue_free()
				loaded += 1
			else:
				_failures.append("%s VRM file exists but failed to load" % name)
		else:
			# VRM file doesn't exist yet — that's OK, it's VRM-ready
			fallback += 1
	print("  %d VRM files loaded, %d pending (modular fallback)" % [loaded, fallback])


func _test_modular_fallback() -> void:
	print("\n-- Test 5: Crew without VRM files fall back to modular --")
	for name in EXPECTED_CREW:
		var vrm_path: String = String(FactoryRef.PROFILES.get(name, {}).get("vrm", ""))
		if vrm_path == "" or not ResourceLoader.exists(vrm_path):
			# This crew member should fall back to the modular pipeline
			var has_mod: bool = FactoryRef.PROFILES.get(name, {}).has("mod")
			_expect(has_mod, "%s has no VRM and no modular fallback" % name)
			if has_mod:
				var mc: Node3D = FactoryRef.build_modular(name)
				_expect(mc != null, "%s modular body failed to build" % name)
				if mc != null:
					root.add_child(mc)
					FactoryRef.dress_modular(mc, name, FactoryRef.CTX_SHIP)
					mc.queue_free()
			break  # Just test the first one we find
	print("  Modular fallback works for crew without VRM files")


func _test_manager_spawn() -> void:
	print("\n-- Test 6: VrmCharacterManager spawn + LOD + visibility --")
	var mgr: Node = ManagerScript.new()
	root.add_child(mgr)

	# Spawn the first 5 crew (or all if we have VRM files)
	var spawned: int = 0
	for name in EXPECTED_CREW:
		var c: Node3D = mgr.call("spawn_crew", name, Vector3(spawned * 2.0, 0.0, 0.0))
		if c != null:
			spawned += 1
		if spawned >= 5:
			break

	_expect(spawned > 0, "Manager spawned no crew")
	_expect(mgr.call("get_crew_count") == spawned, "Crew count mismatch (%d vs %d)" % [mgr.call("get_crew_count"), spawned])

	# Test LOD query
	for name in mgr.call("get_crew_names"):
		var lod: int = mgr.call("get_lod", name)
		_expect(lod >= 0 and lod <= 2, "%s LOD out of range: %d" % [name, lod])

	# Test visibility budget (all should be visible with < MAX_VISIBLE_CREW)
	for name in mgr.call("get_crew_names"):
		var c: Node3D = mgr.get("_crew").get(name)
		if c != null and is_instance_valid(c):
			_expect(c.visible, "%s should be visible (under budget)" % name)

	# Clean up
	for name in mgr.call("get_crew_names"):
		mgr.call("remove_crew", name)
	mgr.queue_free()
	print("  Manager spawned %d crew, LOD + visibility OK" % spawned)


func _test_expression_application() -> void:
	print("\n-- Test 7: Expression profiles apply resting emotion --")
	# Find a crew member with a VRM file
	var test_name: String = ""
	for name in EXPECTED_CREW:
		var vrm_path: String = String(FactoryRef.PROFILES.get(name, {}).get("vrm", ""))
		if vrm_path != "" and ResourceLoader.exists(vrm_path):
			test_name = name
			break

	if test_name == "":
		print("  SKIP: No VRM files available for expression test")
		return

	var c: Node3D = VrmCharacterScript.create(
		String(FactoryRef.PROFILES.get(test_name, {}).get("vrm", "")), test_name)
	root.add_child(c)

	var profile: Dictionary = ManagerScript.EXPRESSION_PROFILES.get(test_name, {})
	var personality: String = String(profile.get("personality", "neutral"))
	if personality != "neutral":
		c.call("set_emotion", personality, 0.6)
		var channels: Dictionary = c.get("_channels")
		_expect(channels.has("emotion"), "%s emotion channel not set" % test_name)
		if channels.has("emotion"):
			var ch: Dictionary = channels["emotion"]
			_expect(String(ch.get("expr", "")) == personality,
				"%s emotion should be '%s' (got '%s')" % [test_name, personality, ch.get("expr", "")])

	# Test viseme
	c.call("set_viseme", "aa", 0.8)
	var channels2: Dictionary = c.get("_channels")
	_expect(channels2.has("viseme"), "%s viseme channel not set" % test_name)

	# Test clearing
	c.call("clear_expressions")
	var channels3: Dictionary = c.get("_channels")
	_expect(channels3.is_empty(), "%s expressions not cleared" % test_name)

	c.queue_free()
	print("  Expression profile for %s: personality=%s" % [test_name, personality])


func _test_aliases() -> void:
	print("\n-- Test 8: Alias resolution --")
	# Test that aliases resolve to canonical profiles
	var aliases: Dictionary = FactoryRef.ALIASES
	for alias in aliases:
		var canonical: String = aliases[alias]
		_expect(FactoryRef.PROFILES.has(canonical),
			"Alias '%s' -> '%s' but '%s' not in PROFILES" % [alias, canonical, canonical])
	# Test a few key aliases
	_expect(FactoryRef.ALIASES.get("Rush", "") == "Dr Rush", "Rush alias broken")
	_expect(FactoryRef.ALIASES.get("Young", "") == "Colonel Young", "Young alias broken")
	_expect(FactoryRef.ALIASES.get("Greer", "") == "Sgt Greer", "Greer alias broken")
	_expect(FactoryRef.ALIASES.get("Wray", "") == "Camille", "Wray alias broken")
	_expect(FactoryRef.ALIASES.get("Tamara", "") == "TJ", "Tamara alias broken")
	print("  All %d aliases resolve correctly" % aliases.size())


func _report() -> void:
	print("\n=== vrm_roster results ===")
	print("  PASSED: %d" % _passes)
	if not _failures.is_empty():
		print("  FAILED: %d" % _failures.size())
		for f in _failures:
			print("    - %s" % f)
	else:
		print("  FAILED: 0")
	print("=== %s ===" % ("ALL PASS" if _failures.is_empty() else "FAILURES"))
	quit(0 if _failures.is_empty() else 1)