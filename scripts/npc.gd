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
#
# Independently of interaction, an NPC with `ambient_lines` (and optionally
# `alert_lines`) pops a passive over-the-head speech bubble when the player
# wanders near — small personality-flavored chatter ("Hey, Eli.") that swaps to
# the alert pool ("What's that alarm?!") while the ship's red alert is active.
# See issue #35 / the "Passive ambient chat bubbles" section below.

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

# Passive ambient chatter (issue #35). When the player wanders within
# `ambient_bubble_distance` an over-the-head speech bubble pops up with a
# personality-flavored one-liner — no interaction needed. These pools give
# each NPC their own voice; the bubble auto-clears after `ambient_bubble_hold`
# seconds and won't re-trigger until `ambient_bubble_cooldown` has elapsed so
# a parked player isn't spammed. `alert_lines` (if any) take precedence
# whenever the ship's red alert is active, so soldiers react to the hull alarm
# instead of small-talking. All optional — an NPC with no pools stays silent.
@export var ambient_lines: Array[String] = []
@export var alert_lines: Array[String] = []
@export var ambient_bubble_distance: float = 4.0
@export var ambient_bubble_hold: float = 3.2
@export var ambient_bubble_cooldown: float = 8.0

# Negotiation trades (issue #90). When a dialog-tree node carries an
# `action: "trade:<resource>:<amount>"` and the player picks it, this NPC grants
# that resource ONCE. Completed trades are tracked in ONE registry keyed by the
# full action string (NOT a per-trade bool) so a resident who offers several
# trades can't be milked and the set stays save-round-trippable.
var _trades_done: Dictionary = {}

var _line_index: int = 0
# Ambient-bubble runtime. _ambient_t accumulates since the last bubble; the
# Label3D is created lazily on first show. _ambient_index walks the pool so an
# NPC cycles its lines (deterministic + testable) rather than repeating one.
var _ambient_bubble: Label3D = null
var _ambient_t: float = 0.0
var _ambient_visible_t: float = 0.0
var _ambient_index: int = 0
var _ambient_alert_index: int = 0
var _ambient_shown: bool = false
var _auto_greet_done: bool = false
var _auto_greet_t: float = 0.0
# walk_to: a one-shot scripted stroll to an absolute world target (used by the
# returned away-team fan-out). Independent of auto_greet — when armed, _process
# steps toward _walk_target and disarms on arrival. Driven planar; never tips
# the model. Stagger via _walk_delay so a trio fans out instead of marching.
var _walking_to: bool = false
var _walk_target: Vector3 = Vector3.ZERO
var _walk_speed: float = 2.5
var _walk_delay: float = 0.0
var _walk_t: float = 0.0
# Facing-restore: when a conversation starts we turn to face the player and
# remember the prior rotation, then ease back to it when the dialog closes so
# the NPC resumes facing their console / panel / patrol heading.
var _facing_player: bool = false
var _pre_talk_rotation: Vector3 = Vector3.ZERO

func _ready() -> void:
	super()
	# Interactable._ready() hard-sets collision_layer = 4 (interactable only).
	# Add layer 1 so the player capsule (mask = 1) can't walk through the NPC.
	collision_layer = 1 | 4
	if prompt == "Interact":
		prompt = "Talk to %s" % character_name
	# StaticBody3D nodes don't process by default. Flip on when auto-greet OR
	# ambient chatter is requested so passive NPCs without either stay free of
	# the per-frame cost.
	set_process(auto_greet or _has_ambient_chatter())
	# Start the cooldown part-way in so NPCs don't all bark the instant the
	# scene loads with the player nearby — stagger via the pool size.
	_ambient_t = float(_ambient_index) * 0.7
	# Resume previously-captured dialogue progress / placement if this NPC
	# has been saved before. NPCState gates on node name (stable as long as
	# the scene's NPC isn't renamed). On a fresh spawn this just records
	# the initial values for later round-tripping. Autoload-tolerant: the
	# scene_boot smoke test loads scenes in -s mode with no autoloads.
	var ns: Node = get_node_or_null("/root/NPCState")
	if ns != null and ns.has_method("restore_or_register"):
		ns.call("restore_or_register", self)

