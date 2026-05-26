class_name GateConsole
extends Interactable

# Gate-room console. Two flavors switched by `kind`:
#   • "gate_control"   — Eli reads his notes; address book empty; gate is dormant.
#   • "ftl_countdown"  — live countdown to next FTL drop; ticks every frame.
#
# The console's text readout is rendered as a TextMesh child of the screen
# plate (see RoomBuilder.attach_console_mesh which builds the plate). The
# TextMesh inherits the plate's tilt automatically, glows tech-blue against
# the plate's dim background, and updates live for the FTL countdown.

@export var kind: String = "gate_control"

# FTL countdown total window length, in seconds (matches the spec's
# "17h 42m 18s" beat from the arrival cinematic). The live remaining
# value is derived from GameClock.elapsed_seconds at every read, so the
# countdown is anchored to accumulated gameplay time and survives
# save/resume exactly.
const FTL_COUNTDOWN_TOTAL_SECONDS: float = 63738.0

# Live readout — TextMesh as child of the ScreenPlate. TextMesh geometry
# regenerates when .text changes, so we track _last_text and only update
# when the displayed string actually differs (avoids re-meshing 60×/sec
# during FTL countdown).
var _text_mi: MeshInstance3D
var _text_mesh: TextMesh
var _last_text: String = ""
# Cached interact-flavour lines so repeated reads cycle instead of repeating.
var _gate_lines: Array[String] = [
	"Eli: \"Gate's in standby. No active wormhole, no address dialed.\"",
	"Eli: \"Address book is… empty. Whoever flew this thing didn't leave notes.\"",
	"Eli: \"Could probably dial an outbound if we had nine symbols and a death wish.\"",
]
var _ftl_lines: Array[String] = [
	"Eli: \"FTL drop timer is ticking. We are very much on a schedule.\"",
	"Eli: \"Whatever's at the other end of this jump, we'll see it when the clock runs out.\"",
	"Eli: \"Destiny doesn't ask for our opinion. The countdown is the countdown.\"",
]
var _line_index: int = 0

func _ready() -> void:
	super()
	# Interactable._ready() hard-sets collision_layer = 4 (interactable-only).
	# OR in layer 1 so the player capsule (mask = 1) also collides with the
	# console body — otherwise the player walks straight through the gate consoles.
	collision_layer = 1 | 4
	_apply_kind_defaults()
	_build_screen_readout()

func _process(_delta: float) -> void:
	if _text_mesh != null:
		var current: String = _readout_text()
		if current != _last_text:
			_text_mesh.text = current
			_last_text = current
	_apply_kind_defaults()
	# FTL countdown is now derived from GameClock.elapsed_seconds — no
	# per-frame accumulator needed. Display computation lives in
	# _readout_text() and _on_interact().

func _apply_kind_defaults() -> void:
	# Each kind gets its own interact prompt — the player doesn't have to walk
	# up to know which one they're aiming at.
	if kind == "ftl_countdown":
		prompt = "Read FTL status"
		if GameState.quest_step == GameState.QUEST_WAIT_FTL:
			prompt = "Trigger FTL drop"
	else:
		prompt = "Read your notes"
		if GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
			prompt = "Diagnose life support"
		elif GameState.quest_step == GameState.QUEST_DIAL_LIME_PLANET:
			prompt = "Dial lime planet"
		elif GameState.is_lime_gate_open():
			prompt = "Gate active: lime planet"

func _build_screen_readout() -> void:
	# Find the ScreenPlate built procedurally by RoomBuilder.attach_console_mesh
	# (named for exactly this purpose) and attach a TextMesh as its child so
	# the text inherits the plate's tilt automatically.
	var holder: Node = get_parent()
	if holder == null:
		return
	var stage: Node = holder.get_node_or_null("ConsoleMesh")
	if stage == null:
		return
	var plate: Node = stage.get_node_or_null("ScreenPlate")
	if plate == null or not (plate is MeshInstance3D):
		return
	var plate_mi: MeshInstance3D = plate

	_text_mesh = TextMesh.new()
	_text_mesh.text = _readout_text()
	_text_mesh.font_size = RoomBuilder.CONSOLE_TEXT_FONT_SIZE
	_text_mesh.depth = RoomBuilder.CONSOLE_TEXT_DEPTH
	_text_mesh.pixel_size = RoomBuilder.CONSOLE_TEXT_PIXEL_SIZE
	_text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_last_text = _text_mesh.text

	var text_mat: StandardMaterial3D = StandardMaterial3D.new()
	text_mat.albedo_color = RoomBuilder.CONSOLE_TEXT_COLOR
	text_mat.emission_enabled = true
	text_mat.emission = RoomBuilder.CONSOLE_TEXT_COLOR
	text_mat.emission_energy_multiplier = RoomBuilder.CONSOLE_TEXT_EMISSION
	text_mat.no_depth_test = true

	_text_mi = MeshInstance3D.new()
	_text_mi.name = "ScreenText"
	_text_mi.mesh = _text_mesh
	_text_mi.material_override = text_mat
	_text_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_text_mi.position = Vector3.ZERO
	_text_mi.rotation_degrees = RoomBuilder.CONSOLE_TEXT_LOCAL_ROTATION_DEG
	plate_mi.add_child(_text_mi)

func _on_interact(_by: Node) -> void:
	if kind == "ftl_countdown":
		if GameState.quest_step == GameState.QUEST_WAIT_FTL:
			GameState.trigger_ftl_drop()
		else:
			GameState.add_log("Console: Next FTL drop in %s." % _format_countdown(_ftl_seconds_remaining()))
			GameState.add_log(_ftl_lines[_line_index % _ftl_lines.size()])
	else:
		if GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
			GameState.diagnose_life_support()
		elif GameState.quest_step == GameState.QUEST_DIAL_LIME_PLANET:
			GameState.dial_lime_planet()
		elif GameState.is_lime_gate_open():
			GameState.add_log("Console: Wormhole active to the lime planet. Step through the gate.")
		else:
			GameState.add_log("Console: Gate is in standby. Address book empty.")
			GameState.add_log(_gate_lines[_line_index % _gate_lines.size()])
	_line_index += 1

func _format_countdown(total_seconds: float) -> String:
	var t: int = int(total_seconds)
	var h: int = t / 3600
	var m: int = (t % 3600) / 60
	var s: int = t % 60
	return "%dh %02dm %02ds" % [h, m, s]


# Countdown is anchored to GameClock.elapsed_seconds — total window minus
# how much gameplay time has accumulated since the new-game origin. Save
# files round-trip GameClock so the displayed value picks up exactly
# where the player left off.
func _ftl_seconds_remaining() -> float:
	return maxf(0.0, FTL_COUNTDOWN_TOTAL_SECONDS - GameClock.elapsed_seconds)

func _readout_text() -> String:
	if kind == "ftl_countdown":
		if GameState.quest_step == GameState.QUEST_WAIT_FTL:
			return "FTL WINDOW\nDROP NOW"
		if GameState.ftl_drop_triggered:
			return "FTL STATUS\nNORMAL SPACE"
		return "NEXT FTL DROP\n" + _format_countdown(_ftl_seconds_remaining())
	if GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
		return "LIFE SUPPORT\nDIAGNOSTIC READY"
	if GameState.quest_step == GameState.QUEST_DIAL_LIME_PLANET:
		return "GATE CONTROL\nLIME WORLD LOCK"
	if GameState.is_lime_gate_open():
		return "GATE ACTIVE\nLIME WORLD"
	return "GATE CONTROL\nSTANDBY"
