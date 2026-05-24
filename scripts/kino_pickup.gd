class_name KinoPickup
extends Interactable

# One-shot pickup that grants the "Kino Remote". The first interact is also
# Eli's naming moment — he stumbles onto the sphere, recognises it as a Japanese
# stop-motion camera, and christens it. Before that moment "Kino" doesn't exist
# in the game's vocabulary, so the prompt stays generic.

@export var prop_to_hide: NodePath

# Guards the naming sequence so a re-interact during the monologue is ignored.
var _naming: bool = false

func _ready() -> void:
	super()
	prompt = _prompt_for_state()
	if GameState.kino_acquired:
		_hide_prop()
		enabled = false

func _on_interact(_by: Node) -> void:
	if _naming or GameState.kino_acquired:
		return
	_naming = true
	enabled = false
	await _name_the_kino()
	GameState.acquire_kino()
	_hide_prop()
	GameState.check_episode_complete()

# Eli's first contact with the sphere: confusion → recognition → naming. Three
# dialogue lines spaced so the HUD's auto-fade (~6.5s linger + 0.8s fade) shows
# each beat before the next overwrites it. Headless smokes skip the waits so
# the kino_room mission-wiring assertion doesn't race --quit-after.
func _name_the_kino() -> void:
	var headless: bool = OS.has_feature("headless") or DisplayServer.get_name() == "headless"
	GameState.dialogue_shown.emit("Eli", "...okay. What the hell are you?")
	if not headless:
		await get_tree().create_timer(3.2).timeout
	GameState.dialogue_shown.emit("Eli", "Some kind of remote. And these — they're like little flying cameras. Spheres with eyes.")
	if not headless:
		await get_tree().create_timer(4.0).timeout
	GameState.dialogue_shown.emit("Eli", "...Kino. Like the old Japanese stop-motion thing. I'm calling them Kinos.")
	if not headless:
		await get_tree().create_timer(2.5).timeout

func _hide_prop() -> void:
	if prop_to_hide.is_empty():
		return
	var n: Node = get_node_or_null(prop_to_hide)
	if n != null and n is Node3D:
		(n as Node3D).visible = false

func _prompt_for_state() -> String:
	if GameState.kino_acquired:
		return "Pick up the Kino Remote"
	return "Examine the strange device"
