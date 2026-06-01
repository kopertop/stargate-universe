extends Node

# Headless smoke test for the Urban/suburban biome — negotiation flavor
# (issue #90). Runs as a SCENE (autoloads active) because npc.gd references the
# GameState autoload singleton (won't compile under a bare -s script — same
# reason npc_chat rides the scene path) and the trade payoff grants via
# GameState.add_resource.
#
#   godot --headless --quit-after 900 res://tests/smoke/biome_urban.tscn
#
# Asserts the acceptance criteria:
#   1. Urban renders from a spec, is WALKABLE (streets — no jump anywhere
#      reachable), and seats graybox settlement buildings.
#   2. Negotiation NPCs spawn (group "negotiation_npc") each carrying a valid
#      choice-tree dialogue (npc.gd dialogue_tree, the existing DialogScreen UI).
#   3. At least one resident offers a trade that yields a needed resource, and
#      driving that trade action grants the resource exactly once (no re-milking).
#   4. Settlement + residents are URBAN-ONLY (desert places none) and DATA-DRIVEN
#      (a spec hazard_params override changes the placed counts).
#
# Duck-types PlanetGenerator via its script path so a freshly-added class_name
# can't parse-error this run (feedback_godot_class_name_headless.md).

const GEN_PATH: String = "res://scripts/planet_generator.gd"

const FLOOR_MAX_ANGLE_DEG: float = 45.0
const WALKABLE_MARGIN_DEG: float = 40.0

var _gen: Script = null
var _failures: Array[String] = []
var _passes: int = 0


func _ready() -> void:
	print("=== biome_urban smoke test ===")
	_gen = load(GEN_PATH)
	_expect(_gen != null, "PlanetGenerator script loads")
	if _gen == null:
		_report()
		return

	_test_urban_renders_walkable_with_buildings()
	_test_negotiation_npcs_spawn_with_dialogue_trees()
	_test_a_trade_yields_a_resource_once()
	_test_trade_choice_press_through_dialog_screen_grants()
	_test_urban_only_and_data_driven()

	_report()


# --- 1: urban renders, walkable streets, settlement buildings ---------------
func _test_urban_renders_walkable_with_buildings() -> void:
	var spec: Dictionary = _spec(424242, "urban")
	var params: Dictionary = _gen.build_params(spec)
	var slope: float = _gen.max_slope_deg(params, 240.0, 2.0)
	_expect(slope < WALKABLE_MARGIN_DEG,
		"urban max slope %.1f° < %.0f° (walkable streets, no jump)" % [slope, WALKABLE_MARGIN_DEG])
	_expect(slope < FLOOR_MAX_ANGLE_DEG, "urban slope under CharacterBody3D floor limit")

	var world: Node3D = Node3D.new()
	add_child(world)
	var manager: Node = _gen.build(world, spec)
	_expect(manager != null, "urban build() returns a chunk manager")
	_expect(world.get_node_or_null("PlanetGround") != null, "urban installs PlanetGround terrain")
	_expect(world.get_node_or_null("PlanetReturnStargate") != null, "urban places return Stargate")
	var buildings: int = _count_prefix(world, "Building")
	_expect(buildings > 0, "urban seats graybox settlement buildings (%d)" % buildings)
	world.queue_free()


