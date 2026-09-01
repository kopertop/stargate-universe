extends SceneTree

# Smoke test for the E2 Light planetary mission squad mechanics.
#
# Verifies:
#   1. SquadCommand autoload: command state machine (hold/advance/cover_fire).
#   2. SquadCommand waypoint: set/clear/has + signal emission.
#   3. SquadCommand serialize/deserialize round-trip.
#   4. SquadCommand reset() clears all state.
#   5. Companion squad_responsive: HOLD stops movement, ADVANCE follows.
#   6. Companion ADVANCE-to-waypoint: moves toward set waypoint, stops on arrive.
#   7. Companion COVER_FIRE: holds position, faces nearest hostile.
#   8. Peeled-off companions ignore squad commands (E1 backward-compat).
#   9. CompanionCommentary: loads data, emits lines via GameState.say().
#  10. Planetary mission quest chain: quests.json has the 6-step chain.
#  11. QuestLog predicate advance: deploy_squad → find_resources → ...
#  12. GameState serialize/deserialize for E2 mission flags.
#  13. data/planetary_missions.json has valid mission objectives.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/squad_mission.gd

const COMPANION_SCRIPT_PATH: String = "res://scripts/companion.gd"
const SQUAD_COMMAND_PATH: String = "res://scripts/squad_command.gd"
const COMMENTARY_SCRIPT_PATH: String = "res://scripts/companion_commentary.gd"
const PLANETARY_MISSIONS_PATH: String = "res://data/planetary_missions.json"
const QUESTS_PATH: String = "res://data/quests.json"

const EXPECTED_MISSION_STEPS: Array[String] = [
	"deploy_squad",
	"find_resources",
	"investigate_ruins",
	"retrieve_ancient_tech",
	"return_through_gate",
	"mission_complete",
]

