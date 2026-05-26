class_name Bed
extends Interactable

# Sleep interactable. Restores full health, plays a short fade, and (if first time)
# marks the player as having found their quarters.
#
# When the interact also triggers the Air-crisis transition
# (can_start_air_crisis), the bed plays a sleep cinematic: lay-down animation,
# fade to black, hold, fade back in, then announce the alarm. The
# CharacterBody3D itself stays put — we only tween the visual `Character`
# child node — so collision and camera anchoring don't fight the cinematic.

@export var first_time_log: String = "These will be my quarters, then. The bed is cold."
@export var sleep_message: String = "Rested. You feel a little less ready to fall over."

# Cinematic timings (seconds). Sequence: lay-down → fade to black → 2s of
# quiet sleep → klaxon (still black) → Eli "What the heck?" (still black)
# → fade back in + wake-up tween (Eli jumps off the bed) → radio static +
# Scott's order (now awake, lit room).
const LAY_DOWN_DURATION: float = 0.55
const FADE_IN_DURATION: float = 0.65
# Quiet "deep sleep" beat after the screen goes black, before the alarm.
const SLEEP_DELAY_DURATION: float = 2.0
const FADE_OUT_DURATION: float = 0.75
const WAKE_UP_DURATION: float = 0.5
# Beat pacing.
const ALARM_TO_REACTION_GAP: float = 0.7   # klaxon → "What the heck?"
const REACTION_READ_TIME: float = 1.6      # "What the heck?" → fade back in
const POST_WAKE_RADIO_DELAY: float = 0.6   # standing up → radio static
const RADIO_CLICK_TO_LINE_GAP: float = 0.35  # static → Scott's line

# Vertical lift above the bed body's pivot — raises the model so it lays
# ON the mattress (~y=0.85 world) rather than half-sunk into the bed body
# collider (centered at y=0.75). 0.18 ≈ mattress top + a thin margin.
const BED_SURFACE_LIFT: float = 0.18

# World-space rotation that lays the model flat with its head at world -Z.
# The bed-single.obj prop has its long axis along world Z with the headboard
# at the -Z end (against the room's -Z wall). A -PI/2 rotation around world
# X maps the model's local +Y (top of head) to world -Z — body aligns along
# the bed's long axis with head on the pillow.
const LAY_DOWN_ROT: Vector3 = Vector3(-PI * 0.5, 0.0, 0.0)

func _ready() -> void:
	super()
	prompt = "Lay down and rest"

func _on_interact(by: Node) -> void:
	if not GameState.quarters_found:
		# mark_quarters_found logs the first-time message itself; passing
		# `first_time_log` here lets each bed instance show its own flavour
		# (Eli's quarters vs Crew Quarters Alpha) without a duplicate log.
		GameState.mark_quarters_found(first_time_log)
	if GameState.air_crisis_started and not GameState.scrubber_repaired:
		GameState.add_log("No chance of sleeping with CO2 alarms rising.")
		return
	GameState.heal_full()
	if GameState.can_start_air_crisis():
		# Sleep cinematic + air-crisis trigger. Awaited so the prompt doesn't
		# re-pop and the player can't queue up a second interact mid-fade.
		await _sleep_cinematic(by)
		return
	GameState.restore_oxygen(GameState.MAX_OXYGEN)
	GameState.add_log(sleep_message)
	GameState.advance_air_quest()


