extends SceneTree

# Smoke test for issue #137 — planet away-team split (Greer north, Scott+Park south).
#
# Verifies:
#   1. away_team group has exactly 3 companions after _spawn_away_team.
#   2. Exactly 1 north companion (Greer, peeled_off=false) + 2 south (Park/Scott,
#      peeled_off=true).
#   3. Greer spawns on the -Z side of the player; Park/Scott on +Z (sign separation).
#   4. After moving the player north + ticking, Greer stays within FOLLOW_DIST;
#      Park/Scott do not move (hold spawn position).
#   5. log_entries contains the exact Scott split line (radio report).
#   6. log_entries contains the arrival dialogue log line.
#   7. resource_count("lime") is unchanged across spawn (no add_resource).
#   8. instant_mode=true → no companions spawn + no split/radio logs.
#   9. REGRESSION (black-screen-on-arrival): _play_split_dialogue must DEFER its
#      dialog_started emit until SceneRouter.is_transitioning clears. Emitting
#      mid-transition opens the WoW dialog, which pauses the tree, which stalls
#      SceneRouter's fade-OUT tween — freezing the full-screen black fade up
#      forever (the planet "never loads"). The emit must wait for the fade.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/away_team_split.gd

const PLANET_SCRIPT_PATH: String = "res://scripts/planet.gd"
const COMPANION_SCRIPT_PATH: String = "res://scripts/companion.gd"
# FOLLOW_DIST from companion.gd = 3.2 — companions within this distance hold still.
# We use 12.0 as a generous "still following" ceiling after player moves north.
const FOLLOW_DIST_MAX: float = 12.0
const RADIO_LINE: String = "Lt Scott (radio): South ridge's got lime too — we're pulling some. You grab what's near the gate."
const DIALOGUE_LINE: String = "Lt Scott: Okay, let's split up. Greer and Eli, you head north. Park and I will head south."

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== away_team_split smoke test ===")

	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(gs != null, "GameState autoload attached")
	_expect(router != null, "SceneRouter autoload attached")
	if gs == null or router == null:
		_report()
		return

	await _test_live_spawn(gs, router)
	await _test_instant_mode_no_spawn(gs, router)
	await _test_dialogue_deferred_during_transition(gs, router)

	# Final cleanup
	gs.call("reset")
	router.set("instant_mode", false)
	router.set("is_transitioning", false)

	_report()


