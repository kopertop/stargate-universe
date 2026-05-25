class_name KinoPickup
extends Interactable

# One-shot pickup that grants the "Kino Remote". The first interact opens the
# standard quest dialog (DialogScreen) for Eli's naming moment — he stumbles
# onto the sphere, recognises the floating camera, and christens it after the
# Russian word for cinema / film. Before that moment "Kino" doesn't exist in
# the game's vocabulary, so the prompt stays generic.

@export var prop_to_hide: NodePath

# Guards the naming sequence so a re-interact during the monologue is ignored.
var _naming: bool = false

# Eli's naming monologue, presented through the standard WoW-style DialogScreen.
# `next: "exit"` ends the conversation; on close kino_pickup acquires the item.
const KINO_DIALOG_TREE: Array = [
	{
		"speaker": "Eli Wallace",
		"text": "Whoa — wait. What is that? It was just sitting on the nightstand. Looks Ancient. Familiar too, somehow.",
		"choices": [
			{"text": "Pick it up.", "next": 1},
			{"text": "Leave it for now.", "next": "exit"},
		],
	},
	{
		"speaker": "Eli Wallace",
		"text": "It's a remote — and these spheres in the cradle, they're little floating cameras. They follow the remote. I've seen design notes like this on Atlantis dumps.",
		"choices": [
			{"text": "Does it have a name?", "next": 2},
			{"text": "Bag it up.", "next": "exit"},
		],
	},
	{
		"speaker": "Eli Wallace",
		"text": "Not yet. But… there's a word for these in Russian — 'kino' — it means cinema, film. Old word. The first kinos in cinema history were just silent footage. Feels right for what these do. I'm calling them Kinos.",
		"choices": [
			{"text": "Kino it is. Take them.", "next": "exit"},
		],
	},
]

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

# Eli's first contact with the sphere routed through the standard quest dialog.
# Headless smokes skip the dialog entirely so the kino mission-wiring assertion
# doesn't race --quit-after (the dialog pauses the SceneTree).
func _name_the_kino() -> void:
	var headless: bool = OS.has_feature("headless") or DisplayServer.get_name() == "headless"
	if headless:
		return
	GameState.dialog_started.emit(self, KINO_DIALOG_TREE)
	# Wait for DialogScreen.close() — emitted globally via GameState.dialog_closed.
	await GameState.dialog_closed

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
