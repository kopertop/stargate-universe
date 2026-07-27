class_name TTSClient
extends Node
## Runtime text-to-speech client for dynamic dialogue.
##
## Calls the resident LuxTTS sidecar (tools/tts-onnx-poc/tts_server.py) over HTTP
## to synthesize ANY line at runtime in a pre-computed character voice — e.g.
## calling the player by name. Voices are fixed (.voice.pt embeddings); only the
## text is dynamic.
##
## Usage:
##   var tts := TTSClient.new()
##   add_child(tts)
##   tts.line_ready.connect(func(stream): $AudioStreamPlayer.stream = stream; $AudioStreamPlayer.play())
##   tts.say("rush", "Lieutenant %s, report to the gate room." % player_name)

signal line_ready(stream: AudioStreamWAV)
signal line_failed(reason: String)

@export var server_url := "http://127.0.0.1:8765"

var _http: HTTPRequest


func _ready() -> void:
	_ensure_http()


func _ensure_http() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


## Request synthesis. seed < 0 = random prosody; >= 0 = reproducible.
func say(voice: String, text: String, seed: int = -1) -> void:
	_ensure_http()  # robust if called before _ready (e.g. headless SceneTree timing)
	var url := "%s/synthesize?voice=%s&text=%s" % [server_url, voice.uri_encode(), text.uri_encode()]
	if seed >= 0:
		url += "&seed=%d" % seed
	var err := _http.request(url)
	if err != OK:
		line_failed.emit("HTTPRequest failed to start: %d" % err)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		line_failed.emit("TTS request failed (result=%d http=%d): %s" % [result, code, body.get_string_from_utf8()])
		return
	# Godot 4.4+: parse RIFF/WAV bytes directly into a playable stream.
	var stream := AudioStreamWAV.load_from_buffer(body, {})
	if stream == null:
		line_failed.emit("Failed to decode WAV (%d bytes)" % body.size())
		return
	line_ready.emit(stream)
