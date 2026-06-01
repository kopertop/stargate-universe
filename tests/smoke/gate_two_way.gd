extends SceneTree

# Issue #68 — player-side free two-way gate travel + persistent-open gate lifecycle.
#
# Mirrors the Kino two-way fix (PR #67) onto the on-foot player path. The KEY RULE
# (design/gdd/stargate-planetary-runs.md): an OPEN Stargate is a free two-way
# portal both directions, unlimited crossings, UNTIL it closes — and it closes on
# the terminal world/story condition (scrubber_repaired), NOT on the player having
# crossed back once.
#
# Run with:
#   godot --headless --quit-after 900 -s res://tests/smoke/gate_two_way.gd
#
# Covers (acceptance criteria):
#   • is_gate_open() stays true across repeated crossings (out→back→out→back),
#     dropping the old `not returned_from_lime_planet` term.
#   • The gate closes ONLY on the real terminal condition (scrubber_repaired).
#   • can_travel_to_lime_planet() permits re-travel for the whole open window
#     (MINE_LIME, RETURN_DESTINY, REPAIR_SCRUBBER), and refuses once closed.
#   • PlanetGate to_ship flags the away-team return (pending_planet_return) on the
#     FIRST crossing only; a second solo crossing carries only the player.
#   • Quest progression is unaffected by repeat crossings.
#   • Arm-latch: a player who SPAWNS overlapping the gate volume does not auto-cross.
#
# PlanetGate is load()ed at runtime (references autoload globals not visible at the
# top-level compile pass of a `-s` SceneTree script) — same pattern as kino_doors.gd.

var PlanetGateScript: Script = null

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== gate two-way travel tests ===")
	PlanetGateScript = load("res://scripts/planet_gate.gd")
	if PlanetGateScript == null:
		print("SHOT_ERROR could not load PlanetGate script")
		quit(1)
		return

	var gs: Node = root.get_node_or_null("GameState")
	var router: Node = root.get_node_or_null("SceneRouter")
	_expect(gs != null, "GameState autoload attached")
	_expect(router != null, "SceneRouter autoload attached")
	if gs == null or router == null:
		_report()
		return

	_test_gate_open_lifecycle(gs)
	_test_can_travel_window(gs)
	await _test_to_ship_away_team_once(gs, router)
	await _test_to_planet_arm_latch(gs, router)

	gs.call("reset")
	router.set("is_transitioning", false)
	router.set("instant_mode", false)
	_report()


# ── gate-open lifecycle: open window survives repeat crossings ─────────────────
# Arrange the open gate, then walk the player out→back→out→back and assert the
# gate reads OPEN every time. It must close ONLY when scrubber_repaired flips.
func _test_gate_open_lifecycle(gs: Node) -> void:
	print("\n--- gate-open window survives repeated crossings ---")
	gs.call("reset")

	# Arrange: dial the gate open (the dial-flag is the window OPEN condition).
	gs.set("lime_planet_dialed", true)
	_expect(gs.call("is_gate_open") == true, "gate opens once a destination is dialed")

	# Act + Assert: the one-shot return latch must NOT close the window.
	gs.set("returned_from_lime_planet", true)
	_expect(gs.call("is_gate_open") == true,
		"gate STAYS open after the first return (window != one-shot story latch)")

	# Simulate repeated crossings — the lifecycle never depends on a crossing count.
	for i in 4:
		_expect(gs.call("is_gate_open") == true,
			"gate still open on repeat crossing #%d" % (i + 1))

	# Act: the terminal world condition fires.
	gs.set("scrubber_repaired", true)
	# Assert: NOW the gate closes — and only now.
	_expect(gs.call("is_gate_open") == false,
		"gate closes on the terminal condition (scrubber_repaired), not on first return")