const EXPECTED_OBJECTIVES: Array[String] = [
	"find_resources",
	"investigate_ruins",
	"retrieve_ancient_tech",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== squad_mission smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var ql: Node = root.get_node_or_null("QuestLog")
	var sc: Node = root.get_node_or_null("SquadCommand")
	_expect(gs != null, "GameState autoload attached")
	_expect(ql != null, "QuestLog autoload attached")
	_expect(sc != null, "SquadCommand autoload attached")
	if gs == null or ql == null or sc == null:
		_report()
		return

	# Save isolation.
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	if save_mgr != null:
		save_mgr.call("configure_test_paths", "squad_mission")

	# --- 1. SquadCommand command state machine ---
	print("\n--- SquadCommand state machine ---")
	gs.call("reset")
	sc.call("reset")
	_expect(String(sc.call("get_command")) == "advance",
		"default command is advance (got %s)" % String(sc.call("get_command")))

	sc.call("set_command", "hold")
	_expect(String(sc.call("get_command")) == "hold",
		"set_command('hold') → get_command() == hold")

	sc.call("set_command", "advance")
	_expect(String(sc.call("get_command")) == "advance",
		"set_command('advance') → get_command() == advance")

	sc.call("set_command", "cover_fire")
	_expect(String(sc.call("get_command")) == "cover_fire",
		"set_command('cover_fire') → get_command() == cover_fire")

	# Idempotency: setting the same command is a no-op (no signal).
	var signal_count: Array[int] = [0]
	var on_cmd_changed: Callable = func(_cmd: String) -> void: signal_count[0] += 1
	if sc.has_signal("command_changed"):
		sc.connect("command_changed", on_cmd_changed)
	sc.call("set_command", "cover_fire")  # same → no signal
	_expect(signal_count[0] == 0, "set_command same value is no-op (no signal)")
	if sc.is_connected("command_changed", on_cmd_changed):
		sc.disconnect("command_changed", on_cmd_changed)

	# --- 2. SquadCommand waypoint ---
	print("\n--- SquadCommand waypoint ---")
	_expect(sc.call("has_waypoint") == false, "no waypoint by default")
	sc.call("set_waypoint", Vector3(10.0, 0.0, 20.0))
	_expect(sc.call("has_waypoint") == true, "waypoint set after set_waypoint")
	var wp: Vector3 = sc.call("get_waypoint")
	_expect(wp == Vector3(10.0, 0.0, 20.0),
		"get_waypoint returns set position (got %s)" % str(wp))
	sc.call("clear_waypoint")
	_expect(sc.call("has_waypoint") == false, "waypoint cleared after clear_waypoint")

	# --- 3. SquadCommand serialize/deserialize ---
	print("\n--- SquadCommand serialize/deserialize ---")
	sc.call("reset")
	sc.call("set_command", "hold")
	sc.call("set_waypoint", Vector3(5.0, 0.0, -3.0))
	sc.call("set_mission_id", "e2_light_planet")
	var snap: Dictionary = sc.call("serialize")
	_expect(String(snap.get("command", "")) == "hold", "serialize command == hold")
	_expect(snap.get("waypoint_set", false) == true, "serialize waypoint_set == true")
	_expect(String(snap.get("mission_id", "")) == "e2_light_planet", "serialize mission_id")
	sc.call("reset")
	_expect(String(sc.call("get_command")) == "advance", "reset → advance")
	sc.call("deserialize", snap)
	_expect(String(sc.call("get_command")) == "hold", "deserialize restores hold")
	_expect(sc.call("has_waypoint") == true, "deserialize restores waypoint")
	_expect(String(sc.call("get_mission_id")) == "e2_light_planet", "deserialize restores mission_id")

	# --- 4. SquadCommand reset ---
	print("\n--- SquadCommand reset ---")
	sc.call("set_command", "cover_fire")
	sc.call("set_waypoint", Vector3(1.0, 2.0, 3.0))
	sc.call("set_mission_id", "test_mission")
	sc.call("reset")
	_expect(String(sc.call("get_command")) == "advance", "reset → command advance")
	_expect(sc.call("has_waypoint") == false, "reset → no waypoint")
	_expect(String(sc.call("get_mission_id")) == "", "reset → empty mission_id")

	# --- 5. Companion squad_responsive: HOLD stops movement ---
	print("\n--- Companion HOLD command ---")
	await _test_companion_hold(gs, sc)

	# --- 6. Companion ADVANCE-to-waypoint ---
	print("\n--- Companion ADVANCE to waypoint ---")
	await _test_companion_advance_waypoint(gs, sc)

	# --- 7. Companion COVER_FIRE ---
	print("\n--- Companion COVER_FIRE ---")
	await _test_companion_cover_fire(gs, sc)

	# --- 8. Peeled-off companions ignore squad commands ---
	print("\n--- Peeled-off ignores squad commands ---")
	await _test_peeled_off_ignores_squad(gs, sc)

	# --- 9. CompanionCommentary ---
	print("\n--- CompanionCommentary ---")
	_test_commentary(gs)

	# --- 10. Quest chain in quests.json ---
	print("\n--- Planetary mission quest chain ---")
	_test_quest_chain(ql)

	# --- 11. QuestLog predicate advance ---
	print("\n--- QuestLog predicate advance ---")
	_test_quest_predicates(gs, ql)

	# --- 12. GameState serialize/deserialize E2 mission flags ---
	print("\n--- GameState E2 mission flags ---")
	_test_gamestate_serialize(gs)

	# --- 13. planetary_missions.json ---
	print("\n--- planetary_missions.json ---")
	_test_planetary_missions_data()

	# Final cleanup
	gs.call("reset")
	sc.call("reset")
	_report()


# ── 5: Companion HOLD stops movement ─────────────────────────────────────────
func _test_companion_hold(gs: Node, sc: Node) -> void:
	sc.call("reset")
	gs.call("reset")
	var player: Node3D = await _make_player(Vector3(0.0, 0.0, 0.0))
	var c: Node3D = await _make_companion("TestHold", Vector3(2.0, 0.0, 0.0), 0)
	await process_frame

	# Set HOLD command — companion should not move even when player moves away.
	sc.call("set_command", "hold")
	var pos_before: Vector3 = c.global_position
	player.global_position = Vector3(0.0, 0.0, -20.0)
	for _i in 30:
		await process_frame
	var moved: float = Vector2(c.global_position.x - pos_before.x, c.global_position.z - pos_before.z).length()
	_expect(moved < 0.05, "HOLD: companion did not move (moved %.4f m)" % moved)
	_cleanup_nodes([c, player])


# ── 6: Companion ADVANCE to waypoint ─────────────────────────────────────────
func _test_companion_advance_waypoint(gs: Node, sc: Node) -> void:
	sc.call("reset")
	gs.call("reset")
	var player: Node3D = await _make_player(Vector3(0.0, 0.0, 0.0))
	var c: Node3D = await _make_companion("TestAdvance", Vector3(0.0, 0.0, 0.0), 0)
	await process_frame

	# Set ADVANCE with a waypoint — companion should move toward it.
	sc.call("set_command", "advance")
	sc.call("set_waypoint", Vector3(15.0, 0.0, 0.0))
	var pos_before: Vector3 = c.global_position
	for _i in 60:
		await process_frame
	var dist_after: float = Vector2(c.global_position.x - 15.0, c.global_position.z).length()
	var dist_before: float = Vector2(pos_before.x - 15.0, pos_before.z).length()
	_expect(dist_after < dist_before,
		"ADVANCE: companion moved toward waypoint (dist %.2f → %.2f)" % [dist_before, dist_after])
	_cleanup_nodes([c, player])


# ── 7: Companion COVER_FIRE ──────────────────────────────────────────────────
func _test_companion_cover_fire(gs: Node, sc: Node) -> void:
	sc.call("reset")
	gs.call("reset")
	var player: Node3D = await _make_player(Vector3(0.0, 0.0, 0.0))
	var c: Node3D = await _make_companion("TestCover", Vector3(5.0, 0.0, 5.0), 0)
	# Create a fake hostile in group "enemy".
	var enemy: Node3D = await _make_enemy(Vector3(10.0, 0.0, 5.0))
	await process_frame

	# Set COVER_FIRE — companion should hold position and face the enemy.
	sc.call("set_command", "cover_fire")
	var pos_before: Vector3 = c.global_position
	var rot_before: float = c.rotation.y
	for _i in 30:
		await process_frame
	var moved: float = Vector2(c.global_position.x - pos_before.x, c.global_position.z - pos_before.z).length()
	_expect(moved < 0.05, "COVER_FIRE: companion held position (moved %.4f m)" % moved)
	# Companion should have rotated to face the enemy (rotation changed).
	var rot_after: float = c.rotation.y
	_expect(rot_after != rot_before,
		"COVER_FIRE: companion rotated to face enemy (rot %.3f → %.3f)" % [rot_before, rot_after])
	_cleanup_nodes([c, player, enemy])


# ── 8: Peeled-off companions ignore squad commands ───────────────────────────
func _test_peeled_off_ignores_squad(gs: Node, sc: Node) -> void:
	sc.call("reset")
	gs.call("reset")
	var player: Node3D = await _make_player(Vector3(0.0, 0.0, 0.0))
	var c: Node3D = await _make_companion("TestPeeled", Vector3(3.0, 0.0, 3.0), 0)
	c.set("peeled_off", true)
	await process_frame

	# Set HOLD — peeled_off companion should ignore it (peeled_off returns
	# before the squad command check in _process).
	sc.call("set_command", "hold")
	var pos_before: Vector3 = c.global_position
	# Peeled_off companions hold position regardless — verify they don't move.
	for _i in 20:
		await process_frame
	var moved: float = Vector2(c.global_position.x - pos_before.x, c.global_position.z - pos_before.z).length()
	_expect(moved < 0.05, "Peeled-off: companion holds position (peeled_off overrides squad)")
	_cleanup_nodes([c, player])


# ── 9: CompanionCommentary ───────────────────────────────────────────────────
func _test_commentary(gs: Node) -> void:
	var CommentaryClass: Script = load(COMMENTARY_SCRIPT_PATH)
	_expect(CommentaryClass != null, "CompanionCommentary script loads")
	if CommentaryClass == null:
		return
	var commentary: RefCounted = CommentaryClass.new()

	# Get a mission_start line.
	var line: Dictionary = commentary.get_line("mission_start")
	_expect(not line.is_empty(), "get_line('mission_start') returns a line")
	if not line.is_empty():
		_expect(String(line.get("speaker", "")) == "Greer",
			"mission_start line speaker is Greer (got %s)" % String(line.get("speaker", "")))
		_expect(String(line.get("text", "")) != "",
			"mission_start line has non-empty text")

	# Get a command_issued line for "hold".
	var hold_line: Dictionary = commentary.get_line("command_issued", {"command": "hold"})
	_expect(not hold_line.is_empty(), "get_line('command_issued', hold) returns a line")
	if not hold_line.is_empty():
		_expect(String(hold_line.get("speaker", "")) == "Greer",
			"hold command line speaker is Greer")

	# Get idle lines (multiple).
	var idle_lines: Array = commentary.get_lines("idle")
	_expect(idle_lines.size() >= 3, "get_lines('idle') returns >= 3 lines (got %d)" % idle_lines.size())

	# Emit a line through GameState.say() — verify narrative_added fires.
	var narrative_count: Array[int] = [0]
	var on_narrative: Callable = func(_speaker: String, _text: String) -> void: narrative_count[0] += 1
	if gs.has_signal("narrative_added"):
		gs.connect("narrative_added", on_narrative)
	var emitted: bool = commentary.emit_line("mission_start")
	_expect(emitted == true, "emit_line('mission_start') returns true (line found)")
	_expect(narrative_count[0] >= 1, "emit_line fired narrative_added signal")
	if gs.is_connected("narrative_added", on_narrative):
		gs.disconnect("narrative_added", on_narrative)


# ── 10: Quest chain in quests.json ───────────────────────────────────────────
func _test_quest_chain(ql: Node) -> void:
	# Verify the e2_planet_mission quest exists and has the expected steps.
	ql.call("start_quest", "e2_planet_mission")
	_expect(String(ql.call("active_step_id", "e2_planet_mission")) == "deploy_squad",
		"e2_planet_mission starts at deploy_squad")
	for i in EXPECTED_MISSION_STEPS.size():
		var sid: String = EXPECTED_MISSION_STEPS[i]
		var lbl: String = String(ql.call("label", sid))
		_expect(lbl != "" and lbl != sid,
			"label() resolves real text for step %d (%s)" % [i, sid])
	_expect(ql.call("is_complete", "e2_planet_mission") == false,
		"e2_planet_mission is not complete at start")


# ── 11: QuestLog predicate advance ───────────────────────────────────────────
func _test_quest_predicates(gs: Node, ql: Node) -> void:
	gs.call("reset")
	ql.call("start_quest", "e2_planet_mission")

	# Step 1 → 2: deploy_squad
	gs.call("deploy_squad")
	_expect(String(ql.call("active_step_id", "e2_planet_mission")) == "find_resources",
		"deploy_squad → find_resources")
	_expect(gs.get("squad_deployed") == true, "squad_deployed flag is true")

	# Step 2 → 3: collect_mission_resources
	gs.call("collect_mission_resources")
	_expect(String(ql.call("active_step_id", "e2_planet_mission")) == "investigate_ruins",
		"collect_mission_resources → investigate_ruins")
	_expect(gs.get("mission_resources_collected") == true, "mission_resources_collected flag is true")

	# Step 3 → 4: investigate_ruins
	gs.call("investigate_ruins")
	_expect(String(ql.call("active_step_id", "e2_planet_mission")) == "retrieve_ancient_tech",
		"investigate_ruins → retrieve_ancient_tech")
	_expect(gs.get("ruins_investigated") == true, "ruins_investigated flag is true")

	# Step 4 → 5: retrieve_ancient_tech
	gs.call("retrieve_ancient_tech")
	_expect(String(ql.call("active_step_id", "e2_planet_mission")) == "return_through_gate",
		"retrieve_ancient_tech → return_through_gate")
	_expect(gs.get("ancient_tech_retrieved") == true, "ancient_tech_retrieved flag is true")

	# Step 5 → 6: return_squad
	gs.call("return_squad")
	_expect(String(ql.call("active_step_id", "e2_planet_mission")) == "mission_complete",
		"return_squad → mission_complete (terminal)")
	_expect(ql.call("is_complete", "e2_planet_mission") == true,
		"e2_planet_mission is_complete fires at terminal step")
	_expect(gs.get("squad_returned") == true, "squad_returned flag is true")

	# Idempotency: calling helpers twice is a no-op.
	gs.call("deploy_squad")
	_expect(gs.get("squad_deployed") == true, "deploy_squad() is idempotent")


# ── 12: GameState serialize/deserialize E2 mission flags ───────────────────
func _test_gamestate_serialize(gs: Node) -> void:
	gs.call("reset")
	gs.set("squad_deployed", true)
	gs.set("mission_resources_collected", true)
	gs.set("ruins_investigated", true)
	gs.set("ancient_tech_retrieved", true)
	gs.set("squad_returned", true)
	var snap: Dictionary = gs.call("serialize")
	_expect(snap.get("squad_deployed", false) == true, "serialize squad_deployed")
	_expect(snap.get("mission_resources_collected", false) == true, "serialize mission_resources_collected")
	_expect(snap.get("ruins_investigated", false) == true, "serialize ruins_investigated")
	_expect(snap.get("ancient_tech_retrieved", false) == true, "serialize ancient_tech_retrieved")
	_expect(snap.get("squad_returned", false) == true, "serialize squad_returned")
	gs.call("reset")
	_expect(gs.get("squad_deployed") == false, "reset clears squad_deployed")
	gs.call("deserialize", snap, 1)
	_expect(gs.get("squad_deployed") == true, "deserialize restores squad_deployed")
	_expect(gs.get("mission_resources_collected") == true, "deserialize restores mission_resources_collected")
	_expect(gs.get("ruins_investigated") == true, "deserialize restores ruins_investigated")
	_expect(gs.get("ancient_tech_retrieved") == true, "deserialize restores ancient_tech_retrieved")
	_expect(gs.get("squad_returned") == true, "deserialize restores squad_returned")


# ── 13: planetary_missions.json ─────────────────────────────────────────────
func _test_planetary_missions_data() -> void:
	var f: FileAccess = FileAccess.open(PLANETARY_MISSIONS_PATH, FileAccess.READ)
	_expect(f != null, "planetary_missions.json exists")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	_expect(parsed is Array, "planetary_missions.json parses as array")
	if not (parsed is Array):
		return
	var missions: Array = parsed
	_expect(missions.size() >= 1, "at least 1 planetary mission defined")
	var mission: Dictionary = missions[0] if missions.size() > 0 else {}
	_expect(String(mission.get("id", "")) == "e2_light_planet", "first mission id is e2_light_planet")
	var mission_obj: Variant = mission.get("mission", {})
	_expect(mission_obj is Dictionary, "mission has 'mission' block")
	if not (mission_obj is Dictionary):
		return
	var objectives: Variant = (mission_obj as Dictionary).get("objectives", [])
	_expect(objectives is Array, "mission has objectives array")
	if not (objectives is Array):
		return
	var obj_arr: Array = objectives
	_expect(obj_arr.size() == 3, "mission has 3 objectives (got %d)" % obj_arr.size())
	for i in EXPECTED_OBJECTIVES.size():
		var obj: Dictionary = obj_arr[i] if i < obj_arr.size() else {}
		_expect(String(obj.get("id", "")) == EXPECTED_OBJECTIVES[i],
			"objective %d id is %s (got %s)" % [i, EXPECTED_OBJECTIVES[i], String(obj.get("id", ""))])


# ── helpers ──────────────────────────────────────────────────────────────────

func _make_player(pos: Vector3) -> Node3D:
	# Remove any stale player from a previous test.
	for child in root.get_children():
		if String(child.name) == "TestPlayer":
			child.queue_free()
	await process_frame
	var p := CharacterBody3D.new()
	p.name = "TestPlayer"
	p.add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cs.shape = cap
	p.add_child(cs)
	root.add_child(p)
	p.global_position = pos
	return p


func _make_companion(display_name: String, pos: Vector3, idx: int) -> Node3D:
	var comp_name: String = "TestCompanion_" + display_name
	# Remove any stale companion from a previous test.
	for child in root.get_children():
		if String(child.name) == comp_name:
			child.queue_free()
	await process_frame
	var CompanionClass: Script = load(COMPANION_SCRIPT_PATH)
	var c: Node3D = CompanionClass.new()
	c.name = comp_name
	c.set("peeled_off", false)
	c.set("squad_responsive", true)
	root.add_child(c)
	c.global_position = pos
	# Use a fallback GLB path — setup handles missing files gracefully.
	c.call("setup", display_name, "res://models/characters/greer.glb", idx)
	return c


func _make_enemy(pos: Vector3) -> Node3D:
	# Remove stale enemy.
	for child in root.get_children():
		if String(child.name) == "TestEnemy":
			child.queue_free()
	await process_frame
	var e := Node3D.new()
	e.name = "TestEnemy"
	e.add_to_group("enemy")
	root.add_child(e)
	e.global_position = pos
	return e


func _cleanup_nodes(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await process_frame


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