# Animate the player model onto the bed, fade to black while the air-crisis
# state flips, then fade back in with the alarm dialog. The model returns to
# its standing pose under the black so the wake-up looks like the player
# simply stood up.
func _sleep_cinematic(by: Node) -> void:
	# Tests + headless playthrough share SceneRouter.instant_mode = true.
	# Skip the cinematic in that case so the state flips synchronously and
	# the test asserts immediately after _interact_node() finds the new
	# air_crisis_started state without having to wait out fade tweens.
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		GameState.add_log("You sleep hard enough to miss the jump timer.")
		GameState.start_air_crisis()
		GameState.announce_air_crisis()
		return

	var player: Node3D = by as Node3D
	if player == null:
		# Defensive — caller signature guarantees Node3D from player.gd's
		# interact ray, but we don't want a script error to hang the await.
		GameState.add_log("You sleep hard enough to miss the jump timer.")
		GameState.start_air_crisis()
		GameState.announce_air_crisis()
		return

	if player.has_method("set_input_locked"):
		player.call("set_input_locked", true)

	# Lay-down tween. Uses WORLD-space global_position + global_rotation so
	# the orientation doesn't depend on which direction the player was
	# facing when they pressed E — the head lands at the bed's pillow end
	# regardless of approach angle.
	var model: Node3D = player.get_node_or_null("Character")
	var model_start_pos: Vector3 = Vector3.ZERO
	var model_start_rot: Vector3 = Vector3.ZERO
	if model != null:
		# Snapshot LOCAL pose for the standing-up snap-back. Restoring
		# global would tangle with player.rotation if the player happens to
		# rotate during the cinematic (locked input prevents this today,
		# but local is the cleaner contract).
		model_start_pos = model.position
		model_start_rot = model.rotation
		var lay_world_pos: Vector3 = global_position + Vector3(0.0, BED_SURFACE_LIFT, 0.0)
		var lay_tween: Tween = create_tween()
		lay_tween.set_parallel(true)
		lay_tween.set_trans(Tween.TRANS_SINE)
		lay_tween.set_ease(Tween.EASE_OUT)
		lay_tween.tween_property(model, "global_position", lay_world_pos, LAY_DOWN_DURATION)
		lay_tween.tween_property(model, "global_rotation", LAY_DOWN_ROT, LAY_DOWN_DURATION)
		await lay_tween.finished

	# Fade overlay — parented to the CURRENT scene so a mid-cinematic scene
	# change (shouldn't happen, but defensive) doesn't leave the overlay
	# stranded on the persistent root.
	var fade_layer: CanvasLayer = CanvasLayer.new()
	fade_layer.layer = 99
	var fade_rect: ColorRect = ColorRect.new()
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	fade_rect.anchor_right = 1.0
	fade_rect.anchor_bottom = 1.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade_rect)
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		current_scene.add_child(fade_layer)
	else:
		get_tree().root.add_child(fade_layer)

	var fade_in: Tween = create_tween()
	fade_in.tween_property(fade_rect, "color:a", 1.0, FADE_IN_DURATION)
	await fade_in.finished

	# State flips silently under the black so the quest target is already
	# updated by the time the world fades back in.
	GameState.add_log("You sleep hard enough to miss the jump timer.")
	GameState.start_air_crisis()

	# === Black beat: alarm + groggy reaction ===
	# Two seconds of quiet black — Eli is asleep — then the klaxon jolts him
	# awake. The dialog HUD sits below this fade overlay (layer 99), so we
	# render Eli's reaction as a caption directly onto the black.
	await get_tree().create_timer(SLEEP_DELAY_DURATION).timeout

	# Awaited (not fire-and-forget) so the three strikes finish before Eli's
	# reaction and there's no detached coroutine outliving this node.
	await _play_wake_alarm()
	await get_tree().create_timer(ALARM_TO_REACTION_GAP).timeout
	_set_caption(fade_layer, "Eli", "Wh— what the heck?")
	GameState.add_log("Eli: What the heck?")
	await get_tree().create_timer(REACTION_READ_TIME).timeout
	_clear_caption(fade_layer)

	# Fade back in with the model STILL in its lay-down pose — the wake-up
	# tween below plays the lay-down in reverse, so Eli is visibly on the
	# bed when the screen returns, then pops up to his feet.
	var fade_out: Tween = create_tween()
	fade_out.tween_property(fade_rect, "color:a", 0.0, FADE_OUT_DURATION)
	await fade_out.finished

	# Wake-up tween — REVERSE of lay-down. Tweens model's local pose back
	# to its standing default. EASE_OUT so the motion settles instead of
	# overshooting at the end. Reads as "Eli jumps up off the bed."
	if model != null:
		var wake_tween: Tween = create_tween()
		wake_tween.set_parallel(true)
		wake_tween.set_trans(Tween.TRANS_SINE)
		wake_tween.set_ease(Tween.EASE_OUT)
		wake_tween.tween_property(model, "position", model_start_pos, WAKE_UP_DURATION)
		wake_tween.tween_property(model, "rotation", model_start_rot, WAKE_UP_DURATION)
		await wake_tween.finished

	fade_layer.queue_free()
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", false)

	# === Awake beat: Scott's radio ===
	# Now that Eli is on his feet in the lit (red-alert) room, Scott crackles
	# in over the radio. Player already has control — Scott's order can land
	# while they start moving. Uses the dialog HUD panel (visible now that
	# the fade is gone) rather than a black-screen caption.
	await get_tree().create_timer(POST_WAKE_RADIO_DELAY).timeout
	Audio.play("res://sounds/radio_click.ogg")
	await get_tree().create_timer(RADIO_CLICK_TO_LINE_GAP).timeout
	GameState.dialogue_shown.emit("Lt Scott", "Eli — get to the control room. NOW. Find Rush.")
	GameState.add_log("Lt Scott (radio): Eli, get to the control room NOW. Find Rush.")
	# Walkie-talkie sign-off beep closes the transmission.
	await get_tree().create_timer(1.8).timeout
	Audio.play("res://sounds/radio_off.ogg")