# ── can_travel window: re-travel allowed across the whole open window ──────────
func _test_can_travel_window(gs: Node) -> void:
	print("\n--- can_travel_to_lime_planet spans the open window ---")
	gs.call("reset")
	gs.set("lime_planet_dialed", true)

	# Mining outbound.
	gs.set("quest_step", gs.QUEST_MINE_LIME)
	_expect(gs.call("can_travel_to_lime_planet") == true,
		"can travel during MINE_LIME")
	# After collecting lime → RETURN_DESTINY: still an open two-way gate.
	gs.set("quest_step", gs.QUEST_RETURN_DESTINY)
	_expect(gs.call("can_travel_to_lime_planet") == true,
		"can re-travel during RETURN_DESTINY")
	# After carrying lime home → REPAIR_SCRUBBER: gate still open, re-travel allowed
	# (the new step that the old guard excluded — the regression this fixes).
	gs.set("quest_step", gs.QUEST_REPAIR_SCRUBBER)
	_expect(gs.call("can_travel_to_lime_planet") == true,
		"can re-travel during REPAIR_SCRUBBER (open window, two-way)")

	# Terminal condition closes the gate → no more travel regardless of step.
	gs.set("scrubber_repaired", true)
	_expect(gs.call("can_travel_to_lime_planet") == false,
		"cannot travel once the gate has closed (scrubber repaired)")


# ── to_ship: away team returns ONCE; later solo crossings carry only the player ─
# The to_ship _travel sets _transitioning before awaiting change_to; we block the
# real scene swap (router.is_transitioning=true) so change_to early-returns and we
# can inspect pending_planet_return + _transitioning right after.
func _test_to_ship_away_team_once(gs: Node, router: Node) -> void:
	print("\n--- to_ship return flags the away team exactly once ---")
	await _cleanup()
	gs.call("reset")
	gs.set("lime_planet_dialed", true)
	gs.set("quest_step", gs.QUEST_RETURN_DESTINY)
	# Enough lime so the MINE_LIME quota guard never trips (it's already past it).
	gs.set("current_scene_path", "res://scenes/planet.tscn")
	router.set("instant_mode", true)
	router.set("is_transitioning", true)   # block the real scene load

	var player := _make_player()
	root.add_child(player)
	var gate: Node = _make_gate("to_ship", "res://scenes/gate_room.tscn", "FromPlanet")
	root.add_child(gate)
	gate.set("_armed", true)               # isolate from the spawn-overlap latch
	await process_frame

	# First crossing home: away-team return is flagged, story latch fires. The
	# exact quest step id depends on QuestLog's state machine (driven separately
	# in e1_flow); here we assert the LATCH + away-team flag + that a repeat
	# crossing does not re-fire the advance.
	_expect(gs.get("returned_from_lime_planet") == false, "story latch unset before first return")
	await gate.call("activate", player)
	_expect(gs.get("returned_from_lime_planet") == true,
		"first to_ship crossing fires the one-shot return latch")
	_expect(gs.get("pending_planet_return") == true,
		"first crossing flags the away team to spawn home WITH the player")
	var step_after_first: String = String(gs.get("quest_step"))

	# Gate room would consume the flag on arrival — simulate that here.
	gs.set("pending_planet_return", false)

	# Second crossing home (solo re-cross on the still-open gate): NO re-flag,
	# and the return-latch advance must not fire again (quest step unchanged).
	gate.set("_transitioning", false)      # fresh gate instance per scene IRL
	gate.set("_armed", true)
	await gate.call("activate", player)
	_expect(gs.get("pending_planet_return") == false,
		"a SECOND solo return does NOT re-flag the away team (no duplicate spawn)")
	_expect(String(gs.get("quest_step")) == step_after_first,
		"repeat crossing does not regress / re-advance the quest")
	_expect(gs.call("is_gate_open") == true,
		"gate still open after repeated returns (until scrubber repaired)")


