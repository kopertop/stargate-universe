extends SceneTree

# HUD Chat-transcript smoke test (#141). The Chat panel must be a NARRATIVE
# transcript — fed only by character speech (dialogue_shown) and narration
# (narrative_added) — and must NOT fill with the noisy system journal (add_log:
# discovery, resources, saves). It starts EMPTY and only fills as people speak.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/hud_chat.gd

const HUD_SCENE: String = "res://objects/hud.tscn"

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null
var _game: Node = null


func _initialize() -> void:
	print("=== hud_chat smoke test ===")
	call_deferred("_run")


func _run() -> void:
	_game = root.get_node_or_null("/root/GameState")
	_expect(_game != null, "GameState autoload present")
	if _game == null:
		_report()
		return

	var scene: PackedScene = load(HUD_SCENE) as PackedScene
	_expect(scene != null, "hud.tscn loads")
	if scene == null:
		_report()
		return
	_hud = scene.instantiate()
	root.add_child(_hud)
	await process_frame

	var chat: RichTextLabel = _hud.get("_chat_log") as RichTextLabel
	_expect(chat != null, "chat log RichTextLabel exists")
	if chat == null:
		_finish()
		return

	# Starts empty — no system-journal seed.
	_expect(chat.get_parsed_text().strip_edges() == "",
		"chat starts empty (not seeded from log_entries)")

	# System-journal noise must NOT reach the chat.
	_game.call("add_log", "Collected 1 lime. Total: 2.")
	_game.call("add_log", "Discovered: Control Interface Room")
	_game.call("add_log", "Game saved.")
	await process_frame
	var after_noise: String = chat.get_parsed_text()
	_expect(not after_noise.contains("Collected"), "resource log line stays OUT of chat")
	_expect(not after_noise.contains("Discovered"), "discovery log line stays OUT of chat")
	_expect(not after_noise.contains("saved"), "save log line stays OUT of chat")

	# Narration (speaker-less stage direction) appears.
	_game.call("narrate", "Lt Scott comes barrelling through the gate!")
	await process_frame
	_expect(chat.get_parsed_text().contains("barrelling through the gate"),
		"narration line appears in chat")

	# Scripted speech via say() appears as "Speaker: line".
	_game.call("say", "Lt Scott", "Okay, it's safe. Start sending people through.")
	await process_frame
	var t: String = chat.get_parsed_text()
	_expect(t.contains("Lt Scott") and t.contains("it's safe"),
		"say() renders a Speaker: line in chat")

	# Live NPC dialogue via dialogue_shown also lands in the transcript.
	_game.emit_signal("dialogue_shown", "Dr Rush", "Fascinating.")
	await process_frame
	_expect(chat.get_parsed_text().contains("Dr Rush") and chat.get_parsed_text().contains("Fascinating"),
		"dialogue_shown speech appears in chat")

	_finish()


func _finish() -> void:
	if _hud != null and is_instance_valid(_hud):
		root.remove_child(_hud)
		_hud.free()
	_report()


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
