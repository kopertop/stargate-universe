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
		"text": "Hey — what's that over there? On the desk. I don't remember putting that down. Looks Ancient.",
		"choices": [
			{"text": "Pick it up.", "next": 1},
			{"text": "Leave it for now.", "next": "exit"},
		],
	},
	{
		"speaker": "Eli Wallace",
		"text": "Okay. It's a remote of some kind — controls down the side, little oval screen. And… wait. Something just lifted off the cradle. A tiny sphere. It's hovering. A flying camera ball.",
		"choices": [
			{"text": "A flying camera ball?", "next": 2},
			{"text": "Set it back down.", "next": "exit"},
		],
	},
	{
		"speaker": "Eli Wallace",
		"text": "Yeah — it tracks the remote. I can fly it around, look through it. It's a recon drone. I should give these things a name before someone else does and ruins it.",
		"choices": [
			{"text": "What are you going to call them?", "next": 3},
			{"text": "Bag it up.", "next": "exit"},
		],
	},
	{
		"speaker": "Eli Wallace",
		"text": "'Kino.' Russian word — means cinema. The first kinos were silent footage, just an eye watching. Feels right. Kino it is. I'm taking them with me.",
		"choices": [
			{"text": "Kino it is.", "next": "exit"},
		],
	},
]

func _ready() -> void:
	super()
	prompt = _prompt_for_state()
	if Inventory.has("kino_remote"):
		_hide_prop()
		enabled = false

func _on_interact(_by: Node) -> void:
	if _naming or Inventory.has("kino_remote"):
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
	if Inventory.has("kino_remote"):
		return "Pick up the Kino Remote"
	return "Examine the strange device"