# --- 2: negotiation NPCs spawn with valid dialogue trees --------------------
func _test_negotiation_npcs_spawn_with_dialogue_trees() -> void:
	var spec: Dictionary = _spec(7, "urban")
	var neg: Dictionary = _gen.negotiation_block(spec)
	_expect(not neg.is_empty(), "urban biome defines a negotiation block")
	var want: int = min(int(neg.get("npc_count", 0)),
		(neg.get("residents", []) as Array).size() if neg.get("residents", []) is Array else 0)
	_expect(want > 0, "negotiation block names residents (%d)" % want)

	var world: Node3D = Node3D.new()
	add_child(world)
	_gen.build(world, spec)
	var residents: Array = world.get_tree().get_nodes_in_group("negotiation_npc")
	# Filter to this world (group is global; other worlds may linger pre-free).
	var mine: Array = []
	for n in residents:
		if (n as Node).get_parent() == world:
			mine.append(n)
	_expect(mine.size() == want, "urban spawns the data-driven NPC count (%d == %d)" % [mine.size(), want])
	_expect(mine.size() > 0, "urban spawns negotiation NPCs")

	var with_trees: int = 0
	for n in mine:
		var tree: Array = n.get("dialogue_tree")
		if tree is Array and not tree.is_empty():
			with_trees += 1
			# A valid tree: every node has a speaker + at least one choice.
			var node0: Dictionary = tree[0]
			_expect(String(node0.get("speaker", "")) != "", "resident dialogue node has a speaker")
			_expect((node0.get("choices", []) as Array).size() > 0, "resident dialogue node offers choices")
	_expect(with_trees == mine.size(), "every negotiation NPC carries a choice-tree dialogue")
	world.queue_free()


# --- 3: a trade yields a needed resource, granted exactly once --------------
func _test_a_trade_yields_a_resource_once() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	_expect(gs != null, "GameState autoload attached")
	if gs == null:
		return
	gs.call("reset")

	var spec: Dictionary = _spec(7, "urban")
	var world: Node3D = Node3D.new()
	add_child(world)
	_gen.build(world, spec)

	# Find a resident that offers a trade (its dialogue carries a trade action).
	var trader: Node = null
	var trade_resource: String = ""
	var trade_amount: int = 0
	for n in world.get_tree().get_nodes_in_group("negotiation_npc"):
		if (n as Node).get_parent() != world:
			continue
		var info: Dictionary = _find_trade_action(n.get("dialogue_tree"))
		if not info.is_empty():
			trader = n
			trade_resource = String(info.get("resource", ""))
			trade_amount = int(info.get("amount", 0))
			break
	_expect(trader != null, "at least one resident offers a trade action")
	if trader == null:
		world.queue_free()
		return
	_expect(trade_resource != "" and trade_amount > 0,
		"trade action names a resource + amount (%s x%d)" % [trade_resource, trade_amount])

	var before: int = int(gs.call("resource_count", trade_resource))
	# Drive the negotiation payoff directly (grant_trade is what the dialog
	# action path calls — npc.gd::_on_dialog_action parses "trade:res:amt").
	var granted: bool = trader.call("grant_trade", trade_resource, trade_amount)
	_expect(granted == true, "first trade grants the resource")
	var after: int = int(gs.call("resource_count", trade_resource))
	_expect(after == before + trade_amount,
		"trade adds the resource (%d -> %d, +%d)" % [before, after, trade_amount])

	# A second attempt of the SAME trade must NOT grant again (no milking).
	var again: bool = trader.call("grant_trade", trade_resource, trade_amount)
	_expect(again == false, "repeating the same trade does not grant twice")
	_expect(int(gs.call("resource_count", trade_resource)) == after,
		"resource count unchanged after a repeated trade")

	# The action-string path (what DialogScreen emits) reaches the same grant.
	var fresh: Node = null
	for n in world.get_tree().get_nodes_in_group("negotiation_npc"):
		if (n as Node).get_parent() == world and n != trader:
			var info2: Dictionary = _find_trade_action(n.get("dialogue_tree"))
			if not info2.is_empty():
				fresh = n
				break
	if fresh != null:
		var info3: Dictionary = _find_trade_action(fresh.get("dialogue_tree"))
		var res2: String = String(info3.get("resource", ""))
		var amt2: int = int(info3.get("amount", 0))
		var b2: int = int(gs.call("resource_count", res2))
		fresh.call("_on_dialog_action", "trade:%s:%d" % [res2, amt2])
		_expect(int(gs.call("resource_count", res2)) == b2 + amt2,
			"dialog action 'trade:%s:%d' grants via the action path" % [res2, amt2])
	world.queue_free()


