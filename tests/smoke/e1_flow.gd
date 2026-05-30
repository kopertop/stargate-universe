extends SceneTree

# Phase A flow smoke test. Exercises GameState's mutators, room discovery,
# the F5 / F9 save round-trip, and verifies the autoload registry is intact.
# The Phase A loop is: arrive in gate room → read consoles → step through the
# exit archway → return. No kino, no breach, no quarters in this slice.
#
# Run with:
#   godot --headless --quit-after 80 -s res://tests/smoke/e1_flow.gd

const EXPECTED_AUTOLOADS: Array[String] = [
	"Audio", "TestCapture", "SaveManager", "GameClock", "GameState", "QuestLog",
	"NPCState", "SceneRouter", "KinoRemote", "EpisodeWrap",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== phase-a flow smoke test ===")

	_verify_autoload_registry()

	# Post-#36: tests use the LIVE autoloads (GameState + QuestLog) rather
	# than spinning up duplicates. In `-s` SceneTree mode autoloads ARE
	# attached to root, so a same-named test-instantiated node would clash
	# and Godot would auto-rename it to "@Node@2" — leaving QuestLog's
	# predicate evaluator reading from the autoload's untouched GameState
	# while the test mutated a different orphan instance. Cleaner to just
	# reset() the autoload between phases.
	_expect(load("res://scripts/game_state.gd") != null, "load GameState script")
	_expect(load("res://scripts/quest_log.gd") != null, "load QuestLog script")
	var gs: Node = root.get_node_or_null("GameState")
	_expect(gs != null, "GameState autoload is attached")
	if gs == null:
		_report()
		return

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
	_expect(gs.quest_step == gs.QUEST_FIND_REST, "air: Rush dismisses Eli -> find a place to rest")

	_expect(not gs.eli_quarters_visited, "air: Eli's quarters start un-visited")
	gs.mark_eli_quarters_found()
	_expect(gs.eli_quarters_visited, "air: mark_eli_quarters_found flips the flag")
	_expect(gs.quest_step == gs.QUEST_FIND_KINO, "air: in quarters -> inspect strange device")

	_expect(not gs.kino_acquired, "mission: kino starts unacquired")
	gs.acquire_kino()
	_expect(gs.kino_acquired, "mission: acquire_kino sets flag")
	_expect(gs.prologue_complete, "air: Rush + quarters + device marks prologue complete")
	_expect(gs.quest_step == gs.QUEST_SLEEP, "air: device inspected -> sleep")
	gs.check_episode_complete()
	_expect(not gs.episode_complete, "air: prologue does not complete episode")

	# Optional prologue flags — still mutable for save compatibility but not on
	# the critical quest path.
	_expect(not gs.elevator_repaired, "air: elevator starts broken")
	gs.unlock_elevator()
	_expect(gs.elevator_repaired, "air: unlock_elevator sets flag")
	_expect(not gs.quarters_found, "air: Crew Quarters Alpha start unfound")
	gs.mark_quarters_found()
	_expect(gs.quarters_found, "air: mark_quarters_found sets flag")

	# Door-traversal state — drives the Kino map's pip dim-on-traverse.
	_expect(gs.doors_traversed.is_empty(), "doors: traversed set starts empty")
	_expect(gs.door_key("a", "b") == gs.door_key("b", "a"), "doors: door_key is direction-agnostic")
	gs.mark_door_traversed("gate_room", "east_corridor")
	_expect(gs.door_was_traversed("gate_room", "east_corridor"), "doors: mark_door_traversed records key")
	_expect(gs.door_was_traversed("east_corridor", "gate_room"), "doors: traversal lookup symmetric")
	gs.mark_door_traversed("gate_room", "east_corridor")
	_expect(gs.doors_traversed.size() == 1, "doors: mark_door_traversed is idempotent")

	gs.start_air_crisis()
	_expect(gs.air_crisis_started, "air: sleep starts crisis")
	_expect(gs.quest_step == gs.QUEST_RETURN_TO_CONTROL, "air: crisis -> return to control room")

	gs.mark_control_room_returned()
	_expect(gs.control_room_returned, "air: control room return records flag")
	_expect(gs.quest_step == gs.QUEST_DIAGNOSE_LIFE_SUPPORT, "air: returned -> access terminal")
	_expect(not gs.blocked_door_beat_done, "air: blocked-door beat not yet played")

	gs.diagnose_life_support()
	_expect(gs.life_support_diagnosed, "air: life support diagnostic records flag")
	_expect(gs.quest_step == gs.QUEST_SEAL_BREACH, "air: terminal access -> seal breach")

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
	_expect(gs.quest_step == gs.QUEST_GO_TO_GATE, "air: FTL -> get to gate room")

	gs.report_to_gate()
	_expect(gs.reported_to_gate, "air: reporting to gate records flag")
	_expect(gs.quest_step == gs.QUEST_FETCH_KINO, "air: gate room -> fetch a Kino (scout first)")

	# Kino-scout beat: pull an orb from the quarters dispenser. Supply is
	# unlimited but the player caps at KINO_ORB_MAX.
	gs.acquire_kino_orb()
	_expect(gs.kino_orbs == 1, "air: dispenser grants a Kino orb")
	_expect(gs.quest_step == gs.QUEST_SCOUT_KINO, "air: holding a Kino -> send it through the gate")
	gs.acquire_kino_orb()
	gs.acquire_kino_orb()
	gs.acquire_kino_orb()
	_expect(gs.kino_orbs == gs.KINO_ORB_MAX, "air: Kino orbs cap at KINO_ORB_MAX")

	# Launching a Kino spends one orb; the recon flight confirms the far side.
	_expect(gs.consume_kino_orb(), "air: launching a Kino spends an orb")
	_expect(gs.kino_orbs == gs.KINO_ORB_MAX - 1, "air: consume_kino_orb decrements")
	gs.complete_kino_scout()
	_expect(gs.kino_scout_done, "air: Kino scout records flag")
	_expect(gs.quest_step == gs.QUEST_DIAL_LIME_PLANET, "air: scout done -> dial lime planet")

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

	# Deployed-Kino tracking: FIFO capped at KINO_DEPLOYED_MAX, oldest dropped.
	gs.deployed_kinos.clear()
	gs.deploy_kino("res://scenes/planet.tscn", Vector3(1, 0, 1))
	gs.deploy_kino("res://scenes/gate_room.tscn", Vector3(2, 0, 2))
	gs.deploy_kino("res://scenes/planet.tscn", Vector3(3, 0, 3))
	_expect(gs.deployed_kinos.size() == 3, "kino: tracks up to KINO_DEPLOYED_MAX deployments")
	gs.deploy_kino("res://scenes/planet.tscn", Vector3(4, 0, 4))
	_expect(gs.deployed_kinos.size() == gs.KINO_DEPLOYED_MAX, "kino: deploying a 4th stays capped at 3")
	_expect(float((gs.deployed_kinos[0] as Dictionary).get("x", -1.0)) == 2.0, "kino: oldest deployment dropped (FIFO pop_front)")
	_expect(gs.deployed_kinos_in_scene("res://scenes/planet.tscn").size() == 2, "kino: deployed_kinos_in_scene filters by scene")

	# Reset before the save tests so they observe a clean slate.
	gs.episode_completed.disconnect(on_done)
	gs.reset()
	_expect(gs.episode_complete == false, "mission: reset clears completion")
	_expect(gs.kino_acquired == false, "mission: reset clears kino")
	_expect(gs.quarters_found == false, "mission: reset clears quarters")
	_expect(gs.eli_quarters_visited == false, "mission: reset clears eli_quarters_visited")
	_expect(gs.elevator_repaired == false, "mission: reset clears elevator_repaired")
	_expect(gs.doors_traversed.is_empty(), "mission: reset clears doors_traversed")
	_expect(gs.kino_orbs == 0, "mission: reset clears kino_orbs")
	_expect(gs.deployed_kinos.is_empty(), "mission: reset clears deployed_kinos")
	_expect(gs.kino_scout_done == false, "mission: reset clears kino_scout_done")
	_expect(gs.kino_plan_approved == false, "mission: reset clears kino_plan_approved")
	_expect(gs.away_party_briefed == false, "mission: reset clears away_party_briefed")
	_expect(gs.kino_return_position == null, "mission: reset clears kino_return_position")
	_expect(gs.breaches_sealed.is_empty(), "mission: reset clears breaches")
	_expect(gs.met_scott == false, "mission: reset clears met_scott")
	_expect(gs.met_rush == false, "mission: reset clears met_rush")
	_expect(gs.quest_step == gs.QUEST_TALK_SCOTT, "mission: reset returns to first quest step")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "mission: reset clears resources")
	_expect(gs.air_crisis_started == false, "mission: reset clears air crisis")
	_expect(gs.scrubber_repaired == false, "mission: reset clears scrubber repair")

	# Serialize / deserialize round-trip via the new ISaveableSystem
	# contract. File I/O has moved to SaveManager; this exercises only
	# GameState's serialize/deserialize methods (no autoloads needed).
	gs.discover_room("gate_room", "Gate Room")
	gs.met_scott = true
	gs.advance_air_quest()
	gs.set_objective("Find a way off this ship")
	gs.add_log("Round-trip log line")
	gs.add_resource(gs.AIR_LIME_RESOURCE, 2, "save test")
	gs.kino_pan_x = 12.5
	gs.kino_pan_y = -8.0
	gs.kino_zoom = 1.7
	gs.kino_active_floor = 1
	gs.kino_marker = {"floor": 0, "world_x": 100.0, "world_y": 200.0}
	gs.kino_orbs = 2
	gs.kino_scout_done = true
	gs.kino_plan_approved = true
	gs.away_party_briefed = true
	gs.deployed_kinos = [{"scene": "res://scenes/planet.tscn", "x": 5.0, "y": 0.0, "z": -3.0}]

	var snapshot: Dictionary = gs.serialize()
	_expect(int(snapshot.get("kino_orbs", -1)) == 2, "serialize captures kino_orbs")
	_expect(snapshot.get("kino_scout_done", false) == true, "serialize captures kino_scout_done")
	_expect(snapshot.get("away_party_briefed", false) == true, "serialize captures away_party_briefed")
	_expect(snapshot.has("quest_step"), "serialize() includes quest_step")
	_expect(String(snapshot.get("quest_step", "")) == gs.QUEST_FIND_RUSH, "serialize captures current quest step")
	_expect(snapshot.get("met_scott", false) == true, "serialize captures met_scott")
	_expect(int((snapshot.get("resources", {}) as Dictionary).get(gs.AIR_LIME_RESOURCE, 0)) == 2, "serialize captures resources")
	_expect(float(snapshot.get("kino_pan_x", 0.0)) == 12.5, "serialize captures kino_pan_x")
	_expect(float(snapshot.get("kino_zoom", 0.0)) == 1.7, "serialize captures kino_zoom")
	_expect(snapshot.get("kino_marker", {}) is Dictionary, "serialize captures kino_marker dict")

	gs.reset()
	_expect(gs.rooms_discovered.is_empty(), "post-reset: rooms cleared")
	_expect(gs.kino_pan_x == 0.0 and gs.kino_zoom == 1.0, "reset: kino UI fields restored to defaults")
	_expect(gs.kino_marker.is_empty(), "reset: kino marker cleared")

	gs.deserialize(snapshot, 2)
	_expect(gs.met_scott, "deserialize restores met_scott")
	_expect(gs.kino_orbs == 2, "deserialize restores kino_orbs")
	_expect(gs.deployed_kinos.size() == 1 and float((gs.deployed_kinos[0] as Dictionary).get("x", -1.0)) == 5.0, "deserialize restores deployed_kinos")
	_expect(gs.kino_scout_done, "deserialize restores kino_scout_done")
	_expect(gs.away_party_briefed, "deserialize restores away_party_briefed")
	_expect(gs.quest_step == gs.QUEST_FIND_RUSH, "deserialize restores quest_step")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 2, "deserialize restores resources")
	_expect(gs.rooms_discovered.size() == 1, "deserialize restores rooms_discovered")
	_expect(gs.log_entries.size() >= 1, "deserialize restores log_entries")
	_expect(gs.kino_pan_x == 12.5, "deserialize restores kino_pan_x")
	_expect(gs.kino_zoom == 1.7, "deserialize restores kino_zoom")
	_expect(int((gs.kino_marker as Dictionary).get("floor", -1)) == 0, "deserialize restores kino_marker.floor")

	# --- Phase F: discovered-lime tracking (compass fog-of-war) --------------
	gs.discover_lime("LimeNode1")
	gs.discover_lime("LimeNode1")
	_expect(gs.lime_discovered.size() == 1, "discover_lime is idempotent")
	_expect(gs.is_lime_discovered("LimeNode1"), "is_lime_discovered true after discover")
	_expect(not gs.is_lime_discovered("LimeNode9"), "undiscovered lime reads false")
	gs.discover_lime("")
	_expect(gs.lime_discovered.size() == 1, "discover_lime ignores empty key")
	var lime_snapshot: Dictionary = gs.serialize()
	_expect((lime_snapshot.get("lime_discovered", []) as Array).has("LimeNode1"),
		"serialize captures lime_discovered")
	gs.reset()
	_expect(gs.lime_discovered.is_empty(), "reset clears lime_discovered")
	gs.deserialize(lime_snapshot, 1)
	_expect(gs.is_lime_discovered("LimeNode1"), "deserialize restores lime_discovered")

	# --- Phase G: ongoing scrubber resource loop ------------------------------
	# Force the loop's preconditions (skip the full repair flow — tested above).
	gs.scrubber_diagnosed = true
	gs.scrubber_repaired = true
	gs.scrubber_level = 100.0
	gs.resources[gs.AIR_LIME_RESOURCE] = 0
	# Tick one minute of simulated decay. Manually call the tick (so the
	# autoload SceneRouter check is bypassed) — we already trust _process is the
	# wrapper.
	var pre_level: float = gs.scrubber_level
	gs.call("_tick_scrubber", 60.0)
	_expect(gs.scrubber_level < pre_level, "scrubber_level decays under repair")
	_expect(gs.scrubber_level > 0.0, "decay is gradual, not instant")

	# Top-up without lime fails cleanly.
	_expect(not gs.top_up_scrubber(), "top_up_scrubber fails without lime")
	# Drop the level well below full so the +33% top-up isn't capped at 100.
	gs.scrubber_level = 20.0
	gs.add_resource(gs.AIR_LIME_RESOURCE, 1, "test")
	var pre_top: float = gs.scrubber_level
	_expect(gs.top_up_scrubber(), "top_up_scrubber returns true with lime")
	_expect(gs.scrubber_level > pre_top + 30.0, "top-up adds ~33% per lime")
	_expect(gs.resource_count(gs.AIR_LIME_RESOURCE) == 0, "top-up spends the lime")

	# Drain past the warn threshold so the warn latch fires exactly once.
	gs.scrubber_level = 40.0
	gs.set("_scrubber_warned", false)
	gs.call("_tick_scrubber", 60.0 * 30.0)   # well past the 33% crossing
	_expect(gs.scrubber_level <= gs.SCRUBBER_WARN_PERCENT, "decay crosses warn threshold")
	_expect(gs.get("_scrubber_warned") == true, "warn latch fires on threshold")

	# At zero the critical latch fires + oxygen starts bleeding.
	gs.scrubber_level = 0.0
	gs.set("_scrubber_critical", false)
	gs.oxygen = gs.MAX_OXYGEN
	gs.call("_tick_scrubber", 60.0)
	_expect(gs.get("_scrubber_critical") == true, "critical latch fires when scrubber drops to 0")
	_expect(gs.oxygen < gs.MAX_OXYGEN, "empty scrubber bleeds oxygen (slow E1-forgiving rate)")

	# --- Phase F: away-team companion (follow + mine + rush) -----------------
	# Duck-typed load so we don't depend on the `Companion` class_name being
	# registered in this same headless run (see godot class_name gotcha).
	var comp_script: Script = load("res://scripts/companion.gd") as Script
	_expect(comp_script != null, "load Companion script")
	if comp_script != null:
		var comp: Node = comp_script.new()
		root.add_child(comp)
		# Pass a non-existent model path so the body-build skips the GLB load; we
		# only care about group membership + the cutscene API here.
		comp.call("setup", "Test", "res://nonexistent.glb", 0)
		_expect(comp.is_in_group("away_team"), "companion joins away_team (cutscene muster)")
		_expect(comp.is_in_group("companion"), "companion joins companion group (compass)")
		_expect(comp.has_method("rush_to"), "companion exposes rush_to for the cutscene")
		comp.call("rush_to", Vector3(5.0, 0.0, 5.0))
		_expect(comp.get("_rushing") == true, "rush_to arms the cutscene sprint")
		root.remove_child(comp)
		comp.free()

	# --- Lime objective live-counter text (top-left objective on the planet) ---
	# planet.gd swaps the static "Step through the Stargate…" line for this
	# counter while the player is mining; the strings are asserted here so a
	# future refactor can't silently break the HUD copy + a save-game would
	# round-trip the same characters.
	_expect(gs.lime_objective_text(0, 3) == "Collect at least 3 lime deposits — 0/3",
		"lime_objective_text: zero progress")
	_expect(gs.lime_objective_text(2, 3) == "Collect at least 3 lime deposits — 2/3",
		"lime_objective_text: partial progress")
	_expect(gs.lime_objective_text(3, 3) == "Lime collected — 3/3  ✓  head back to the gate",
		"lime_objective_text: completion flips copy")
	_expect(gs.lime_objective_text(5, 3) == "Lime collected — 5/3  ✓  head back to the gate",
		"lime_objective_text: over-cap still reads completion")

	# --- Resource-node fog-of-war: DISCOVER_RANGE was 30m, bumped to 50m so the
	# player can spot a deposit without having to walk right on top of it.
	# Asserting the constant directly catches accidental regressions in either
	# direction (too generous → no exploration; too tight → user can't find lime).
	var rn_script: Script = load("res://scripts/resource_node.gd") as Script
	_expect(rn_script != null, "load resource_node script")
	if rn_script != null:
		var consts: Dictionary = rn_script.get_script_constant_map()
		_expect(float(consts.get("DISCOVER_RANGE", 0.0)) == 50.0,
			"resource_node DISCOVER_RANGE is 50m")

	# Don't free the autoload — Godot tears it down with the SceneTree.
	# Reset its state so any test that re-uses this process later sees a
	# clean GameState (irrelevant for the runner, kind to debuggers).
	gs.reset()

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
