extends SceneTree
## Headless proof: Godot drives the TTS sidecar end-to-end and decodes audio.
##
##   <godot> --headless --path <project root> \
##       --script res://tools/tts-onnx-poc/godot/test_tts_roundtrip.gd
##
## Requires tts_server.py running on 127.0.0.1:8765. Synthesizes a DYNAMIC line
## (player name injected at runtime) in the pre-computed "rush" voice, writes the
## decoded audio to user:// and prints stats, then quits with 0/1.

func _init() -> void:
	_run()


func _run() -> void:
	var tts := TTSClient.new()
	get_root().add_child(tts)

	var player_name := "Chris"  # pretend this came from save data / char creation
	var line := "Ah, %s. The Kino's picked up something on deck three. Do try to keep up." % player_name
	print("[test] requesting dynamic line: \"%s\"" % line)

	var done := false
	var ok := false
	tts.line_ready.connect(func(stream: AudioStreamWAV) -> void:
		var frames := stream.data.size() / 2  # 16-bit mono
		print("[test] line_ready: %d samples, %.2fs @ %dHz, format=%d" % [
			frames, float(frames) / stream.mix_rate, stream.mix_rate, stream.format])
		var out := "user://tts_roundtrip.wav"
		stream.save_to_wav(out)
		print("[test] wrote ", ProjectSettings.globalize_path(out))
		ok = true
		done = true)
	tts.line_failed.connect(func(reason: String) -> void:
		printerr("[test] FAILED: ", reason)
		done = true)

	tts.say("rush", line, 11)

	# Pump the main loop until the request resolves (or time out).
	var waited := 0.0
	while not done and waited < 30.0:
		await create_timer(0.1).timeout  # SceneTree.create_timer
		waited += 0.1

	if not done:
		printerr("[test] TIMEOUT waiting for TTS")
	print("[test] %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