# Arm a scripted walk to an absolute world point. `delay` staggers the start so
# a group fans out smoothly rather than moving in lockstep. Flips on _process.
# Safe to call before or after _ready (only touches state + set_process).
func walk_to(target: Vector3, speed: float = 2.5, delay: float = 0.0) -> void:
	_walk_target = target
	_walk_speed = maxf(0.1, speed)
	_walk_delay = maxf(0.0, delay)
	_walk_t = 0.0
	_walking_to = true
	set_process(true)


func _process(delta: float) -> void:
	if _walking_to:
		_step_walk(delta)
	# Passive chatter runs for any NPC with a pool, independent of auto-greet.
	if _has_ambient_chatter():
		_step_ambient(delta)
	# Auto-greet is the only other reason to keep processing once the walk is
	# done; bail (and stop processing if nothing else needs it) otherwise.
	if not auto_greet or _auto_greet_done:
		if not _walking_to and not _has_ambient_chatter():
			set_process(false)
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
		if not _has_ambient_chatter():
			set_process(false)
		look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)
		_on_interact(player)
		return
	var step: float = min(auto_greet_speed * delta, dist - auto_greet_distance * 0.95)
	global_position += to_player.normalized() * step
	# Face the way we're walking so the model doesn't moonwalk.
	look_at(Vector3(player.global_position.x, global_position.y, player.global_position.z), Vector3.UP)


# --------------- Passive ambient chat bubbles (issue #35) ------------------

func _has_ambient_chatter() -> bool:
	return not ambient_lines.is_empty() or not alert_lines.is_empty()


# One frame of ambient-bubble logic. Holds a visible bubble for
# `ambient_bubble_hold`, then hides it; once `ambient_bubble_cooldown` has
# elapsed and the player is within range, pops a fresh line. Headless/instant
# runs (no player, no frames) simply never trigger — the bubble is cosmetic.
func _step_ambient(delta: float) -> void:
	if _ambient_shown:
		_ambient_visible_t += delta
		if _ambient_visible_t >= ambient_bubble_hold:
			_hide_ambient_bubble()
		return
	_ambient_t += delta
	if _ambient_t < ambient_bubble_cooldown:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > ambient_bubble_distance:
		return
	var line: String = next_ambient_line()
	if line == "":
		return
	show_ambient_bubble(line)


# Choose the next ambient line, context-aware: when the ship's red alert is
# active and this NPC has alert_lines, draw from that pool; otherwise cycle the
# normal ambient pool. Each pool advances its own cursor so lines rotate
# deterministically (testable). Returns "" when no pool applies.
#
# `alert_active` is injectable so tests can drive both branches without standing
# up the GameState autoload (ShipAlert reads the bare GameState singleton, which
# does not exist under -s). When -1 (default) we resolve it ourselves.
func next_ambient_line(alert_active: int = -1) -> String:
	var alerted: bool = (alert_active == 1) if alert_active >= 0 else _is_alert_active()
	if alerted and not alert_lines.is_empty():
		var l: String = alert_lines[_ambient_alert_index % alert_lines.size()]
		_ambient_alert_index += 1
		return l
	if ambient_lines.is_empty():
		return ""
	var line: String = ambient_lines[_ambient_index % ambient_lines.size()]
	_ambient_index += 1
	return line


# Autoload-tolerant alert check — ShipAlert reads the GameState autoload, which
# is absent in -s scene-boot runs. The bare GameState identifier won't even
# resolve there, so gate the whole call behind the autoload's presence: no
# autoload means "no alert".
func _is_alert_active() -> bool:
	if get_node_or_null("/root/GameState") == null:
		return false
	return ShipAlert.is_alert_active()


# Pop a speech bubble with `text` over the NPC's head. Lazily builds the Label3D
# (a billboarded panel-ish caption above the nametag). Public so tests/cinematics
# can force a bubble without waiting for proximity.
func show_ambient_bubble(text: String) -> void:
	if _ambient_bubble == null:
		_ambient_bubble = _build_ambient_bubble()
		add_child(_ambient_bubble)
	_ambient_bubble.text = text
	_ambient_bubble.visible = true
	_ambient_shown = true
	_ambient_visible_t = 0.0


func _hide_ambient_bubble() -> void:
	_ambient_shown = false
	_ambient_t = 0.0
	_ambient_visible_t = 0.0
	if _ambient_bubble != null:
		_ambient_bubble.visible = false


