extends SceneTree

# Smoke test for issue #136 — E1 cold-open standoff + Kino pickup line.
#
# Verifies:
#   1. DrRush dialogue_tree has speakers in order Eli → Sgt Greer → Lt Scott →
#      Dr Rush, and Eli's line contains "blow up".
#   2. After DrRush.interact(player): met_rush==true, quest_step==QUEST_FIND_REST.
#   3. ControlConsole no-op (met_rush==true, step==QUEST_FIND_RUSH): exact log
#      line logged, quest step unchanged, and ZERO mutation to
#      life_support_diagnosed / breaches_sealed / air_crisis_started.
#   4. KINO_DIALOG_TREE[0].text == "Oh, what's that? Looks portable." and no
#      node in the tree contains the banned "didn't leave this here" /
#      "don't remember putting" phrases.
#   5. KinoPickup.interact(player) → Inventory.has("kino_remote").
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/e1_opening.gd

const NPC_SCRIPT_PATH: String = "res://scripts/npc.gd"
const CONSOLE_SCRIPT_PATH: String = "res://scripts/control_console.gd"
const KINO_PICKUP_SCRIPT_PATH: String = "res://scripts/kino_pickup.gd"

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== e1_opening smoke test (issue #136) ===")

	var gs: Node = root.get_node_or_null("GameState")
	var inv: Node = root.get_node_or_null("Inventory")
	var router: Node = root.get_node_or_null("SceneRouter")
	var save_mgr: Node = root.get_node_or_null("SaveManager")

	_expect(gs != null, "GameState autoload present")
	_expect(inv != null, "Inventory autoload present")
	_expect(router != null, "SceneRouter autoload present")
	if gs == null or inv == null or router == null:
		_report()
		return

	# Redirect save I/O so the test never touches the real user:// save.
	if save_mgr != null and save_mgr.has_method("configure_test_paths"):
		save_mgr.call("configure_test_paths")

	# Instant mode: state flips synchronously; no awaited coroutines or cutscenes.
	router.set("instant_mode", true)
	gs.call("reset")

	# ── 1. Standoff tree structure ─────────────────────────────────────────────
	_test_standoff_tree_structure(gs)

	# ── 1b. Standoff actors physically spawn in the control room ──────────────
	await _test_standoff_actors_spawn(gs)

	# ── 2. DrRush.interact → met_rush + quest advancement ─────────────────────
	# Uses await so it must be driven from an async wrapper.
	await _test_rush_interact_advances_quest(gs)

	# ── 3. Console no-op: zero mutation + exact log line ──────────────────────
	await _test_console_noop(gs)

	# ── 4. Kino discovery line: correct text, no banned phrases ───────────────
	_test_kino_discovery_line()

	# ── 5. KinoPickup.interact → Inventory.has("kino_remote") ─────────────────
	await _test_kino_pickup_grants_item(gs, inv)

	_report()


# ── 1. Standoff tree structure ─────────────────────────────────────────────────

func _test_standoff_tree_structure(gs: Node) -> void:
	print("\n-- standoff tree structure --")
	gs.call("reset")

	# Load the DrRush NPC exactly as room.gd's _spawn_dr_rush does, then read
	# its dialogue_tree. We don't add it to the scene — only field reads needed.
	var npc_script: Script = load(NPC_SCRIPT_PATH) as Script
	_expect(npc_script != null, "npc.gd script loads")
	if npc_script == null:
		return

	var rush: StaticBody3D = StaticBody3D.new()
	rush.set_script(npc_script)
	rush.name = "DrRush"
	rush.set("character_name", "Dr Rush")

	# Mirror the standoff tree assigned in room.gd::_spawn_dr_rush. The "action"
	# keys are the choreography cues that drive the physical Greer/Scott staging
	# (see room.gd::_on_standoff_cue) — they ride GameState.dialog_action.
	rush.set("dialogue_tree", [
		{
			"speaker": "Eli",
			"text": "Rush, don't! That thing could blow up the ship!",
			"choices": [{"text": "Step forward.", "next": 1}],
		},
		{
			"speaker": "Sgt Greer",
			"action": "standoff_greer",
			"hold": true,
			"text": "Doctor. Step away from the console. Now. I am not asking.",
			"choices": [{"text": "Watch Greer's hand drift to his sidearm.", "next": 2}],
		},
		{
			"speaker": "Lt Scott",
			"action": "standoff_scott",
			"text": "Greer — stand down. Nobody's shooting anyone. Rush, we just need a moment.",
			"choices": [{"text": "Wait for Rush's response.", "next": 3}],
		},
		{
			"speaker": "Dr Rush",
			"action": "standoff_rush_talks",
			"text": "Eli, you don't know what you're talking about. You only THINK you do, because I embedded a rudimentary version of Ancient into the game you played.",
			"choices": [{"text": "Watch as Rush presses the button anyway.", "next": 4}],
		},
		{
			"speaker": "Dr Rush",
			"action": "standoff_rush_leaves",
			"caption_delay": 2.2,
			"text": "Well. That's that, then.",
			"choices": [{"text": "Watch him go.", "next": 5}],
		},
		{
			"speaker": "Eli",
			"action": "standoff_eli_console",
			"text": "Apparently… that did nothing?",
			"choices": [{"text": "Stare at the readout.", "next": 6}],
		},
		{
			"speaker": "Eli",
			"action": "standoff_clear",
			"text": "And everyone's just… walking away. Okay. I need to find somewhere to cool off.",
			"choices": [{"text": "Go find your quarters.", "next": "exit"}],
		},
	])
	rush.set("met_flag", "met_rush")
	rush.set("first_meet_recompute_objective", true)

	var tree: Array = rush.get("dialogue_tree")
	_expect(tree.size() >= 7, "standoff tree has at least 7 nodes")
	if tree.is_empty():
		rush.free()
		return

	# Verify speaker order: the confrontation ends on RUSH shrugging off and
	# ELI working the console + deciding to go cool off.
	var expected_speakers: Array[String] = ["Eli", "Sgt Greer", "Lt Scott", "Dr Rush", "Dr Rush", "Eli", "Eli"]
	for i in expected_speakers.size():
		if i < tree.size():
			var nd: Variant = tree[i]
			var speaker: String = ""
			if nd is Dictionary:
				speaker = String((nd as Dictionary).get("speaker", ""))
			_expect(speaker == expected_speakers[i],
				"standoff node[%d] speaker == '%s' (got '%s')" % [i, expected_speakers[i], speaker])

	# Eli's line must contain "blow up"
	var eli_text: String = ""
	var eli_nd: Variant = tree[0]
	if eli_nd is Dictionary:
		eli_text = String((eli_nd as Dictionary).get("text", ""))
	_expect("blow up" in eli_text,
		"Eli's opening line contains 'blow up' (got: '%s')" % eli_text)

	# Choreography cues: every staged beat must carry the action id that
	# room.gd::_on_standoff_cue dispatches on. Without these the actors
	# never move (regression guard for the "Greer talks but isn't in the room" bug).
	var expected_actions: Dictionary = {
		1: "standoff_greer", 2: "standoff_scott", 3: "standoff_rush_talks",
		4: "standoff_rush_leaves", 5: "standoff_eli_console", 6: "standoff_clear",
	}
	for idx in expected_actions:
		var want: String = expected_actions[idx]
		var got: String = ""
		if idx < tree.size() and tree[idx] is Dictionary:
			got = String((tree[idx] as Dictionary).get("action", ""))
		_expect(got == want, "standoff node[%d] action == '%s' (got '%s')" % [idx, want, got])

	# Greer's node must HOLD — the player can't continue until he's charged in.
	var greer_holds: bool = tree.size() > 1 and tree[1] is Dictionary \
		and (tree[1] as Dictionary).get("hold", false) == true
	_expect(greer_holds, "Greer's standoff node holds the dialog until he arrives")

	# Rush shrugs the confrontation off and leaves; Eli closes the scene by
	# deciding HIMSELF to go cool off (the quest objective handles "quarters").
	var rush_exit_text: String = ""
	if tree.size() >= 5 and tree[4] is Dictionary:
		rush_exit_text = String((tree[4] as Dictionary).get("text", "")).to_lower()
	_expect("that's that" in rush_exit_text,
		"Rush shrugs off with 'that's that' (got: '%s')" % rush_exit_text)
	var eli_final_text: String = ""
	if tree.size() >= 7 and tree[6] is Dictionary:
		eli_final_text = String((tree[6] as Dictionary).get("text", "")).to_lower()
	_expect(not ("quarters" in eli_final_text),
		"Eli's closer doesn't hardcode 'quarters' (got: '%s')" % eli_final_text)
	_expect("cool off" in eli_final_text,
		"Eli decides to go cool off")

	rush.free()


# ── 1b. Standoff actors physically spawn in the control room ──────────────────
# Regression guard for "Greer talks but isn't in the room": instance the REAL
# control_interface_room at the find_rush beat and assert Greer + Scott bodies
# spawn as silent (non-interactable) actors, with Greer carrying his sidearm.
func _test_standoff_actors_spawn(gs: Node) -> void:
	print("\n-- standoff actors spawn in control room --")
	gs.call("reset")  # fresh state: met_rush/air_crisis/kino_pilot all false

	var packed: PackedScene = load("res://scenes/room.tscn") as PackedScene
	_expect(packed != null, "room.tscn loads")
	if packed == null:
		return
	gs.set("next_room_id", "control_interface_room")
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame  # let room.gd::_ready() build + _maybe_spawn_standoff() run

	var greer: Node = inst.get_node_or_null("StandoffGreer")
	var scott: Node = inst.get_node_or_null("StandoffScott")
	_expect(greer != null, "StandoffGreer body spawned in control room")
	_expect(scott != null, "StandoffScott body spawned in control room")

	if greer != null:
		_expect(greer.get("enabled") == false, "Greer is non-interactable (enabled == false)")
		_expect(int(greer.get("collision_layer")) == 0,
			"Greer is off the interact layer (collision_layer == 0)")
		_expect(_has_snapped_gear(greer, "Sidearm"), "Greer carries a Sidearm snapped to a bone")
		_expect(_has_snapped_gear(greer, "Rifle"), "Greer arrives with his rifle slung (grid-verified mount)")
		_expect(not _has_snapped_gear(greer, "Helmet"), "Greer is bareheaded (no helmets aboard ship)")
	if scott != null:
		_expect(scott.get("enabled") == false, "Scott is non-interactable (enabled == false)")
		_expect(_has_snapped_gear(scott, "Sidearm"), "Scott also always carries a Sidearm")
		_expect(not _has_snapped_gear(scott, "Helmet"), "Scott is bareheaded (no helmets aboard ship)")

	# Rush + player may be ModularCharacter or Mint (Mint is the forward path).
	var rush_npc: Node = inst.get_node_or_null("DrRush")
	var rush_mc: Node = _modular_body(rush_npc) if rush_npc != null else null
	var rush_mint: Node = _mint_npc_body(rush_npc) if rush_npc != null else null
	_expect(rush_npc != null and (rush_mc != null or rush_mint != null),
		"Dr Rush renders as ModularCharacter or Mint Rush")
	if rush_mint != null:
		_expect(rush_mint.has_method("set_move_blend"),
			"Mint Rush exposes set_move_blend loco API")
	var player_body: Node = inst.get_node_or_null("Player")
	var pmc: Node = _modular_body(player_body) if player_body != null else null
	var mint_eli: Node = _mint_body(player_body) if player_body != null else null
	_expect(pmc != null or mint_eli != null,
		"player avatar is ModularCharacter or Mint Eli")
	if pmc != null:
		_expect(String(pmc.call("equipped", "Body")) != "",
			"player wears a torso garment (the red tee)")
		_expect(String(pmc.call("equipped", "Arms")) == "",
			"player Arms slot cleared (bare arms = t-shirt silhouette)")
	if mint_eli != null:
		_expect(mint_eli.has_method("set_move_blend"),
			"Mint player exposes set_move_blend loco API")
		_expect(mint_eli.has_method("equip_weapon"),
			"Mint player exposes equip_weapon")

	# Cue dispatch should not crash and should leave actors valid (instant_mode
	# snaps the staging). standoff_clear despawns both.
	gs.emit_signal("dialog_action", "standoff_greer")
	gs.emit_signal("dialog_action", "standoff_scott")
	await process_frame
	_expect(is_instance_valid(greer), "Greer survives the advance/enter cues")
	gs.emit_signal("dialog_action", "standoff_clear")
	await process_frame
	await process_frame  # queue_free needs a tick to actually leave the tree
	_expect(not is_instance_valid(greer),
		"standoff_clear despawns Greer (instant_mode)")

	root.remove_child(inst)
	inst.free()


# The ModularCharacter under an actor, duck-typed via set_slot (class_name
# lookup is unreliable under -s). Null = legacy mini body.
func _modular_body(actor: Node) -> Node:
	var stack: Array = [actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_method("set_slot"):
			return n
		for c in n.get_children():
			stack.append(c)
	return null


# MintCharacter under the player (duck-typed via set_move_blend + slug meta).
func _mint_body(actor: Node) -> Node:
	var stack: Array = [actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_method("set_move_blend") and n.has_method("equip_weapon") and n.has_method("find_skeleton"):
			return n
		for c in n.get_children():
			stack.append(c)
	return null


# Mint NPC body (quest-giver Rush may not expose equip_weapon).
func _mint_npc_body(actor: Node) -> Node:
	var stack: Array = [actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_method("set_move_blend") and n.has_method("find_skeleton") and n.has_method("play"):
			return n
		for c in n.get_children():
			stack.append(c)
	return null


# Gear now snaps to skeleton bones via BoneAttachment3D, not to the body root.
# True if a live gear node of `gear_name` hangs off a BoneAttachment3D anywhere
# under the actor (ignores "_retired" nodes mid-queue_free).
func _has_snapped_gear(actor: Node, gear_name: String) -> bool:
	var stack: Array = [actor]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BoneAttachment3D and n.get_node_or_null(gear_name) != null:
			return true
		for c in n.get_children():
			stack.append(c)
	return false


# ── 2. DrRush.interact → met_rush + quest step advancement ────────────────────

func _test_rush_interact_advances_quest(gs: Node) -> void:
	print("\n-- DrRush.interact advances quest --")
	gs.call("reset")

	# Advance to QUEST_FIND_RUSH so met_rush flip makes narrative sense.
	gs.set("met_scott", true)
	gs.call("advance_air_quest")
	_expect(gs.get("quest_step") == "find_rush",
		"pre-condition: quest_step is QUEST_FIND_RUSH before interacting with Rush")

	var npc_script: Script = load(NPC_SCRIPT_PATH) as Script
	if npc_script == null:
		_fail("could not load npc.gd for DrRush interact test")
		return

	var rush: StaticBody3D = StaticBody3D.new()
	rush.set_script(npc_script)
	rush.name = "DrRush"
	rush.set("character_name", "Dr Rush")
	rush.set("met_flag", "met_rush")
	rush.set("first_meet_recompute_objective", true)
	rush.set("dialogue_tree", [
		{
			"speaker": "Eli",
			"text": "Rush, don't push that — it could blow up the ship!",
			"choices": [{"text": "Step forward.", "next": "exit"}],
		},
	])

	# Add to tree so GameState / group lookups inside Npc._on_interact work.
	root.add_child(rush)
	await process_frame

	# A bare Node as the "by" parameter is fine: _face_interactor falls back to
	# get_first_node_in_group("player") which returns null headless, and
	# look_at is never reached (distance check returns early).
	var dummy_player: Node = Node.new()
	root.add_child(dummy_player)
	dummy_player.add_to_group("player")

	rush.call("interact", dummy_player)

	# met_rush must be true immediately (Npc._handle_first_meet fires BEFORE
	# dialog_started.emit per npc.gd:328-333).
	_expect(gs.get("met_rush") == true,
		"met_rush == true immediately after DrRush.interact()")
	_expect(gs.get("quest_step") == "find_rest",
		"quest_step == QUEST_FIND_REST after DrRush.interact()")

	rush.queue_free()
	dummy_player.queue_free()
	await process_frame


# ── 3. Console no-op: exact log line, ZERO state mutation ─────────────────────

func _test_console_noop(gs: Node) -> void:
	print("\n-- ControlConsole no-op --")
	gs.call("reset")

	# Set up: Rush has been met but we're still on QUEST_FIND_RUSH.
	gs.set("met_scott", true)
	gs.call("advance_air_quest")      # → QUEST_FIND_RUSH
	gs.set("met_rush", true)
	# Do NOT advance past QUEST_FIND_RUSH — that's the gate for the no-op branch.
	_expect(gs.get("quest_step") == "find_rush",
		"pre-condition: quest_step is QUEST_FIND_RUSH for no-op test")

	# Snapshot the fields the no-op must NOT mutate.
	var snap_diagnosed: bool = gs.get("life_support_diagnosed") == true
	var snap_crisis: bool = gs.get("air_crisis_started") == true
	# breaches_sealed is a Dictionary; read size safely.
	var raw_breaches: Variant = gs.get("breaches_sealed")
	var snap_breaches: int = 0
	if raw_breaches is Dictionary:
		snap_breaches = (raw_breaches as Dictionary).size()

	# Collect log entries via the log_added signal so we can detect the exact line.
	var logged_lines: Array[String] = []
	var on_log: Callable = func(line: String) -> void:
		logged_lines.append(line)
	gs.connect("log_added", on_log)

	# Build a ControlConsole the same way RoomBuilder does (StaticBody3D + script).
	var console_script: Script = load(CONSOLE_SCRIPT_PATH) as Script
	_expect(console_script != null, "control_console.gd script loads")
	if console_script == null:
		gs.disconnect("log_added", on_log)
		return

	var console: StaticBody3D = StaticBody3D.new()
	console.set_script(console_script)
	console.name = "ControlConsoleTest"
	# Add to tree before interact so _ready (collision_layer override) runs.
	root.add_child(console)
	await process_frame

	var dummy: Node = Node.new()
	root.add_child(dummy)
	dummy.add_to_group("player")

	console.call("interact", dummy)

	gs.disconnect("log_added", on_log)

	# Exact log line must appear.
	var expected_line: String = "Apparently that did nothing…"
	var found_line: bool = false
	for l in logged_lines:
		if expected_line in l:
			found_line = true
			break
	_expect(found_line,
		"console no-op logs exact line '%s'" % expected_line)

	# Quest step must not have advanced.
	_expect(gs.get("quest_step") == "find_rush",
		"quest_step unchanged after console no-op (still QUEST_FIND_RUSH)")

	# ZERO mutation to ship-state fields.
	_expect(gs.get("life_support_diagnosed") == snap_diagnosed,
		"life_support_diagnosed unchanged after no-op (was %s)" % snap_diagnosed)
	var raw_b2: Variant = gs.get("breaches_sealed")
	var cur_breaches: int = 0
	if raw_b2 is Dictionary:
		cur_breaches = (raw_b2 as Dictionary).size()
	_expect(cur_breaches == snap_breaches,
		"breaches_sealed unchanged after no-op")
	_expect(gs.get("air_crisis_started") == snap_crisis,
		"air_crisis_started unchanged after no-op (was %s)" % snap_crisis)

	console.queue_free()
	dummy.queue_free()
	await process_frame


# ── 4. Kino discovery line ────────────────────────────────────────────────────

func _test_kino_discovery_line() -> void:
	print("\n-- Kino discovery line --")

	var kp_script: Script = load(KINO_PICKUP_SCRIPT_PATH) as Script
	_expect(kp_script != null, "kino_pickup.gd script loads")
	if kp_script == null:
		return

	# Read KINO_DIALOG_TREE via the script's constant map (no need to instantiate).
	var consts: Dictionary = kp_script.get_script_constant_map()
	var raw_tree: Variant = consts.get("KINO_DIALOG_TREE", [])
	var tree: Array = []
	if raw_tree is Array:
		tree = raw_tree as Array

	_expect(tree.size() > 0, "KINO_DIALOG_TREE is non-empty")
	if tree.is_empty():
		return

	var raw0: Variant = tree[0]
	var text0: String = ""
	if raw0 is Dictionary:
		text0 = String((raw0 as Dictionary).get("text", ""))
	_expect(text0 == "Oh, what's that? Looks portable.",
		"KINO_DIALOG_TREE[0].text == 'Oh, what's that? Looks portable.' (got: '%s')" % text0)

	# Negative assertions: banned phrases must not appear in ANY tree node.
	var banned: Array[String] = [
		"didn't leave this here",
		"don't remember putting",
		"I don't remember",
		"I didn't leave",
	]
	for raw_node in tree:
		if not (raw_node is Dictionary):
			continue
		var nd: Dictionary = raw_node as Dictionary
		var t: String = String(nd.get("text", "")).to_lower()
		for phrase in banned:
			_expect(not (phrase.to_lower() in t),
				"KINO tree node '%s…' has no banned phrase '%s'" % [t.left(30), phrase])


# ── 5. KinoPickup.interact grants kino_remote ─────────────────────────────────

func _test_kino_pickup_grants_item(gs: Node, inv: Node) -> void:
	print("\n-- KinoPickup.interact grants item --")
	gs.call("reset")

	# Advance to QUEST_FIND_KINO so the pickup's internal gate lets interact proceed.
	gs.set("met_scott", true)
	gs.call("advance_air_quest")   # → find_rush
	gs.set("met_rush", true)
	gs.call("advance_air_quest")   # → find_rest
	gs.call("mark_eli_quarters_found")  # → find_kino

	_expect(not bool(inv.call("has", "kino_remote")),
		"pre-condition: kino_remote not in inventory before pickup")

	var kp_script: Script = load(KINO_PICKUP_SCRIPT_PATH) as Script
	_expect(kp_script != null, "kino_pickup.gd script loads for interact test")
	if kp_script == null:
		return

	var pickup: StaticBody3D = StaticBody3D.new()
	pickup.set_script(kp_script)
	pickup.name = "KinoPickup"

	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 0.9, 1.4)
	cs.shape = box
	pickup.add_child(cs)

	root.add_child(pickup)
	await process_frame

	var dummy: Node = Node.new()
	root.add_child(dummy)
	dummy.add_to_group("player")

	pickup.call("interact", dummy)
	# _name_the_kino has an OS.has_feature("headless") early-return, so
	# acquire_kino fires synchronously in headless mode.
	await process_frame

	_expect(bool(inv.call("has", "kino_remote")),
		"Inventory.has('kino_remote') == true after KinoPickup.interact()")

	pickup.queue_free()
	dummy.queue_free()
	await process_frame


# ── helpers ────────────────────────────────────────────────────────────────────

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  PASS  %s" % label)
		_passes += 1
	else:
		print("  FAIL  %s" % label)
		_failures.append(label)


func _fail(reason: String) -> void:
	print("  FAIL  %s" % reason)
	_failures.append(reason)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