# --- 3b: REAL UI path — press the trade choice button in DialogScreen --------
# Regression for the choice-level-action drop (PR #120 review): the authored
# trade lives on a CHOICE object, and the only player-reachable path is a button
# press inside DialogScreen. This drives that exact path — instantiate the real
# DialogScreen, render the trader's tree, walk to the trade node, and press its
# choice button — and asserts the resource is granted. It must FAIL if
# DialogScreen drops choice-level actions (which it did before the fix).
func _test_trade_choice_press_through_dialog_screen_grants() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		_expect(false, "GameState autoload attached (dialog-screen path)")
		return
	gs.call("reset")

	var spec: Dictionary = _spec(7, "urban")
	var world: Node3D = Node3D.new()
	add_child(world)
	_gen.build(world, spec)

	# Find a trader whose tree has a CHOICE carrying a trade action (the broken path).
	var trader: Node = null
	var trade_path: Dictionary = {}
	for n in world.get_tree().get_nodes_in_group("negotiation_npc"):
		if (n as Node).get_parent() != world:
			continue
		var path: Dictionary = _find_choice_trade(n.get("dialogue_tree"))
		if not path.is_empty():
			trader = n
			trade_path = path
			break
	_expect(trader != null, "a resident carries a trade action ON A CHOICE (the UI path)")
	if trader == null:
		world.queue_free()
		return

	var resource: String = String(trade_path.get("resource", ""))
	var amount: int = int(trade_path.get("amount", 0))
	# Isolate from prior tests/NPCState: same-named residents can restore a
	# `_trades_done` registry, which would block the grant and mask the press path.
	trader.set("_trades_done", {})
	var before: int = int(gs.call("resource_count", resource))

	# Wire the trader to the dialog_action channel exactly as a live conversation
	# does (npc.gd::_begin_conversation_facing). This is the listener that grants.
	var listener: Callable = Callable(trader, "_on_dialog_action")
	if not gs.is_connected("dialog_action", listener):
		gs.connect("dialog_action", listener)

	# Instance the REAL DialogScreen (same scene hud.gd loads) and start it.
	var dlg_scene: PackedScene = load("res://objects/dialog_screen.tscn")
	_expect(dlg_scene != null, "dialog_screen.tscn loads")
	if dlg_scene == null:
		world.queue_free()
		return
	var screen: Control = dlg_scene.instantiate()
	add_child(screen)
	var tree: Array = trader.get("dialogue_tree")
	screen.call("start", trader, tree)

	# Walk the rendered nodes to the one whose choice carries the trade action,
	# pressing the choice button that advances toward it. We re-render by pressing
	# buttons (the real input path), then press the trade choice itself.
	var pressed_trade: bool = _press_to_trade_choice(screen, tree)
	_expect(pressed_trade, "navigated DialogScreen to the trade choice and pressed it")

	# Pressing the trade choice button must have fired its action -> grant.
	var after: int = int(gs.call("resource_count", resource))
	_expect(after == before + amount,
		"pressing the trade CHOICE button grants %s (%d -> %d, +%d)" % [resource, before, after, amount])

	# Cleanup: unpause (DialogScreen pauses on start), drop the listener, free.
	get_tree().paused = false
	if gs.is_connected("dialog_action", listener):
		gs.disconnect("dialog_action", listener)
	if is_instance_valid(screen):
		screen.queue_free()
	world.queue_free()


# Navigate the live DialogScreen by pressing choice buttons until we reach and
# press the choice carrying a "trade:" action. Returns true if we pressed it.
# Bounded by the node count so a malformed tree can't loop forever.
func _press_to_trade_choice(screen: Control, tree: Array) -> bool:
	var box: VBoxContainer = screen.get_node_or_null("Window/Margin/VBox/ChoicesVBox")
	if box == null:
		return false
	for _step in range(tree.size() + 2):
		var idx: int = int(screen.get("_current_index"))
		if idx < 0 or idx >= tree.size():
			return false
		var node: Dictionary = tree[idx]
		var choices: Array = node.get("choices", [])
		var trade_btn: int = -1
		var advance_btn: int = -1
		for i in range(choices.size()):
			var c: Dictionary = choices[i]
			if String(c.get("action", "")).begins_with("trade:"):
				trade_btn = i
				break
			# Prefer a choice that jumps deeper (toward the trade node).
			var nxt: Variant = c.get("next")
			var is_num: bool = typeof(nxt) == TYPE_FLOAT or typeof(nxt) == TYPE_INT
			if advance_btn < 0 and is_num and int(nxt) > idx:
				advance_btn = i
		var press: int = trade_btn if trade_btn >= 0 else advance_btn
		if press < 0 or press >= box.get_child_count():
			return false
		(box.get_child(press) as Button).emit_signal("pressed")
		if trade_btn >= 0:
			return true
	return false


