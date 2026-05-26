extends Node

# @no-save: ambient atmosphere audio — no persistent state, all derived from
# GameState flags.
#
# Plays one-shot atmosphere sounds tied to ship state. Currently:
#   - Light flicker: random interval after air_crisis_started, off again
#     once scrubber_repaired.
#
# Routes everything through the global `Audio` autoload so the SFX bus
# volume slider still controls it. Pitch is randomized by Audio.play() so
# repeat plays don't feel mechanical.

const FLICKER_SOUND: String = "res://sounds/flicker.ogg"
# Random delay between flickers — long enough that the player notices the
# silence between them, short enough that the air-crisis tension stays
# present.
const FLICKER_MIN_INTERVAL: float = 6.0
const FLICKER_MAX_INTERVAL: float = 14.0

var _flicker_timer: Timer

func _ready() -> void:
	# Active even while the game is paused (Kino Remote opens pause the tree)
	# so the ambient layer still ticks under the menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flicker_timer = Timer.new()
	_flicker_timer.one_shot = true
	_flicker_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_flicker_timer.timeout.connect(_on_flicker_tick)
	add_child(_flicker_timer)
	_schedule_next_flicker()


func _schedule_next_flicker() -> void:
	_flicker_timer.start(randf_range(FLICKER_MIN_INTERVAL, FLICKER_MAX_INTERVAL))


func _on_flicker_tick() -> void:
	if _should_play_flicker():
		Audio.play(FLICKER_SOUND)
	_schedule_next_flicker()


# Only flicker during the air-crisis window — the Destiny is "in trouble"
# from the alarm onwards until the scrubber is fully repaired. Outside that
# window the ship reads as nominal and the timer ticks silently.
func _should_play_flicker() -> bool:
	if not GameState.air_crisis_started:
		return false
	if GameState.scrubber_repaired:
		return false
	return true
