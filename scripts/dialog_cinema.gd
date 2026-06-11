extends Node

# Fable-style conversation presentation (user design goal, 2026-06-11):
# the participants face each other and a pause-immune over-the-shoulder
# camera SHIFTS TO WHOEVER IS SPEAKING; when it's the player's turn to pick
# a response the camera frames ELI with the floating choice list beside him.
#
# Spawned by DialogScreen in live play only — never under instant_mode and
# never for radio/self dialogs (where the dialog target IS the player).
# DialogScreen keeps owning the tree/choices/pause; this node owns the
# camera, the face-each-other staging, and the talk/idle clip swap. The
# SceneTree is paused during dialogs, so the camera rig is PROCESS_MODE_ALWAYS
# and the participants' MODEL subtrees (not their logic scripts) are flipped
# to ALWAYS so their animations keep breathing.

const CameraRigScript: Script = preload("res://scripts/standoff_camera.gd")

var _rig: Node3D = null
var _npc: Node3D = null
var _player: Node3D = null
# Model subtrees flipped to ALWAYS for the conversation: [node, prior_mode].
var _restored_modes: Array = []
var _last_speaker: Node3D = null
# Participant nametags hidden for the close-up (the subtitle names the
# speaker; a billboard label fills half the frame at OTS range).
var _hidden_tags: Array = []


func begin(npc: Node3D, player: Node3D) -> void:
	_npc = npc
	_player = player
	# Square the player up to the NPC (the NPC already turns via
	# _begin_conversation_facing; the player never did).
	if _player != null and _npc != null:
		var to_npc: Vector3 = _npc.global_position - _player.global_position
		to_npc.y = 0.0
		if to_npc.length() > 0.05:
			_player.rotation.y = atan2(-to_npc.x, -to_npc.z)
	# Keep both bodies animating through the pause (Model subtrees only —
	# never the NPC's logic script, which would run ambient chatter mid-talk).
	for actor in [_npc, _player]:
		var model: Node = actor.get_node_or_null("Model") if actor != null else null
		if model == null and actor != null:
			model = actor.get_node_or_null("Character")   # the player's wrapper
		if model != null:
			_restored_modes.append([model, model.process_mode])
			model.process_mode = Node.PROCESS_MODE_ALWAYS
	for actor in [_npc, _player]:
		var tag: Node = actor.get_node_or_null("Nametag") if actor != null else null
		if tag is Node3D and (tag as Node3D).visible:
			(tag as Node3D).visible = false
			_hidden_tags.append(tag)
	_rig = CameraRigScript.new()
	_rig.name = "DialogCamera"
	add_child(_rig)
	_rig.call("configure", 33.0, 0.35)   # long lens (portrait), speaker left-of-centre
	_rig.call("activate")


# Frame the node's SPEAKER over the listener's shoulder. The camera stays
# locked on them while the player's options float beside the frame — no cut
# to Eli for decisions (user direction 2026-06-11: choices appear over the
# speaker immediately).
func frame_node(speaker_name: String) -> void:
	if _rig == null:
		return
	var speaker: Node3D = _resolve_speaker(speaker_name)
	if speaker == null:
		speaker = _npc
	var listener: Node3D = _npc if speaker == _player else _player
	if speaker == null or listener == null or speaker == listener:
		return
	_swap_talk_clips(speaker)
	var s_head: Vector3 = _head_of(speaker)
	var l_head: Vector3 = _head_of(listener)
	var away: Vector3 = l_head - s_head   # speaker -> listener
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3.FORWARD
	away = away.normalized()
	var side: Vector3 = away.cross(Vector3.UP)
	# Anchor BEHIND the listener's shoulder: ~a metre past their head and
	# three-quarters to the side, slightly high, long lens on the speaker's
	# face. Keeps the listener as a corner sliver (the OTS look) instead of
	# a head filling the frame — at conversation range (~1.6 m) the offsets
	# matter more than at cinema-set distances.
	var pos: Vector3 = l_head + away * 0.9 + side * 0.9 + Vector3.UP * 0.25
	# orbit = 0: conversation shots HOLD. The standoff's slow pan accumulates
	# forever — a player reading for a minute ended up looking at the backs
	# of both heads (live-play bug).
	_rig.call("frame", pos, s_head + Vector3.UP * 0.05, 0.8, 0.0)
	_last_speaker = speaker


func end() -> void:
	for entry in _restored_modes:
		var node: Node = entry[0]
		if is_instance_valid(node):
			node.process_mode = entry[1]
	_restored_modes.clear()
	for tag in _hidden_tags:
		if is_instance_valid(tag):
			(tag as Node3D).visible = true
	_hidden_tags.clear()
	_set_clip(_npc, "idle")
	if _rig != null and is_instance_valid(_rig):
		_rig.call("release")
		_rig.queue_free()
	_rig = null


# "Eli" → the player; otherwise an NPC body whose character_name matches
# (multi-speaker scenes: Park chiming into Rush's scrubber briefing cuts to
# Park); fallback = the dialog target.
func _resolve_speaker(speaker_name: String) -> Node3D:
	if speaker_name == "Eli" or speaker_name == "You":
		return _player
	if _npc != null and String(_npc.get("character_name")) == speaker_name:
		return _npc
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Node3D and String(node.get("character_name")) == speaker_name:
			return node as Node3D
	return _npc


# The verbal speaker talks, everyone else idles (modular bodies only — the
# clip helpers no-op on legacy minis).
func _swap_talk_clips(verbal_speaker: Node3D) -> void:
	for actor in [_npc, _player]:
		_set_clip(actor, "talk" if actor == verbal_speaker else "idle")


func _set_clip(actor: Node3D, clip: String) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var mc: Node = null
	if actor == _player:
		mc = actor.get("_mc")
	else:
		var holder: Node = actor.get_node_or_null("Model")
		if holder != null:
			for c in holder.get_children():
				if c.has_method("set_slot"):
					mc = c
					break
	if mc != null and mc.has_method("play_clip"):
		mc.call("play_clip", clip)


# Face height for framing: modular bodies are real-scale (~1.5 m eye-line);
# legacy minis and prop targets (the Kino pickup crate) sit lower.
func _head_of(actor: Node3D) -> Vector3:
	var modular: bool = false
	if actor == _player:
		modular = actor.get("_mc") != null
	else:
		var holder: Node = actor.get_node_or_null("Model")
		if holder != null:
			for c in holder.get_children():
				if c.has_method("set_slot"):
					modular = true
					break
	return actor.global_position + Vector3.UP * (1.5 if modular else 1.0)
