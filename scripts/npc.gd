class_name Npc
extends Interactable

# Talkable NPC. Cycles a list of dialogue lines into the HUD log on each
# interact, sets an optional GameState bool flag the first time it's spoken
# to, and can announce a new objective once the conversation kicks the
# player into the next quest beat.
#
# When `auto_greet` is true, the NPC tracks the player after entering the
# scene and walks toward them up to `auto_greet_distance`; once close enough,
# it fires its own first interact. Used so Lt Scott approaches the player
# during the arrival beat instead of waiting to be talked to.

@export var character_name: String = "NPC"
@export var dialogue_lines: Array[String] = []
# Choice-tree dialog. When set, takes precedence over dialogue_lines and routes
# through the full-screen DialogScreen (with portrait close-up + Fable-style
# choices) instead of a single HUD popup. See objects/dialog_screen.tscn.
# Each node is a Dictionary { speaker, text, choices: [{ text, next }] }.
# `next` is an integer index into the same tree, or the string "exit".
@export var dialogue_tree: Array = []
# Optional replacement after `met_flag` is already true. This keeps stateful
# NPCs from replaying first-meet exposition after a save/load or re-interact.
@export var repeat_dialogue_tree: Array = []
@export var met_flag: String = ""
@export var first_meet_objective: String = ""
# When set, the first interact also recomputes the objective via the
# matching GameState method. Avoids hardcoding objective text where the
# state machine already owns it.
@export var first_meet_recompute_objective: bool = false

# Auto-greet: walk toward the player and start the conversation without
# the player having to press E. Disabled by default; opt in per-NPC.
@export var auto_greet: bool = false
@export var auto_greet_distance: float = 2.4
@export var auto_greet_delay: float = 1.5
@export var auto_greet_speed: float = 1.8

var _line_index: int = 0
var _auto_greet_done: bool = false
var _auto_greet_t: float = 0.0

func _ready() -> void:
	super()
	# Interactable._ready() hard-sets collision_layer = 4 (interactable only).
	# Add layer 1 so the player capsule (mask = 1) can't walk through the NPC.
	collision_layer = 1 | 4
	if prompt == "Interact":
		prompt = "Talk to %s" % character_name
	# StaticBody3D nodes don't process by default. Only flip when auto-greet is
	# requested so passive NPCs (Rush) don't pay the per-frame cost.
	set_process(auto_greet)

func _process(delta: float) -> void:
	if not auto_greet or _auto_greet_done:
		return
	_auto_greet_t += delta
	if _auto_greet_t < auto_greet_delay:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Planar distance — we never want to chase vertically.
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist <= auto_greet_distance:
		_auto_greet_done = true
		set_process(false)
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
		_on_interact(player)
		return
	var step: float = min(auto_greet_speed * delta, dist - auto_greet_distance * 0.95)
	global_position += to_player.normalized() * step
	# Face the way we're walking so the model doesn't moonwalk.
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)

func _on_interact(_by: Node) -> void:
	# Choice-tree dialog takes precedence. The DialogScreen pauses the game,
	# zooms a portrait-camera onto this node, and routes choice picks back.
	var active_tree: Array = _active_dialogue_tree()
	if not active_tree.is_empty():
		if _line_index == 0 and not _has_met():
			_handle_first_meet()
		_line_index += 1
		GameState.dialog_started.emit(self, active_tree)
		return
	if dialogue_lines.is_empty():
		return
	var line: String = dialogue_lines[_line_index % dialogue_lines.size()]
	GameState.add_log("%s: %s" % [character_name, line])
	GameState.dialogue_shown.emit(character_name, line)
	if _line_index == 0:
		_handle_first_meet()
	_line_index += 1


# ---------------- Kenney GLB helpers --------------------------------------
#
# Two static utilities shared by gate_room.gd and room.gd when they instance
# a Mini Characters GLB. Live on npc.gd so the NPC class owns its own
# "make my model not white and not statue-still" idioms.

# Kenney "Mini Characters 1" GLBs reference an external colormap.png that
# Godot's GLB importer drops on import (see memory: glTF embedded texture
# lost). Walk the imported tree and slap a StandardMaterial3D using the
# palette atlas onto every MeshInstance3D — without this every mini-char
# renders as a solid white silhouette.
static func apply_kenney_colormap(root: Node, tex: Texture2D) -> void:
	if tex == null or root == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness = 0.78
	mat.metallic = 0.0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = mat
		for c in n.get_children():
			stack.append(c)


# Find the AnimationPlayer that Godot's glTF importer creates inside the
# instanced GLB (it lives one level deep, not at the wrapper root — see
# memory: glTF AnimationPlayer path), and start the first available
# animation (preferring one whose name contains "idle").
static func play_idle_animation(root: Node) -> void:
	if root == null:
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			var ap: AnimationPlayer = n
			var names: PackedStringArray = ap.get_animation_list()
			if names.is_empty():
				return
			var pick: String = ""
			for nm in names:
				if String(nm).to_lower().contains("idle"):
					pick = String(nm)
					break
			if pick == "":
				pick = String(names[0])
			ap.play(pick)
			return
		for c in n.get_children():
			stack.append(c)

func _handle_first_meet() -> void:
	if met_flag != "" and not bool(GameState.get(met_flag)):
		GameState.set(met_flag, true)
		# Story milestones get logged once so the journal records them.
		GameState.add_log("Met %s." % character_name)
		if first_meet_recompute_objective and GameState.has_method("_recompute_objective"):
			GameState.call("_recompute_objective")
		elif first_meet_objective != "":
			GameState.set_objective(first_meet_objective)
		# Rush completes the story arc — re-check episode completion.
		if GameState.has_method("check_episode_complete"):
			GameState.check_episode_complete()

func _has_met() -> bool:
	return met_flag != "" and bool(GameState.get(met_flag))

func _active_dialogue_tree() -> Array:
	if _has_met() and not repeat_dialogue_tree.is_empty():
		return repeat_dialogue_tree
	return dialogue_tree
