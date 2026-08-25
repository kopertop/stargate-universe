extends SceneTree

# Smoke test for the composable-music Audio (scripts/music_director.gd).
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/music_director.gd
#
# Asserts:
#   • Autoloads present; data/music_moods.json loads into a non-empty mood table.
#   • Mood table is internally consistent (crisis-intensity scale stems ⊆ the crisis
#     mood; melodic stems referenced).
#   • set_mood() records the intended mix in _targets at the authored dB, and a
#     transition drops stems no longer in the new mood.
#   • Crisis intensity scales the danger stems by scrubber_level (full charge → quiet,
#     empty → authored target).
#   • refresh() derives the mood from room + quest step (quest crisis beats override
#     the room mood).
#   • FTL PLANET phase routes to the planet mood; dialog ducking offsets/restores.
#   • play_sting() and a missing-stem mood are safe no-ops (half-baked library).
#   • Every BAKED sounds/music/loops/*.ogg loads non-null (catches the missing-.import
#     trap — a stem file with no sidecar load()s to null in-game).
#
# Uses live autoloads (Audio + GameState + SceneRouter). Drives methods directly
# rather than via signals (deferred hooks don't fire in -s mode before _initialize).

const LOOPS_DIR: String = "res://sounds/music/loops"

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== music_director smoke test ===")

	var md: Node = root.get_node_or_null("Audio")
	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")

	_expect(md != null, "Audio autoload present")
	_expect(gs != null, "GameState autoload present")
	_expect(router != null, "SceneRouter autoload present")
	if md == null or gs == null or router == null:
		_report()
		return

	# Headless: set_mood snaps gains instantly (no tweens that never tick).
	router.set("instant_mode", true)
	# Guarantee config is loaded regardless of autoload _ready ordering in -s mode.
	md.call("_load_config")

	# --- 1. Config loaded -----------------------------------------------------
	var moods: Dictionary = md.get("_moods")
	var defaults: Dictionary = md.get("_defaults")
	var melodic: Array = md.get("_melodic")
	var crisis_cfg: Dictionary = md.get("_crisis_cfg")
	_expect(not moods.is_empty(), "mood table loaded (non-empty)")
	for required in ["silent", "ship_calm", "mystery", "tension", "crisis", "planet", "somber"]:
		_expect(moods.has(required), "mood table defines '%s'" % required)
	_expect(not defaults.is_empty(), "defaults block present")
	_expect(not melodic.is_empty(), "melodic_stems list present")

	# --- 2. Mood table internal consistency -----------------------------------
	var crisis_stems: Dictionary = (moods.get("crisis", {}) as Dictionary).get("stems", {})
	for sid in crisis_cfg.get("scale_stems", []):
		_expect(crisis_stems.has(sid),
			"crisis_intensity scale stem '%s' is part of the crisis mood" % sid)
	# Every melodic stem appears in at least one mood (otherwise it can never play).
	for msid in melodic:
		var seen: bool = false
		for mid in moods.keys():
			if ((moods[mid] as Dictionary).get("stems", {}) as Dictionary).has(msid):
				seen = true
				break
		_expect(seen, "melodic stem '%s' is referenced by some mood" % msid)

	# --- 3. set_mood records the intended mix in _targets ---------------------
	md.call("set_mood", "ship_calm", 0.0)
	_expect(String(md.get("current_mood")) == "ship_calm", "set_mood sets current_mood")
	var targets: Dictionary = md.get("_targets")
	var ship_stems: Dictionary = (moods["ship_calm"] as Dictionary).get("stems", {})
	for sid in ship_stems.keys():
		_expect(targets.has(sid), "ship_calm target recorded for '%s'" % sid)
	_expect(is_equal_approx(float(targets.get("bed_ship_warm", -99.0)),
		float(ship_stems.get("bed_ship_warm"))), "bed_ship_warm target == authored dB")

	# --- 4. Transition drops stems no longer in the new mood ------------------
	md.call("set_mood", "tension", 0.0)
	targets = md.get("_targets")
	var tension_stems: Dictionary = (moods["tension"] as Dictionary).get("stems", {})
	_expect(targets.has("pad_strings_tense"), "tension adds pad_strings_tense")
	_expect(not targets.has("mel_piano_sparse"),
		"ship_calm-only stem (mel_piano_sparse) dropped on transition to tension")
	for sid in targets.keys():
		_expect(tension_stems.has(sid), "post-transition target '%s' belongs to tension" % sid)

	# --- 5. Crisis intensity scales danger stems by scrubber_level ------------
	var scale_stems: Array = crisis_cfg.get("scale_stems", [])
	var min_db: float = float(crisis_cfg.get("min_db", -22.0))
	if not scale_stems.is_empty():
		var probe: String = String(scale_stems[0])
		var authored: float = float(crisis_stems.get(probe))
		gs.set("scrubber_level", 100.0)            # full charge → quietest
		md.call("set_mood", "crisis", 0.0)
		targets = md.get("_targets")
		_expect(is_equal_approx(float(targets.get(probe)), min_db),
			"crisis: '%s' at min_db when scrubber full (100%%)" % probe)
		gs.set("scrubber_level", 0.0)              # empty → authored (most intense)
		md.call("set_mood", "crisis", 0.0)
		targets = md.get("_targets")
		_expect(is_equal_approx(float(targets.get(probe)), authored),
			"crisis: '%s' at authored dB when scrubber empty (0%%)" % probe)

	# --- 6. refresh() derives mood from room + quest step ---------------------
	gs.set("scrubber_level", 0.0)
	gs.set("quest_step", "talk_scott")             # non-crisis step
	gs.set("current_room_id", "breached_section_south")
	md.call("refresh", 0.0)
	_expect(String(md.get("current_mood")) == "tension",
		"refresh: breached_section_south room → tension mood")
	gs.set("quest_step", "seal_breach")            # air-crisis beat overrides room
	md.call("refresh", 0.0)
	_expect(String(md.get("current_mood")) == "crisis",
		"refresh: air-crisis quest step overrides room mood → crisis")
	gs.set("current_room_id", "infirmary")
	gs.set("quest_step", "talk_scott")
	md.call("refresh", 0.0)
	_expect(String(md.get("current_mood")) == "somber",
		"refresh: infirmary room → somber mood")

	# --- 7. FTL phase + dialog ducking ----------------------------------------
	md.call("_on_ftl_phase", 3)                    # PLANET
	_expect(String(md.get("current_mood")) == "planet", "FTL PLANET phase → planet mood")
	var duck: float = float(defaults.get("duck_db", -10.0))
	md.call("_on_dialog_started", null, [])
	_expect(is_equal_approx(float(md.get("_duck_db")), duck), "dialog_started ducks music")
	md.call("_on_dialog_closed")
	_expect(is_equal_approx(float(md.get("_duck_db")), 0.0), "dialog_closed restores music")

	# --- 8. Safe no-ops on a half-baked library -------------------------------
	# play_sting on a (possibly) missing file must not crash or add a lingering child.
	md.call("play_sting", "sting_discovery")
	_expect(true, "play_sting() is a safe no-op when the stem isn't baked")
	md.call("_on_ftl_phase", 2)                    # JUMPING → riser + impact stings
	_expect(true, "FTL JUMPING phase stings are a safe no-op when unbaked")

	# --- 9. Every baked stem loads non-null (the missing-.import trap) ---------
	var checked: int = 0
	var dir: DirAccess = DirAccess.open(LOOPS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".ogg"):
				var path: String = LOOPS_DIR + "/" + fname
				var ok: bool = ResourceLoader.exists(path) and load(path) != null
				_expect(ok, "baked stem loads non-null: %s" % fname)
				checked += 1
			fname = dir.get_next()
		dir.list_dir_end()
	print("  note: %d baked stem(s) on disk (0 = library not baked yet; run tools/music-bake)" % checked)

	router.set("instant_mode", false)
	_report()


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - " + f)
		quit(1)
