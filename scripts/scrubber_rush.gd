class_name ScrubberRush
extends Npc

# Dr Rush at the open life-support panel in the south corridor (Phase D). He's
# already pulled the scrubber hatch when the player arrives. Talking to him
# plays the WoW-style scene — Rush, then Dr Park, then (FTL drop) Dr Brody —
# and at the end folds in diagnose + FTL drop + auto-dial and routes the player
# to the Gate Room.
#
# The scene is the FIRST multi-speaker dialog: one tree voices Rush/Park/Brody
# via per-node speaker. The Brody node carries an "action" so DialogScreen
# fires the FTL-drop blur the instant his line appears. In instant_mode (tests)
# the dialog is skipped and the scene completes synchronously.

const FTL_ACTION: String = "scrubber_ftl"
# Preload (not class_name lookup): class_name registration can lag in headless
# -s runs, so reference the FTL effect by its script path.
const FtlDropScript: Script = preload("res://scripts/ftl_drop.gd")

func _ready() -> void:
	character_name = "Dr Rush"
	dialogue_tree = _scene_tree()
	super()

func _scene_tree() -> Array:
	return [
		{
			"speaker": "Dr Rush",
			"text": "This stuff can't be salvaged — whatever it is. We'll have to replace the whole bed with something else.",
			"choices": [{"text": "Replace it with what?", "next": 1}],
		},
		{
			"speaker": "Dr Rush",
			"text": "Lime, maybe. The carbonate would scrub CO2 well enough to buy us time. Did any come through with us when we dialed in?",
			"choices": [{"text": "Did it?", "next": 2}],
		},
		{
			"speaker": "Dr Park",
			"text": "No — I checked the manifest twice. Unfortunately, it didn't make it through the gate.",
			"choices": [{"text": "So now what?", "next": 3}],
		},
		{
			"speaker": "Dr Brody",
			"text": "Guys — the gate just dialed itself. We dropped out of FTL and it locked an address on its own. You'll want to get up here.",
			"action": FTL_ACTION,
			"choices": [{"text": "On my way.", "next": "exit"}],
		},
	]

func _on_interact(by: Node) -> void:
	var sr: Node = get_node_or_null("/root/SceneRouter")
	if sr != null and sr.get("instant_mode"):
		GameState.complete_scrubber_scene()
		return
	if not GameState.dialog_action.is_connected(_on_dialog_action):
		GameState.dialog_action.connect(_on_dialog_action)
	# If the player backs out before the FTL beat, drop the dialog_action hook
	# when the dialog closes so it doesn't linger past this conversation.
	if not GameState.dialog_closed.is_connected(_cleanup_dialog_action):
		GameState.dialog_closed.connect(_cleanup_dialog_action, CONNECT_ONE_SHOT)
	super(by)

func _cleanup_dialog_action() -> void:
	if GameState.dialog_action.is_connected(_on_dialog_action):
		GameState.dialog_action.disconnect(_on_dialog_action)

func _on_dialog_action(action_id: String) -> void:
	if action_id != FTL_ACTION:
		return
	if GameState.dialog_action.is_connected(_on_dialog_action):
		GameState.dialog_action.disconnect(_on_dialog_action)
	# The deck lurches (blur + SFX) and the scene resolves: scrubber diagnosed,
	# Destiny out of FTL, gate dialed. Quest advances to "get to the Gate Room"
	# while Brody's line is still on screen and the player picks "On my way".
	# Spawn the FTL-drop blur into the scene-tree root (survives the paused
	# current scene; self-frees). Instantiated via the preloaded script ref so
	# there's no class_name lookup.
	var fx: CanvasLayer = FtlDropScript.new()
	get_tree().root.add_child(fx)
	GameState.complete_scrubber_scene()
