class_name GateConsole
extends Interactable

# Gate-room console. Two flavors switched by `kind`:
#   • "gate_control"   — Eli reads his notes; address book empty; gate is dormant.
#   • "ftl_countdown"  — live countdown to next FTL drop; ticks every frame.
#
# Both consoles render a small Label3D floating just above their model so the
# readout is legible from across the room. The interact handler dumps a longer
# block of flavor text to the HUD log so the player can read Eli's thinking.

@export var kind: String = "gate_control"

# FTL countdown initial offset (matches the spec's "17h 42m 18s" beat from the
# arrival cinematic — feel free to tweak per scene if you want a different beat).
@export var ftl_seconds_remaining: float = 63738.0

# Floating readout above the console mesh. Built procedurally so the .tscn /
# instancer doesn't have to know about it.
var _readout: Label3D
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
	_build_readout()

func _process(delta: float) -> void:
	if _readout != null:
		_readout.text = _readout_text()
	_apply_kind_defaults()
	if kind != "ftl_countdown":
		return
	ftl_seconds_remaining = maxf(0.0, ftl_seconds_remaining - delta)

func _apply_kind_defaults() -> void:
	# Each kind gets its own interact prompt — the player doesn't have to walk
	# up to know which one they're aiming at.
	if kind == "ftl_countdown":
		prompt = "Read FTL status"
		if GameState.quest_step == GameState.QUEST_WAIT_FTL:
			prompt = "Trigger FTL drop"
	else:
		prompt = "Read Eli's notes"
		if GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
			prompt = "Diagnose life support"
		elif GameState.quest_step == GameState.QUEST_DIAL_LIME_PLANET:
			prompt = "Dial lime planet"
		elif GameState.is_lime_gate_open():
			prompt = "Gate active: lime planet"

func _build_readout() -> void:
	_readout = Label3D.new()
	_readout.name = "Readout"
	# Glue the readout to the screen plate (no billboard) so the text reads
	# AS the console's display rather than a floating tag above the unit.
	_readout.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Depth test ON so the console housing properly occludes the label when
	# the camera is on the WRONG side of the console (was rendering through
	# the back as mirrored text). render_priority breaks ties with the plate
	# from the front side so the label doesn't z-fight.
	_readout.no_depth_test = false
	_readout.render_priority = 1
	_readout.shaded = false
	# Single-sided so the back of the quad doesn't render mirrored text when
	# the camera is behind the console — the screen is meant to be read only
	# from the operator's side.
	_readout.double_sided = false
	_readout.pixel_size = 0.007
	_readout.outline_size = 8
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_readout.modulate = Color(0.55, 0.92, 1.0, 1.0) if kind == "ftl_countdown" else Color(1.0, 0.74, 0.32, 1.0)
	_readout.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	# Pin the readout to the screen plate's transform — derive from RoomBuilder's
	# shared CONSOLE_* constants so retuning the plate auto-retunes the label.
	# Plate is at stage-local (CONSOLE_SCREEN_PLATE_Y, CONSOLE_SCREEN_PLATE_Z)
	# scaled by CONSOLE_SCALE = holder-local position. Normal direction follows
	# the plate's tilt (Godot's +X rotation: +Y → (0, cos, -sin)).
	# Label's text plane (default normal +Z) needs `tilt - 90°` rotation around
	# X so its -Z (text-visible side) aligns with the plate's +Y (surface normal).
	var plate_y: float = RoomBuilder.CONSOLE_SCREEN_PLATE_Y * RoomBuilder.CONSOLE_SCALE
	var plate_z: float = RoomBuilder.CONSOLE_SCREEN_PLATE_Z * RoomBuilder.CONSOLE_SCALE
	var tilt_rad: float = deg_to_rad(RoomBuilder.CONSOLE_SCREEN_TILT_DEG)
	# 5 cm outward along the plate normal — generous offset so the label
	# clearly sits on TOP of the emissive plate (no z-fight) but stays within
	# the housing's occlusion volume so the back wall hides it from behind.
	var proud: float = 0.05
	_readout.position = Vector3(
		0.0,
		plate_y + cos(tilt_rad) * proud,
		plate_z - sin(tilt_rad) * proud,
	)
	_readout.rotation_degrees = Vector3(RoomBuilder.CONSOLE_SCREEN_TILT_DEG - 90.0, 0.0, 0.0)
	add_child(_readout)
	# Set initial text immediately so the first frame already reads.
	_readout.text = _readout_text()

func _on_interact(_by: Node) -> void:
	if kind == "ftl_countdown":
		if GameState.quest_step == GameState.QUEST_WAIT_FTL:
			GameState.trigger_ftl_drop()
		else:
			GameState.add_log("Console: Next FTL drop in %s." % _format_countdown(ftl_seconds_remaining))
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

func _readout_text() -> String:
	if kind == "ftl_countdown":
		if GameState.quest_step == GameState.QUEST_WAIT_FTL:
			return "FTL WINDOW\nDROP NOW"
		if GameState.ftl_drop_triggered:
			return "FTL STATUS\nNORMAL SPACE"
		return "NEXT FTL DROP\n" + _format_countdown(ftl_seconds_remaining)
	if GameState.quest_step == GameState.QUEST_DIAGNOSE_LIFE_SUPPORT:
		return "LIFE SUPPORT\nDIAGNOSTIC READY"
	if GameState.quest_step == GameState.QUEST_DIAL_LIME_PLANET:
		return "GATE CONTROL\nLIME WORLD LOCK"
	if GameState.is_lime_gate_open():
		return "GATE ACTIVE\nLIME WORLD"
	return "GATE CONTROL\nSTANDBY"