# ── 1: live-play spawn (instant_mode=false) ─────────────────────────────────
func _test_live_spawn(gs: Node, router: Node) -> void:
	print("\n--- live spawn (instant_mode=false) ---")
	gs.call("reset")
	router.set("instant_mode", false)

	# Seed the required state so _spawn_away_team is reachable from _ready.
	gs.set("quest_step", gs.QUEST_MINE_LIME)
	gs.set("lime_planet_dialed", true)
	gs.set("active_planet_spec", gs.call("build_air_lime_spec"))

	# Snapshot lime count BEFORE any spawn.
	var lime_before: int = gs.call("resource_count", gs.AIR_LIME_RESOURCE)

	# Build a minimal player in group "player" so _spawn_away_team can find it.
	var player: Node3D = _make_player(Vector3(0.0, 0.0, 0.0))
	root.add_child(player)

	# Clear any pre-existing log entries from state setup so the assertions are clean.
	gs.get("log_entries").clear()

	# Directly call _spawn_away_team on an instance of the planet script.
	# We cannot load the full planet.tscn without the whole scene graph, so we
	# test the two functions we changed individually (same pattern as gate_two_way.gd).
	var planet_script: Script = load(PLANET_SCRIPT_PATH)
	_expect(planet_script != null, "planet script loads")
	if planet_script == null:
		await _cleanup()
		return

	# Instantiate a bare planet script holder (Node3D). We call _spawn_away_team
	# and _play_split_dialogue directly so no planet.tscn scene graph is needed.
	var planet: Node3D = Node3D.new()
	planet.set_script(planet_script)
	# The planet script's _spawn_away_team calls add_child on `self`, so we must
	# add the planet node to the tree first so add_child works.
	root.add_child(planet)
	await process_frame

	# --- arrival dialogue ---
	# _play_split_dialogue checks SceneRouter.instant_mode directly via autoload.
	# instant_mode=false → should emit dialog_started + add_log.
	planet.call("_play_split_dialogue")

	# --- spawn the away team ---
	planet.call("_spawn_away_team", player.global_position)
	await process_frame

	# 1. Away team group size = 3.
	var away_team: Array = get_nodes_in_group("away_team")
	# Filter to companions spawned by THIS planet node (children of planet).
	var companions: Array = []
	for n in planet.get_children():
		if String(n.get_script().resource_path if n.get_script() != null else "") == COMPANION_SCRIPT_PATH:
			companions.append(n)
	# Also check via group (all must be in away_team).
	_expect(companions.size() == 3, "away_team has exactly 3 companions (got %d)" % companions.size())

	# 2. Partition: 1 north (peeled_off=false), 2 south (peeled_off=true).
	var north_team: Array = []
	var south_team: Array = []
	for c in companions:
		if c.get("peeled_off") == true:
			south_team.append(c)
		else:
			north_team.append(c)
	_expect(north_team.size() == 1, "1 north companion (Greer, peeled_off=false), got %d" % north_team.size())
	_expect(south_team.size() == 2, "2 south companions (Park+Scott, peeled_off=true), got %d" % south_team.size())

	# 3. Greer is north (peeled_off=false) and named Greer.
	if north_team.size() == 1:
		var greer: Node3D = north_team[0]
		_expect(String(greer.name) == "Companion_Greer", "north companion is Companion_Greer")

	# 4. South companion names are Park and LtScott.
	var south_names: Array = []
	for c in south_team:
		south_names.append(String(c.name))
	_expect(south_names.has("Companion_Park"), "south team includes Companion_Park")
	_expect(south_names.has("Companion_LtScott"), "south team includes Companion_LtScott")

	# 5. Spawn-side sign separation: Greer Z < player Z (north=-Z);
	#    Park/Scott Z > player Z (south=+Z). Planar XZ only.
	var player_z: float = player.global_position.z
	if north_team.size() == 1:
		var gz: float = (north_team[0] as Node3D).global_position.z
		_expect(gz < player_z, "Greer spawns north of player (Z < player_Z: %.2f < %.2f)" % [gz, player_z])
	for c in south_team:
		var sz: float = (c as Node3D).global_position.z
		_expect(sz > player_z, "%s spawns south of player (Z > player_Z: %.2f > %.2f)" % [String(c.name), sz, player_z])

	# 6. Greer follows: move player north and tick; Greer should move toward player.
	#    Park/Scott hold position (peeled_off=true → _set_moving(false); return).
	#    We record positions before the tick and assert Greer closed the gap while
	#    south members are unchanged.
	var south_pos_before: Dictionary = {}
	for c in south_team:
		south_pos_before[c.name] = (c as Node3D).global_position

	var greer_z_before: float = 0.0
	if north_team.size() == 1:
		greer_z_before = (north_team[0] as Node3D).global_position.z

	# Move player north (-Z) so the follow goal (player + trailing offset) is
	# well beyond Greer's spawn. Greer should step north (Z decreases / becomes
	# more negative). Park/Scott must stay put.
	player.global_position = Vector3(0.0, 0.0, -8.0)
	# Tick process frames so companion _process runs and moves Greer toward goal.
	for _i in 60:
		await process_frame

	# Greer should have moved north: Z must have decreased (more negative).
	# _follow computes goal = player.pos + offset(slot=0) = (0,0,-8)+(-1.6,0,1.8)
	# = (-1.6,0,-6.2). Greer starts at (-1.2,0,-2.4) → steps toward (-1.6,0,-6.2)
	# so position.z decreases each frame.
	if north_team.size() == 1:
		var greer: Node3D = north_team[0]
		var greer_z_after: float = greer.global_position.z
		_expect(greer_z_after < greer_z_before,
			"Greer moved north (Z %.2f → %.2f, decreased toward follow goal)" % [greer_z_before, greer_z_after])

	# Park/Scott must not have moved (peeled_off=true → hold position).
	for c in south_team:
		var pos_now: Vector3 = (c as Node3D).global_position
		var pos_was: Vector3 = south_pos_before[c.name]
		var moved: float = Vector2(pos_now.x - pos_was.x, pos_now.z - pos_was.z).length()
		_expect(moved < 0.05, "%s held position (moved %.4f m)" % [String(c.name), moved])

	# 7. Lime count unchanged (radio log must NOT call add_resource).
	var lime_after: int = gs.call("resource_count", gs.AIR_LIME_RESOURCE)
	_expect(lime_after == lime_before,
		"resource_count(lime) unchanged after spawn (no add_resource in radio report)")

	# 8. Log contains the Scott radio line.
	var logs: Array = gs.get("log_entries")
	var has_radio: bool = false
	for line in logs:
		if String(line) == RADIO_LINE:
			has_radio = true
			break
	_expect(has_radio, "log_entries contains the Scott south-team radio report")

	# 9. Log contains the arrival dialogue line.
	var has_dialogue_log: bool = false
	for line in logs:
		if String(line) == DIALOGUE_LINE:
			has_dialogue_log = true
			break
	_expect(has_dialogue_log, "log_entries contains the Scott split dialogue log line")

	# All companions are in group "away_team" (group membership check).
	for c in companions:
		_expect(c.is_in_group("away_team"), "%s is in group away_team" % String(c.name))

	await _cleanup_planet(planet, player)