# True while a bubble is on screen — handy for tests/HUD.
func is_ambient_bubble_visible() -> bool:
	return _ambient_shown


func _build_ambient_bubble() -> Label3D:
	var b: Label3D = Label3D.new()
	b.name = "AmbientBubble"
	# Sit above the nametag (which lives at y=2.0) so the two don't overlap.
	b.position = Vector3(0.0, 2.42, 0.0)
	b.pixel_size = 0.0038
	b.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.shaded = false
	b.double_sided = true
	b.outline_size = 8
	b.modulate = Color(0.82, 0.94, 1.0, 1.0)
	b.outline_modulate = Color(0.02, 0.05, 0.09, 0.9)
	b.width = 420.0
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b

# One frame of a scripted walk toward _walk_target. Planar step at _walk_speed,
# smooth yaw toward travel, arrive within 0.3 m. Mirrors Companion._step_toward
# but moves the body via global_position (NPCs are StaticBody3D, no physics
# integration) — same trick auto_greet already uses.
func _step_walk(delta: float) -> void:
	_walk_t += delta
	if _walk_t < _walk_delay:
		_set_npc_clip("idle")
		return
	var to_t: Vector3 = _walk_target - global_position
	to_t.y = 0.0
	var dist: float = to_t.length()
	if dist <= 0.3:
		_walking_to = false
		_set_npc_clip("idle")
		return
	var dir: Vector3 = to_t.normalized()
	var step: float = min(_walk_speed * delta, dist)
	global_position += dir * step
	# Face travel direction (Kenney mini-char convention handled by look_at).
	var look: Vector3 = global_position + dir
	look.y = global_position.y
	if global_position.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
	_set_npc_clip("walk")


# Switch the GLB AnimationPlayer to a clip whose name contains `clip` (walk /
# idle). No-ops if the model or a matching clip is absent.
func _set_npc_clip(clip: String) -> void:
	var ap: AnimationPlayer = _find_anim_player(self)
	if ap == null:
		return
	for nm in ap.get_animation_list():
		if String(nm).to_lower().contains(clip):
			if ap.current_animation != String(nm):
				ap.play(String(nm))
			return


func _find_anim_player(root: Node) -> AnimationPlayer:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			return n as AnimationPlayer
		for c in n.get_children():
			stack.append(c)
	return null


func _on_interact(by: Node) -> void:
	# Choice-tree dialog takes precedence. The DialogScreen pauses the game,
	# zooms a portrait-camera onto this node, and routes choice picks back.
	var active_tree: Array = _active_dialogue_tree()
	if not active_tree.is_empty():
		# Turn to face the player for the conversation; restore the prior facing
		# when it closes (otherwise NPCs freeze facing the player forever).
		_begin_conversation_facing(by)
		if _line_index == 0 and not _has_met():
			_handle_first_meet()
		_line_index += 1
		_notify_npc_state_update()
		GameState.dialog_started.emit(self, active_tree)
		return
	if dialogue_lines.is_empty():
		return
	_face_interactor(by)
	var line: String = dialogue_lines[_line_index % dialogue_lines.size()]
	GameState.add_log("%s: %s" % [character_name, line])
	GameState.dialogue_shown.emit(character_name, line)
	if _line_index == 0:
		_handle_first_meet()
	_line_index += 1
	_notify_npc_state_update()


# Notify the NPCState autoload to capture this NPC's current state. Safe
# to call when NPCState is absent (scene_boot.gd loads scenes in -s mode
# with no autoloads).
func _notify_npc_state_update() -> void:
	var ns: Node = get_node_or_null("/root/NPCState")
	if ns != null and ns.has_method("update"):
		ns.call("update", self)


# Serialization contract used by NPCState. Captures every per-instance
# value that diverges from the scene-authored defaults during play.
func get_save_state() -> Dictionary:
	return {
		"line_index": _line_index,
		"auto_greet_done": _auto_greet_done,
		"trades_done": _trades_done.keys(),
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
	}