# --- 4: urban-only + data-driven --------------------------------------------
func _test_urban_only_and_data_driven() -> void:
	# Desert places NO settlement / negotiation content.
	var desert_world: Node3D = Node3D.new()
	add_child(desert_world)
	_gen.build(desert_world, _spec(7, "desert"))
	_expect(_count_prefix(desert_world, "Building") == 0, "desert places no settlement buildings")
	var desert_npcs: int = 0
	for n in desert_world.get_tree().get_nodes_in_group("negotiation_npc"):
		if (n as Node).get_parent() == desert_world:
			desert_npcs += 1
	_expect(desert_npcs == 0, "desert places no negotiation NPCs")
	desert_world.queue_free()

	# A spec hazard_params override changes the placed building count — proves the
	# settlement is data-driven, not hardcoded.
	var base: Dictionary = _gen.settlement_block(_spec(7, "urban"))
	var base_count: int = int(base.get("building_count", 0))
	_expect(base_count > 0, "baseline urban building count from data (%d)" % base_count)
	var tuned: Dictionary = _spec(7, "urban")
	tuned["hazard_params"] = {"settlement": {"building_count": base_count + 6,
		"min_radius": 18.0, "max_radius": 130.0}}
	var tuned_world: Node3D = Node3D.new()
	add_child(tuned_world)
	_gen.build(tuned_world, tuned)
	_expect(_count_prefix(tuned_world, "Building") == base_count + 6,
		"spec override changes the placed building count (%d)" % _count_prefix(tuned_world, "Building"))
	tuned_world.queue_free()


# --- helpers ----------------------------------------------------------------
func _spec(seed: int, biome: String) -> Dictionary:
	return {
		"seed": seed,
		"biome": biome,
		"resource_table": {"lime_nodes": 4, "lime_per_node": 1,
			"lime_min_radius": 50.0, "lime_max_radius": 120.0},
		"hazard_params": {},
		"name": "Test %s" % biome,
	}


# Walk a dialogue tree for the first node carrying a "trade:<res>:<amt>" action
# (on a node directly or one of its choices). Returns {resource, amount} or {}.
func _find_trade_action(tree: Variant) -> Dictionary:
	if not (tree is Array):
		return {}
	for node in (tree as Array):
		if not (node is Dictionary):
			continue
		var candidates: Array = [String((node as Dictionary).get("action", ""))]
		for c in (node as Dictionary).get("choices", []):
			if c is Dictionary:
				candidates.append(String((c as Dictionary).get("action", "")))
		for a in candidates:
			if String(a).begins_with("trade:"):
				var parts: PackedStringArray = String(a).split(":")
				if parts.size() >= 3:
					return {"resource": String(parts[1]), "amount": int(parts[2])}
	return {}


# Like _find_trade_action but ONLY considers actions on CHOICE objects (the
# player-reachable UI path). Returns {resource, amount} or {}.
func _find_choice_trade(tree: Variant) -> Dictionary:
	if not (tree is Array):
		return {}
	for node in (tree as Array):
		if not (node is Dictionary):
			continue
		for c in (node as Dictionary).get("choices", []):
			if not (c is Dictionary):
				continue
			var a: String = String((c as Dictionary).get("action", ""))
			if a.begins_with("trade:"):
				var parts: PackedStringArray = a.split(":")
				if parts.size() >= 3:
					return {"resource": String(parts[1]), "amount": int(parts[2])}
	return {}


func _count_prefix(world: Node, prefix: String) -> int:
	var n: int = 0
	for c in world.get_children():
		if String(c.name).begins_with(prefix):
			n += 1
	return n


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
		get_tree().quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		get_tree().quit(1)
