extends Node

# @no-save: audio playback bus — no persistent gameplay state.
#
# Code adapted from KidsCanCode

var num_players = 12
# All one-shot SFX route through the SFX bus so the volume slider in the title
# menu affects them; ambient hum (music bed) lives on the Music bus.
var bus = "SFX"

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

# Menu hover sound — fired when a Button gains focus (keyboard / controller
# navigation) OR receives mouse hover. Throttled so a fast mouse-drag across a
# list of buttons doesn't machine-gun the SFX bus. Centralised here so swapping
# the file to a dedicated ui_hover.ogg in future is a one-line change.
const UI_HOVER_SOUND: String = "res://sounds/bong_001.ogg"   # Kenney Interface Sounds — short menu hover blip
const UI_HOVER_MIN_INTERVAL_MS: int = 70
var _last_ui_hover_ms: int = -10000

func _ready():

	for i in num_players:
		var p = AudioStreamPlayer.new()
		add_child(p)
		
		available.append(p)
		
		p.volume_db = -10
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus


func _on_stream_finished(stream): available.append(stream)

func play(sound_path): queue.append(sound_path)


# Fire the menu-hover blip — call from a Control's focus_entered / mouse_entered.
# Throttled so rapid focus-walks (mouse-drag, keyboard auto-repeat) don't spam.
func play_ui_hover() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ui_hover_ms < UI_HOVER_MIN_INTERVAL_MS:
		return
	_last_ui_hover_ms = now
	play(UI_HOVER_SOUND)


# Wire focus_entered + mouse_entered on a focusable Control so the hover sound
# fires for both keyboard/controller navigation and mouse hover. Idempotent
# (safe to call twice on the same Control). Restricted to BaseButton subclasses
# by the caller — sliders' mouse_entered would fire on every drag-cross of the
# rail and machine-gun the SFX bus.
func attach_ui_hover(control: Control) -> void:
	if control == null:
		return
	if not control.focus_entered.is_connected(play_ui_hover):
		control.focus_entered.connect(play_ui_hover)
	if not control.mouse_entered.is_connected(play_ui_hover):
		control.mouse_entered.connect(play_ui_hover)

func _process(_delta):

	if not queue.is_empty() and not available.is_empty():
		
		available[0].stream = load(queue.pop_front())
		available[0].play()
		available[0].pitch_scale = randf_range(0.9, 1.1)
		
		available.pop_front()