func apply_save_state(s: Dictionary) -> void:
	_line_index = int(s.get("line_index", 0))
	_auto_greet_done = s.get("auto_greet_done", false) == true
	_trades_done.clear()
	var td: Variant = s.get("trades_done", [])
	if td is Array:
		for k in (td as Array):
			_trades_done[String(k)] = true
	var pos_raw: Variant = s.get("pos", null)
	if pos_raw is Array and (pos_raw as Array).size() == 3:
		var arr: Array = pos_raw
		global_position = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	if s.has("yaw"):
		rotation.y = float(s["yaw"])
	# Once auto_greet has fired, never replay it on resume — otherwise an
	# already-greeted NPC walks back over to the player again on reload.
	if _auto_greet_done:
		set_process(false)


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

# Yaw to face the interacting player (planar only — never tip the model). Falls
# back to the player group if `by` isn't a Node3D. look_at needs us in the tree
# (we are, on interact) and a non-coincident target.
func _face_interactor(by: Node) -> void:
	var target: Node3D = by as Node3D
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if target == null:
		return
	var flat: Vector3 = Vector3(target.global_position.x, global_position.y, target.global_position.z)
	if global_position.distance_to(flat) < 0.05:
		return
	look_at(flat, Vector3.UP)


# Start a face-to-face conversation: remember our prior rotation (once), turn to
# the player, and arm a one-shot restore on dialog close.
func _begin_conversation_facing(by: Node) -> void:
	if not _facing_player:
		_pre_talk_rotation = rotation
		_facing_player = true
	_face_interactor(by)
	if not GameState.dialog_closed.is_connected(_on_talk_ended):
		GameState.dialog_closed.connect(_on_talk_ended, CONNECT_ONE_SHOT)
	# Negotiation: while THIS NPC's dialog is open, listen for trade actions a
	# choice fires (DialogScreen emits GameState.dialog_action with the picked
	# choice's `action`). Hooked here so only the active conversation's NPC reacts.
	if not GameState.dialog_action.is_connected(_on_dialog_action):
		GameState.dialog_action.connect(_on_dialog_action)


# A dialog node fired an action while talking to this NPC. A
# "trade:<resource>:<amount>" action grants that resource once — the negotiation
# payoff (issue #90). Any other action id is ignored here (other systems hook the
# same signal for their own ids — scrubber_rush, etc.).
func _on_dialog_action(action_id: String) -> void:
	if action_id.begins_with("trade:"):
		var parts: PackedStringArray = action_id.split(":")
		if parts.size() >= 3:
			grant_trade(String(parts[1]), int(parts[2]))


# Grant a negotiated resource ONCE per (resource, amount) trade. Routes through
# GameState.add_resource so the count, log line, and resource_changed signal all
# fire normally. Returns true only on the first successful grant. Public so a
# test (or cinematic) can drive the negotiation payoff directly.
func grant_trade(resource: String, amount: int) -> bool:
	if resource == "" or amount <= 0:
		return false
	var key: String = "%s:%d" % [resource, amount]
	if _trades_done.has(key):
		return false
	_trades_done[key] = true
	_notify_npc_state_update()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return true
	if gs.has_method("add_resource"):
		gs.call("add_resource", resource, amount, "trade with %s" % character_name)
	return true


# Dialog closed — ease back to the pre-talk facing over the shortest arc so the
# NPC resumes what they were doing (their idle animation never stopped).
func _on_talk_ended() -> void:
	# Drop the negotiation hook so only the NPC currently being talked to reacts
	# to a trade action (the conversation just closed).
	if GameState.dialog_action.is_connected(_on_dialog_action):
		GameState.dialog_action.disconnect(_on_dialog_action)
	if not _facing_player:
		return
	_facing_player = false
	if not is_inside_tree():
		return
	rotation.x = _pre_talk_rotation.x
	rotation.z = _pre_talk_rotation.z
	var target_y: float = rotation.y + wrapf(_pre_talk_rotation.y - rotation.y, -PI, PI)
	var tween: Tween = create_tween()
	tween.tween_property(self, "rotation:y", target_y, 0.45).set_trans(Tween.TRANS_SINE)

func _handle_first_meet() -> void:
	if met_flag != "" and not GameState.get(met_flag):
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
	return met_flag != "" and GameState.get(met_flag) == true

func _active_dialogue_tree() -> Array:
	if _has_met() and not repeat_dialogue_tree.is_empty():
		return repeat_dialogue_tree
	return dialogue_tree