# ── to_planet arm-latch: spawn-overlapping the gate must NOT auto-cross ────────
func _test_to_planet_arm_latch(gs: Node, router: Node) -> void:
	print("\n--- to_planet arm-latch (no spawn-on-gate bounce) ---")
	await _cleanup()
	gs.call("reset")
	gs.set("lime_planet_dialed", true)
	gs.set("quest_step", gs.QUEST_MINE_LIME)
	router.set("instant_mode", true)
	router.set("is_transitioning", true)   # block real scene load

	# Case 1 — player spawns INSIDE the gate volume (overlapping at _ready). The
	# gate starts disarmed and _arm_if_spawn_clear must NOT arm it while the player
	# overlaps, so a spawn-on-gate doesn't bounce the player straight back.
	var gate: Node = _make_gate("to_planet", "res://scenes/planet.tscn", "FromShipGate")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.4, 3.2, 1.2)
	shape.shape = box
	gate.add_child(shape)
	var player := _make_player()
	root.add_child(gate)
	root.add_child(player)
	(player as Node3D).global_position = (gate as Node3D).global_position
	# Let _ready's deferred _arm_if_spawn_clear settle (it awaits 4 physics frames).
	for _i in 7:
		await physics_frame
	await process_frame

	_expect(gate.get("_armed") == false,
		"gate stays DISARMED when the player spawns overlapping its volume")

	# The spawn-overlap body_entered must NOT cross AND must NOT arm — arming is
	# owned by leaving the volume, so the player can't insta-bounce back home.
	gate.call("_on_body_entered", player)
	_expect(gate.get("_transitioning") == false,
		"un-armed gate does NOT cross on the spawn-overlap contact (anti spawn-on-gate bounce)")
	_expect(gate.get("_armed") == false,
		"spawn-overlap contact does NOT arm the gate (must leave the volume first)")

	# Leaving the volume arms the gate.
	gate.call("_on_body_exited", player)
	_expect(gate.get("_armed") == true, "leaving the volume re-arms the gate")

	# Now armed → a genuine re-entry crosses (gate open, quest in window).
	gate.call("_on_body_entered", player)
	_expect(gate.get("_transitioning") == true,
		"armed gate crosses on the next genuine entry after leaving + re-entering")

	await _cleanup()

	# Case 2 — a CLEAR spawn (player not overlapping) arms the gate after a physics
	# frame, so a normal walk-in crosses on first contact (no false latch).
	var gate2: Node = _make_gate("to_planet", "res://scenes/planet.tscn", "FromShipGate")
	var shape2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(4.4, 3.2, 1.2)
	shape2.shape = box2
	gate2.add_child(shape2)
	root.add_child(gate2)
	(gate2 as Node3D).global_position = Vector3(0.0, 0.0, 0.0)
	var player2 := _make_player()
	root.add_child(player2)
	(player2 as Node3D).global_position = Vector3(0.0, 0.0, 50.0)  # well clear of the gate
	for _j in 7:
		await physics_frame
	await process_frame
	_expect(gate2.get("_armed") == true,
		"a clear spawn arms the gate (normal walk-in crosses on first contact)")

	await _cleanup()


# ── helpers ────────────────────────────────────────────────────────────────────

func _make_gate(mode: String, target_scene: String, target_spawn: String) -> Node:
	var g: Area3D = Area3D.new()
	g.set_script(PlanetGateScript)
	g.set("mode", mode)
	g.set("target_scene", target_scene)
	g.set("target_spawn", target_spawn)
	return g


# A minimal CharacterBody3D in group "player" — PlanetGate._travel only checks
# group membership, not the full player rig.
func _make_player() -> Node3D:
	var p := CharacterBody3D.new()
	p.name = "TestPlayer"
	p.add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cs.shape = cap
	p.add_child(cs)
	return p


func _cleanup() -> void:
	for child in root.get_children():
		if child == self:
			continue
		var nm: String = String(child.name)
		# Leave the autoloads + the SceneTree's current scene alone; only sweep the
		# test-built players/gates.
		if child is Area3D or nm == "TestPlayer":
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