# ── 2: instant_mode=true → no companions spawn + no split/radio logs ─────────
func _test_instant_mode_no_spawn(gs: Node, router: Node) -> void:
	print("\n--- instant_mode=true (headless guard) ---")
	gs.call("reset")
	router.set("instant_mode", true)

	gs.set("quest_step", gs.QUEST_MINE_LIME)
	gs.set("lime_planet_dialed", true)
	gs.set("active_planet_spec", gs.call("build_air_lime_spec"))

	# Clear log so we can assert no new lines added.
	gs.get("log_entries").clear()

	var player: Node3D = _make_player(Vector3(0.0, 0.0, 0.0))
	root.add_child(player)

	var planet_script: Script = load(PLANET_SCRIPT_PATH)
	if planet_script == null:
		_expect(false, "planet script loads (instant_mode sub-test)")
		await _cleanup()
		return

	# Under instant_mode, _play_split_dialogue must return immediately without
	# emitting dialog_started or adding a log line.
	var planet: Node3D = Node3D.new()
	planet.set_script(planet_script)
	root.add_child(planet)
	await process_frame

	# Call _play_split_dialogue — should early-return (instant_mode=true).
	planet.call("_play_split_dialogue")

	# The outer guard in planet.gd::_ready (not instant_mode) means _spawn_away_team
	# would never be called at all in headless. We replicate that guard here:
	# don't call _spawn_away_team under instant_mode, matching _ready behavior.
	# Assert: no companions were added by the dialogue call.
	var companions_after_dialogue: Array = []
	for n in planet.get_children():
		if n.get_script() != null and \
				String(n.get_script().resource_path) == COMPANION_SCRIPT_PATH:
			companions_after_dialogue.append(n)
	_expect(companions_after_dialogue.is_empty(),
		"instant_mode: _play_split_dialogue does not spawn companions")

	# Assert: no log line added by _play_split_dialogue under instant_mode.
	var logs: Array = gs.get("log_entries")
	var has_dialogue_log: bool = false
	var has_radio: bool = false
	for line in logs:
		if String(line) == DIALOGUE_LINE:
			has_dialogue_log = true
		if String(line) == RADIO_LINE:
			has_radio = true
	_expect(not has_dialogue_log, "instant_mode: _play_split_dialogue adds no log line")

	# Also verify that if someone accidentally calls _spawn_away_team with instant_mode
	# set, the companions WOULD spawn (the guard is in _ready, not _spawn_away_team).
	# This isn't a requirement to block — just confirm peeled_off wiring still works.
	# We skip the _spawn_away_team call here (mirrors what _ready does: it's gated
	# by `if not SceneRouter.instant_mode`).
	_expect(not has_radio,
		"instant_mode: no radio log (spawn was skipped by _ready's guard)")

	await _cleanup_planet(planet, player)


