class_name TTSClient
extends Node

## Runtime text-to-speech client for dynamic dialogue.
##
## Calls the resident LuxTTS sidecar (tools/tts-onnx-poc/tts_server.py) over HTTP
## to synthesize ANY line at runtime in a pre-computed character voice — e.g.
## calling the player by name. Voices are fixed (.voice.pt embeddings); only the
## text is dynamic.
##
## Enhanced (P3 TTS integration):
##   • Per-character voice profiles: resolves a speaker display name to its
##     TTS voice via data/characters.json (tts_voice field).
##   • Emotional inflection: passes an emotion hint to the sidecar (neutral,
##     urgent, calm, angry, afraid, sad, curious, determined). The sidecar
##     may ignore it if it doesn't support emotion steering yet.
##   • Ancient language TTS: lines marked `ancient: true` in the dialogue tree
##     use a configurable voice (default "narrator") with a pitch shift for an
##     otherworldly quality.
##   • In-memory caching: repeated lines reuse the cached AudioStreamWAV.
##   • Text-only fallback: if the sidecar is unreachable, line_failed fires and
##     the caller shows the subtitle text without audio.
##
## Usage:
##   var tts := TTSClient.new()
##   add_child(tts)
##   tts.line_ready.connect(func(stream): $AudioStreamPlayer.stream = stream; $AudioStreamPlayer.play())
##   tts.say("rush", "Lieutenant %s, report to the gate room." % player_name)
##   # High-level: resolves voice from speaker name + emotion from characters.json
##   tts.say_line("Dr Rush", "Ah, Eli. Try to keep up.")
##   # Ancient language line (otherworldly voice + pitch shift):
##   tts.say_line("Dr Rush", "The ship is ancient.", "calm", true)

signal line_ready(stream: AudioStreamWAV)
signal line_failed(reason: String)

@export var server_url := "http://127.0.0.1:8765"
@export var voice_bus := "Voice"
@export var ancient_voice := "narrator"
@export var ancient_pitch := 0.85  # lower pitch for Ancient speech
@export var enable_caching := true
@export var enable_tts := true   # master toggle; false = text-only mode

var _http: HTTPRequest
var _health_http: HTTPRequest
var _player: AudioStreamPlayer
var _cache: Dictionary = {}  # cache_key -> AudioStreamWAV (in-memory)
var _available: bool = false
var _health_checked: bool = false

const CHARACTERS_PATH: String = "res://data/characters.json"
static var _characters: Dictionary = {}


func _ready() -> void:
	_ensure_http()
	_ensure_player()
	if enable_tts:
		_check_health()


func _ensure_http() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_health_http = HTTPRequest.new()
	add_child(_health_http)
	_health_http.request_completed.connect(_on_health_completed)


func _ensure_player() -> void:
	if _player != null:
		return
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.bus = voice_bus


# ── Health check ───────────────────────────────────────────────────────────

## Check if the TTS sidecar is running. Sets _available for fast-fallback.
func _check_health() -> void:
	_ensure_http()
	var err := _health_http.request("%s/health" % server_url)
	if err != OK:
		_available = false
		_health_checked = true


func _on_health_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		_available = true
	else:
		_available = false
	_health_checked = true


## True if the TTS sidecar has confirmed it's running, or hasn't been checked
## yet (optimistic — the request will fail gracefully if not).
func is_available() -> bool:
	if not enable_tts:
		return false
	if not _health_checked:
		return true  # optimistic: haven't checked yet, let the request try
	return _available


# ── Character voice resolution ─────────────────────────────────────────────

## Resolve a speaker display name to its TTS voice name from characters.json.
## Falls back to "default" if the character isn't registered or has no tts_voice.
static func voice_for(speaker: String) -> String:
	_load_characters()
	var entry: Variant = _characters.get(speaker, null)
	if entry is Dictionary:
		var v: String = String((entry as Dictionary).get("tts_voice", ""))
		if v != "":
			return v
	return "default"


## Resolve a speaker's default emotion from characters.json.
## Returns "neutral" if not specified.
static func emotion_for(speaker: String) -> String:
	_load_characters()
	var entry: Variant = _characters.get(speaker, null)
	if entry is Dictionary:
		var e: String = String((entry as Dictionary).get("default_emotion", ""))
		if e != "":
			return e
	return "neutral"