# Render a cinematic caption directly onto the fade overlay (which sits above
# the dialog HUD), so the radio exchange is visible while the screen is
# black. Reuses a single "Caption" Label, replacing its text each beat.
func _set_caption(layer: CanvasLayer, speaker: String, line: String) -> void:
	var label: Label = layer.get_node_or_null("Caption") as Label
	if label == null:
		label = Label.new()
		label.name = "Caption"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(label)
	label.text = "%s\n\n\"%s\"" % [speaker, line]


func _clear_caption(layer: CanvasLayer) -> void:
	var label: Node = layer.get_node_or_null("Caption")
	if label != null:
		label.queue_free()


# Three klaxon strikes spaced ~0.55s apart, with a short electrical flicker
# between strikes 2 and 3 for additional unease. Fires concurrently with the
# wake-up fade-out so the alarm reads as the first thing Eli registers when
# he opens his eyes.
#
# Routes through a dedicated AudioStreamPlayer at volume_db = +6 instead of
# the shared Audio pool (which clamps at -10 dB) — the alarm needs to cut
# through dialog + ambient. Pool-routed sounds (flicker) stay at the normal
# attenuation so the klaxon dominates the moment.
func _play_wake_alarm() -> void:
	const KLAXON: String = "res://sounds/klaxon.ogg"
	const FLICKER: String = "res://sounds/flicker.ogg"
	const STRIKE_SPACING: float = 0.55
	const KLAXON_VOLUME_DB: float = 6.0

	var klaxon_stream: AudioStream = load(KLAXON)
	for i in 3:
		_play_loud(klaxon_stream, KLAXON_VOLUME_DB)
		if i == 1:
			# Halfway through the klaxon series, drop a flicker for the
			# "lights are wrong" feel.
			Audio.play(FLICKER)
		if i < 2:
			await get_tree().create_timer(STRIKE_SPACING).timeout
			# Bail if the bed was freed mid-sequence (defensive — input is
			# locked during the cinematic so this shouldn't happen).
			if not is_inside_tree():
				return


# Spawn a one-shot AudioStreamPlayer parented to the scene root, play it
# at the requested gain, and free it on finish. Bypasses the shared Audio
# pool so the klaxon isn't capped at the pool's quiet default volume.
func _play_loud(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player_node: AudioStreamPlayer = AudioStreamPlayer.new()
	player_node.stream = stream
	player_node.bus = "SFX"
	player_node.volume_db = volume_db
	player_node.finished.connect(player_node.queue_free)
	get_tree().current_scene.add_child(player_node)
	player_node.play()