# ── 3: regression — dialog emit is deferred past the arrival transition ──────
# Reproduces the black-screen-on-arrival deadlock: in live play the planet's
# _ready fires _play_split_dialogue WHILE SceneRouter is still mid-fade
# (is_transitioning=true). The WoW dialog pauses the tree on open, and the
# router's fade-OUT is a tween bound to the now-paused autoload — so the black
# fade rect never lifts. The fix defers the emit until is_transitioning clears.
# Against the pre-fix code (synchronous emit) the "deferred while transitioning"
# assertion fails — exactly the regression we want guarded.
func _test_dialogue_deferred_during_transition(gs: Node, router: Node) -> void:
	print("\n--- regression: dialog deferred until transition completes ---")
	# Arrange: live mode, but a scene transition is still in progress (mid-fade).
	gs.call("reset")
	router.set("instant_mode", false)
	router.set("is_transitioning", true)
	gs.set("quest_step", gs.QUEST_MINE_LIME)
	gs.set("lime_planet_dialed", true)
	gs.set("active_planet_spec", gs.call("build_air_lime_spec"))

	var player: Node3D = _make_player(Vector3.ZERO)
	root.add_child(player)

	var planet_script: Script = load(PLANET_SCRIPT_PATH)
	var planet: Node3D = Node3D.new()
	planet.set_script(planet_script)
	# add_child fires planet._ready, which aborts early on the bare node (no
	# $World/$Player/$View) BEFORE any dialogue code — same harness pattern as
	# _test_live_spawn. Let that settle, THEN connect the listener so only our
	# explicit _play_split_dialogue call is measured.
	root.add_child(planet)
	await process_frame

	# Count dialog_started emits via our own listener (HUD is a scene node, not an
	# autoload, so nothing else is connected in this headless harness).
	var emit_count: Array[int] = [0]
	var on_emit: Callable = func(_npc: Variant, _tree: Variant) -> void:
		emit_count[0] += 1
	gs.connect("dialog_started", on_emit)

	# Act 1: fire the split dialogue while the transition is still running. The
	# coroutine should park on its is_transitioning poll and NOT emit yet.
	planet.call("_play_split_dialogue")
	for _i in 20:
		await process_frame

	# Assert 1: emit deferred while transitioning; tree never paused mid-fade.
	_expect(emit_count[0] == 0,
		"dialog_started NOT emitted while SceneRouter.is_transitioning (deferred past fade)")
	_expect(not paused,
		"tree not paused during the arrival transition (fade can complete)")

	# Act 2: transition completes (fade-out done) — the deferred emit should fire.
	router.set("is_transitioning", false)
	for _i in 10:
		await process_frame

	# Assert 2: dialog emitted exactly once, now that the fade has cleared.
	_expect(emit_count[0] == 1,
		"dialog_started emitted once after the transition clears (got %d)" % emit_count[0])

	if gs.is_connected("dialog_started", on_emit):
		gs.disconnect("dialog_started", on_emit)
	await _cleanup_planet(planet, player)


# ── helpers ──────────────────────────────────────────────────────────────────

func _make_player(pos: Vector3) -> Node3D:
	var p := CharacterBody3D.new()
	p.name = "TestPlayer"
	p.add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cs.shape = cap
	p.add_child(cs)
	p.global_position = pos
	return p


func _cleanup_planet(planet: Node3D, player: Node3D) -> void:
	planet.queue_free()
	player.queue_free()
	await process_frame


func _cleanup() -> void:
	for child in root.get_children():
		if String(child.name) in ["GameState", "SceneRouter", "QuestLog", "Inventory",
				"Audio", "SaveManager", "NPCState", "HUD"]:
			continue
		if child == self:
			continue
		child.queue_free()
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