static func _load_characters() -> void:
	if not _characters.is_empty():
		return
	var file: FileAccess = FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	if file == null:
		return
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		_characters = parsed


# ── Synthesis ───────────────────────────────────────────────────────────────

## Request synthesis. seed < 0 = random prosody; >= 0 = reproducible.
## emotion is an optional hint (neutral, urgent, calm, angry, afraid, sad,
## curious, determined). The sidecar may ignore it.
## ancient = true uses the ancient_voice with a pitch shift.
func say(voice: String, text: String, seed: int = -1, emotion: String = "", ancient: bool = false) -> void:
	if not enable_tts:
		line_failed.emit("TTS disabled (text-only mode)")
		return
	_ensure_http()
	# Check cache first.
	var cache_key := _cache_key(voice, text, seed, emotion, ancient)
	if enable_caching and _cache.has(cache_key):
		var cached: AudioStreamWAV = _cache[cache_key]
		line_ready.emit(cached)
		return
	# Build the request URL. The sidecar accepts voice + text (+ optional seed).
	# We append emotion as a query param the server may use in future.
	var url := "%s/synthesize?voice=%s&text=%s" % [server_url, voice.uri_encode(), text.uri_encode()]
	if seed >= 0:
		url += "&seed=%d" % seed
	if emotion != "" and emotion != "neutral":
		url += "&emotion=%s" % emotion.uri_encode()
	var err := _http.request(url)
	if err != OK:
		line_failed.emit("HTTPRequest failed to start: %d" % err)

	# Stash request metadata so we can apply pitch / cache on completion.
	_http.set_meta("current_voice", voice)
	_http.set_meta("current_ancient", ancient)
	_http.set_meta("current_cache_key", cache_key)


## High-level convenience: resolve voice + emotion from speaker name, then
## synthesize. If ancient is true, uses the ancient_voice with pitch shift.
func say_line(speaker: String, text: String, emotion: String = "", ancient: bool = false, seed: int = -1) -> void:
	var voice: String = voice_for(speaker) if not ancient else ancient_voice
	var emo: String = emotion if emotion != "" else emotion_for(speaker)
	say(voice, text, seed, emo, ancient)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_available = false
		var reason := "TTS request failed (result=%d http=%d): %s" % [result, code, body.get_string_from_utf8()]
		line_failed.emit(reason)
		return
	# Godot 4.4+: parse RIFF/WAV bytes directly into a playable stream.
	var stream := AudioStreamWAV.load_from_buffer(body, {})
	if stream == null:
		line_failed.emit("Failed to decode WAV (%d bytes)" % body.size())
		return
	# Apply pitch shift for Ancient language lines.
	var is_ancient: bool = _http.get_meta("current_ancient", false)
	if is_ancient:
		# AudioStreamWAV doesn't have pitch_scale; the player's pitch is
		# set at playback time. We stash the flag on the stream via meta.
		stream.set_meta("ancient_pitch", ancient_pitch)
	# Cache the stream.
	if enable_caching:
		var ck: String = _http.get_meta("current_cache_key", "")
		if ck != "":
			_cache[ck] = stream
	_available = true
	line_ready.emit(stream)


# ── Playback convenience ───────────────────────────────────────────────────

## Play a synthesized stream on the Voice bus. Connect line_ready to this
## for one-liner playback. Applies Ancient pitch shift if the stream carries
## the ancient_pitch meta.
func play_stream(stream: AudioStreamWAV) -> void:
	_ensure_player()
	_player.stream = stream
	# Apply pitch shift if the stream was tagged as Ancient.
	if stream.has_meta("ancient_pitch"):
		_player.pitch_scale = float(stream.get_meta("ancient_pitch", 1.0))
	else:
		_player.pitch_scale = 1.0
	_player.play()


## Stop any currently playing voice line.
func stop() -> void:
	if _player != null:
		_player.stop()


# ── Caching helpers ─────────────────────────────────────────────────────────

func _cache_key(voice: String, text: String, seed: int, emotion: String, ancient: bool) -> String:
	return "%s|%s|%d|%s|%s" % [voice, text, seed, emotion, str(ancient)]


## Clear the in-memory cache (e.g. on language change).
func clear_cache() -> void:
	_cache.clear()