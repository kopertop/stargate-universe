extends AudioStreamPlayer

# Procedural low ambient hum for ship interiors.
# Generates a slow-shifting drone from a stack of sine waves with subtle LFO
# pitch wobble. No external audio file required.

@export var base_freq: float = 55.0
@export var sample_rate: float = 22050.0
@export var enabled: bool = true

var _phase_a: float = 0.0
var _phase_b: float = 0.0
var _phase_c: float = 0.0
var _lfo: float = 0.0
var _playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	if not enabled:
		return
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = sample_rate
	gen.buffer_length = 0.2
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	_fill()

func _process(_delta: float) -> void:
	if _playback != null:
		_fill()

func _fill() -> void:
	var frames: int = _playback.get_frames_available()
	if frames <= 0:
		return
	var inc: float = TAU / sample_rate
	for i in frames:
		_lfo += inc * 0.07
		var wobble: float = sin(_lfo) * 0.6
		_phase_a += inc * (base_freq + wobble)
		_phase_b += inc * (base_freq * 1.5 + wobble * 0.5)
		_phase_c += inc * (base_freq * 0.5 - wobble * 0.3)
		var s: float = sin(_phase_a) * 0.35 + sin(_phase_b) * 0.18 + sin(_phase_c) * 0.22
		_playback.push_frame(Vector2(s, s))
