extends SceneTree

# Phase A flow smoke test. Exercises GameState's mutators, room discovery,
# the F5 / F9 save round-trip, and verifies the autoload registry is intact.
# The Phase A loop is: arrive in gate room → read consoles → step through the
# exit archway → return. No kino, no breach, no quarters in this slice.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/e1_flow.gd

const EXPECTED_AUTOLOADS: Array[String] = [
	"Audio", "TestCapture", "GameState", "SceneRouter", "KinoRemote", "EpisodeWrap",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== phase-a flow smoke test ===")

	_verify_autoload_registry()

	var gs_script: Script = load("res://scripts/game_state.gd") as Script
	_expect(gs_script != null, "load GameState script")
	if gs_script == null:
		_report()
		return

	var gs: Node = Node.new()
	gs.set_script(gs_script)
	gs.name = "GameState"
	root.add_child(gs)

	gs.reset()
	_expect(gs.health == gs.MAX_HEALTH, "reset: health == MAX_HEALTH")
	_expect(gs.oxygen == gs.MAX_OXYGEN, "reset: oxygen == MAX_OXYGEN")
	_expect(gs.rooms_discovered.is_empty(), "reset: rooms cleared")
	_expect(gs.log_entries.is_empty(), "reset: log cleared")
	_expect(gs.episode_complete == false, "reset: episode not complete")

	gs.damage(35.0)
	_expect(gs.health == 65.0, "damage(35) drops health to 65")
	gs.heal_full()
	_expect(gs.health == gs.MAX_HEALTH, "heal_full restores to MAX_HEALTH")

	gs.consume_oxygen(20.0)
	_expect(gs.oxygen == 80.0, "consume_oxygen(20) drops to 80")
	gs.restore_oxygen(100.0)
	_expect(gs.oxygen == gs.MAX_OXYGEN, "restore_oxygen full caps at MAX")

	gs.discover_room("gate_room", "Gate Room")
	gs.discover_room("gate_room", "Gate Room")
	_expect(gs.rooms_discovered.size() == 1, "discover_room is idempotent")
	gs.discover_room("corridor", "Destiny Main Corridor")
	_expect(gs.rooms_discovered.size() == 2, "second room discovered")

	# Episode 1 / Air path: the old Rush + Kino + quarters + breach gate is now
	# only the prologue. Completion fires after the lime planet run repairs the
	# CO2 scrubber.
	var completed_emits: Array[bool] = []
	var on_done := func() -> void: completed_emits.append(true)
	gs.episode_completed.connect(on_done)

	_expect(gs.quest_step == gs.QUEST_TALK_SCOTT, "air: starts at Talk to Scott")
	gs.met_scott = true
	gs.advance_air_quest()
	_expect(gs.quest_step == gs.QUEST_FIND_RUSH, "air: Scott -> find Rush")

	_expect(not gs.met_rush, "air: Rush starts un-met")
	gs.met_rush = true
	gs.advance_air_quest()
	_expect(gs.quest_step == gs.QUEST_FIND_KINO, "air: Rush -> find Kino Remote in Eli's Quarters")

	_expect(not gs.kino_acquired, "mission: kino starts unacquired")
	gs.acquire_kino()
	_expect(gs.kino_acquired, "mission: acquire_kino sets flag")
	_expect(gs.quest_step == gs.QUEST_RESTORE_POWER, "air: Kino -> restore power at Engineering Bay")

	_expect(not gs.elevator_repaired, "air: elevator starts broken")
	gs.unlock_elevator()
	_expect(gs.elevator_repaired, "air: unlock_elevator sets flag")
	_expect(gs.quest_step == gs.QUEST_FIND_QUARTERS, "air: power restored -> find Crew Quarters Alpha")

	_expect(not gs.quarters_found, "air: quarters start unfound")
	gs.mark_quarters_found()
	_expect(gs.quarters_found, "air: mark_quarters_found sets flag")
	_expect(gs.prologue_complete, "air: Rush + Kino + power + quarters marks prologue complete")
	_expect(gs.quest_step == gs.QUEST_SLEEP, "air: prologue -> sleep")
	gs.check_episode_complete()
	_expect(not gs.episode_complete, "air: prologue does not complete episode")

	gs.start_air_crisis()
	_expect(gs.air_crisis_started, "air: sleep starts crisis")
	_expect(gs.quest_step == gs.QUEST_DIAGNOSE_LIFE_SUPPORT, "air: crisis -> diagnose life support")

	gs.diagnose_life_support()
	_expect(gs.life_support_diagnosed, "air: life support diagnostic records flag")
	_expect(gs.quest_step == gs.QUEST_SEAL_BREACH, "air: diagnostic -> seal breach")

	_expect(gs.breaches_sealed.is_empty(), "mission: no breaches sealed yet")
	gs.seal_breach("breach_a")
	_expect(gs.breaches_sealed.has("breach_a"), "mission: seal_breach records id")
	gs.seal_breach("breach_a")
	_expect(gs.breaches_sealed.size() == 1, "mission: seal_breach is idempotent")
	gs.check_episode_complete()
	_expect(not gs.episode_complete, "air: breach seal does not complete episode")
	_expect(gs.quest_step == gs.QUEST_FIND_SCRUBBER, "air: breach -> find scrubber")

	gs.diagnose_scrubber()
	_expect(gs.scrubber_diagnosed, "air: scrubber diagnosis records flag")
	_expect(gs.quest_step == gs.QUEST_WAIT_FTL, "air: scrubber diagnosis -> wait FTL")

	gs.trigger_ftl_drop()
	_expect(gs.ftl_drop_triggered, "air: FTL drop records flag")
	_expect(gs.quest_step == gs.QUEST_DIAL_LIME_PLANET, "air: FTL -> dial lime planet")

	gs.dial_lime_planet()
	_expect(gs.lime_planet_dialed, "air: lime planet dialed")
	_expect(gs.is_lime_gate_open(), "air: Stargate opens after lime dial")
	_expect(gs.quest_step == gs.QUEST_MINE_LIME, "air: dial -> mine lime")

	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "resources: lime starts at zero")
	gs.add_resource(gs.AIR_LIME_RESOURCE, 2, "test planet")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 2, "resources: add_resource accumulates")
	_expect(not gs.has_resource(gs.AIR_LIME_RESOURCE, gs.AIR_LIME_REQUIRED), "resources: 2 lime is below repair requirement")
	_expect(not gs.spend_resource(gs.AIR_LIME_RESOURCE, 3, "overdraft test"), "resources: overspend returns false")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 2, "resources: failed spend leaves lime unchanged")
	gs.add_resource(gs.AIR_LIME_RESOURCE, 1, "test planet")
	_expect(gs.has_resource(gs.AIR_LIME_RESOURCE, gs.AIR_LIME_REQUIRED), "resources: lime reaches repair requirement")
	_expect(gs.quest_step == gs.QUEST_RETURN_DESTINY, "air: enough lime -> return to Destiny")

	gs.return_from_lime_planet()
	_expect(gs.returned_from_lime_planet, "air: return from planet records flag")
	_expect(gs.quest_step == gs.QUEST_REPAIR_SCRUBBER, "air: return -> repair scrubber")
	_expect(not gs.episode_complete, "air: return with lime does not complete before repair")

	_expect(gs.repair_scrubber_with_lime(), "air: repair scrubber spends lime")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "resources: repair spends all required lime")
	_expect(not gs.spend_resource(gs.AIR_LIME_RESOURCE, 1, "post-repair overdraft"), "resources: lime cannot go negative")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "resources: lime remains zero after failed spend")
	_expect(gs.scrubber_repaired, "air: scrubber repaired flag set")
	_expect(gs.episode_complete, "air: scrubber repair completes Episode 1")
	_expect(gs.quest_step == gs.QUEST_COMPLETE, "air: quest step is complete")
	_expect(completed_emits.size() == 1, "mission: episode_completed emitted once")

	# Re-running check should not re-fire the signal.
	gs.check_episode_complete()
	_expect(completed_emits.size() == 1, "mission: completion is one-shot")

	# Reset before the save tests so they observe a clean slate.
	gs.episode_completed.disconnect(on_done)
	gs.reset()
	_expect(gs.episode_complete == false, "mission: reset clears completion")
	_expect(gs.kino_acquired == false, "mission: reset clears kino")
	_expect(gs.quarters_found == false, "mission: reset clears quarters")
	_expect(gs.elevator_repaired == false, "mission: reset clears elevator_repaired")
	_expect(gs.breaches_sealed.is_empty(), "mission: reset clears breaches")
	_expect(gs.met_scott == false, "mission: reset clears met_scott")
	_expect(gs.met_rush == false, "mission: reset clears met_rush")
	_expect(gs.quest_step == gs.QUEST_TALK_SCOTT, "mission: reset returns to first quest step")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "mission: reset clears resources")
	_expect(gs.air_crisis_started == false, "mission: reset clears air crisis")
	_expect(gs.scrubber_repaired == false, "mission: reset clears scrubber repair")

	# F5 quicksave path (no scene path set → save is refused, not silent failure).
	gs.current_scene_path = ""
	gs.save_game("", Vector3.ZERO, 0.0)
	# save_game with empty scene still writes — semantic check is current_scene_path
	# gating only inside _quicksave (the F5 handler). Direct save_game writes whatever.
	_expect(gs.has_save(), "save_game writes file regardless")
	gs.wipe_save()
	_expect(not gs.has_save(), "wipe_save removes file")

	# Round-trip a save with meaningful payload, then reset + reload via the
	# JSON parser path (load_and_resume schedules a scene change, so we call
	# the parser pieces directly here for the smoke test).
	gs.discover_room("gate_room", "Gate Room")
	gs.met_scott = true
	gs.advance_air_quest()
	gs.set_objective("Find a way off this ship")
	gs.add_log("Quicksave round-trip line")
	gs.add_resource(gs.AIR_LIME_RESOURCE, 2, "save test")
	gs.save_game("res://scenes/gate_room.tscn", Vector3(1.5, 1.05, 10.0), 0.5)
	_expect(gs.has_save(), "save_game writes payload")

	# Reset state and replay the read leg of load_and_resume's logic.
	gs.reset()
	_expect(gs.rooms_discovered.is_empty(), "post-reset: rooms cleared")
	var file: FileAccess = FileAccess.open(gs.SAVE_PATH, FileAccess.READ)
	_expect(file != null, "save file readable")
	if file != null:
		var raw: String = file.get_as_text()
		file.close()
		var parsed: Variant = JSON.parse_string(raw)
		_expect(parsed is Dictionary, "save parses to dictionary")
		if parsed is Dictionary:
			var data: Dictionary = parsed
			_expect(String(data.get("scene", "")) == "res://scenes/gate_room.tscn", "saved scene preserved")
			var pos: Array = data.get("pos", [])
			_expect(pos.size() == 3 and float(pos[0]) == 1.5, "saved position preserved")
			_expect(float(data.get("yaw", 0.0)) == 0.5, "saved yaw preserved")
			_expect(String(data.get("quest_step", "")) == gs.QUEST_FIND_RUSH, "saved quest step preserved")
			_expect(bool(data.get("met_scott", false)), "saved Scott quest flag preserved")
			var saved_resources: Dictionary = data.get("resources", {})
			_expect(int(saved_resources.get(gs.AIR_LIME_RESOURCE, 0)) == 2, "saved resources preserved")
			var log_arr: Array = data.get("log_entries", [])
			_expect(log_arr.size() >= 1, "saved log entries preserved")

	gs.wipe_save()
	_expect(not gs.has_save(), "post-test wipe cleared file")

	root.remove_child(gs)
	gs.free()

	_report()


func _verify_autoload_registry() -> void:
	var file := FileAccess.open("res://project.godot", FileAccess.READ)
	if file == null:
		_expect(false, "open project.godot")
		return
	var contents := file.get_as_text()
	file.close()
	for name in EXPECTED_AUTOLOADS:
		var pattern := "%s=\"*res://" % name
		_expect(contents.find(pattern) != -1, "autoload registered: " + name)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes, " / ", _passes + _failures.size())
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
