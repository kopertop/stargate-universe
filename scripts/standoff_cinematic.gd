extends Node

# Space-advanced cutscene sequencer for the E1 cold-open standoff (#136
# follow-up). Plays the SAME dialogue tree the WoW-dialog path uses, but as
# letterboxed captions (Cinematic autoload) while the choreography cues fire
# underneath — the standoff has no real choices, so it plays out as a scene
# instead of a dialog window. Presentation only: quest/met state is flipped
# by standoff_rush.gd before play() begins, and instant_mode never builds
# this node (it keeps the classic dialog path the suites assert against).
#
#   var seq: Node = StandoffCinematicScript.new()
#   room.add_child(seq)
#   seq.call("play", tree)
#   await Signal(seq, "finished")
#
# Advance = Space (jump) / E (interact) / ui_accept / left click. A node with
# "hold": true also waits for GameState.dialog_release before it may advance
# (Greer's charge must land before the scene moves on). Cues emit on
# GameState.dialog_action exactly like DialogScreen renders them.

signal finished

# A caption must be on screen this long before an advance press counts —
# prevents one eager Space press from machine-gunning through two beats.
const MIN_CAPTION_TIME: float = 0.35
# Baked voice lines (LuxTTS, one file per tree node index). Either container
# works — hermes bakes WAV, the repo may keep OGG.
const VO_DIR: String = "res://sounds/dialog/standoff"

var _advance_requested: bool = false
var _vo: AudioStreamPlayer = null


func _ready() -> void:
	set_process_unhandled_input(true)
	_vo = AudioStreamPlayer.new()
	_vo.name = "VoicePlayer"
	add_child(_vo)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") \
			or event.is_action_pressed("interact") \
			or event.is_action_pressed("ui_accept"):
		_advance_requested = true
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_advance_requested = true


# Deterministic advance for capture harnesses/tests (no faked InputEvents).
func request_advance() -> void:
	_advance_requested = true


func play(tree: Array) -> void:
	await Cinematic.letterbox_in()
	var first: bool = true
	for i in range(tree.size()):
		var node: Dictionary = tree[i]
		var action: String = String(node.get("action", ""))
		# Optional staging silence: the cue fires (the button CLICKS) but the
		# spoken line holds back for caption_delay seconds.
		var delay: float = float(node.get("caption_delay", 0.0))
		if delay > 0.0:
			Cinematic.set_caption("")
			if action != "":
				GameState.dialog_action.emit(action)
			await get_tree().create_timer(delay, true).timeout
			Cinematic.set_caption(_caption_for(node, first))
		else:
			Cinematic.set_caption(_caption_for(node, first))
			if action != "":
				GameState.dialog_action.emit(action)
		_play_vo(i)   # spoken line starts with its caption
		first = false
		if node.get("hold", false) == true:
			await GameState.dialog_release
		await _wait_advance()
	Cinematic.set_caption("")
	await Cinematic.letterbox_out()
	finished.emit()


# Play the baked voice line for tree node `idx` if one exists. Lines live on
# the master bus, so Movie Maker recordings pick them up too.
func _play_vo(idx: int) -> void:
	if _vo == null:
		return
	_vo.stop()
	for ext in ["ogg", "wav"]:
		var path: String = "%s/%d.%s" % [VO_DIR, idx, ext]
		if ResourceLoader.exists(path):
			_vo.stream = load(path)
			_vo.play()
			return


func _wait_advance() -> void:
	_advance_requested = false
	var shown: float = 0.0
	while true:
		await get_tree().process_frame
		shown += get_process_delta_time()
		# A voiced line plays out before the scene may advance — authored
		# cutscene pacing (and the video pinger paces itself to the VO).
		if _vo != null and _vo.playing:
			continue
		if _advance_requested and shown >= MIN_CAPTION_TIME:
			return


func _caption_for(node: Dictionary, first: bool) -> String:
	var speaker: String = String(node.get("speaker", ""))
	var text: String = String(node.get("text", ""))
	var line: String = text
	if speaker != "":
		line = "%s — \"%s\"" % [speaker.to_upper(), text]
	if first:
		line += "\n[Space]"
	return line
