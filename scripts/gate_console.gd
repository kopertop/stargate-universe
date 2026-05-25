class_name GateConsole
extends Interactable

# Gate-room console. Two flavors switched by `kind`:
#   • "gate_control"   — Eli reads his notes; address book empty; gate is dormant.
#   • "ftl_countdown"  — live countdown to next FTL drop; ticks every frame.
#
# The console's text readout is rendered into a SubViewport (Label inside a
# ColorRect background) and then applied to the screen plate's emission
# texture — so the text appears AS the screen content, not as a floating label
# on top. Updating _vp_label.text every frame ticks the countdown live.

@export var kind: String = "gate_control"

# FTL countdown initial offset (matches the spec's "17h 42m 18s" beat from the
# arrival cinematic — feel free to tweak per scene if you want a different beat).
@export var ftl_seconds_remaining: float = 63738.0

# Off-screen viewport that renders the readout text. Its output texture is
# wired into the screen plate's emission_texture so the text IS the screen.
const SCREEN_TEX_SIZE: Vector2i = Vector2i(640, 280)
const TEXT_FONT_SIZE: int = 64
var _viewport: SubViewport
var _vp_label: Label
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

func _process(delta: float) -> void:
	if _vp_label != null:
		_vp_label.text = _readout_text()
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

func _build_screen_readout() -> void:
	# Build an off-screen SubViewport that renders the readout text on a
	# blue background. Then apply the viewport's render texture as the
	# screen plate's emission_texture so the text becomes part of the
	# screen's emissive surface (not a floating label on top).
	_viewport = SubViewport.new()
	_viewport.name = "ReadoutViewport"
	_viewport.size = SCREEN_TEX_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	# Opaque background — we want the WHOLE screen plate to glow blue with
	# the text rendered AS the screen content (not a translucent overlay).
	_viewport.transparent_bg = false
	add_child(_viewport)

	# DARK background — near-black so only the text glows. Inverts the
	# previous treatment (bright blue + dark text) per user direction. With
	# emission_energy_multiplier in play, "dark" stays dark (0.04 × 3.2 = 0.13)
	# while the bright tech-blue text clips toward white = looks like a glowing
	# Ancient CRT readout.
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06, 1.0)
	_viewport.add_child(bg)

	# Tech-blue text — the same color the screen background USED to be.
	# Now the wording IS the bright element on the screen.
	_vp_label = Label.new()
	_vp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vp_label.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_vp_label.add_theme_color_override("font_color", RoomBuilder.CONSOLE_SCREEN_COLOR_DEFAULT)
	_vp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_vp_label.add_theme_constant_override("outline_size", 4)
	_vp_label.text = _readout_text()
	_viewport.add_child(_vp_label)

	# Wait one frame so the viewport has actually rendered before we sample
	# its texture (otherwise the plate flashes black on first frame).
	await get_tree().process_frame
	_apply_text_to_plate()


# Find the screen plate built by RoomBuilder.attach_console_mesh and swap
# its material so the emission samples our SubViewport texture. The plate
# was named "ScreenPlate" by attach_console_mesh specifically so we can
# find it here.
func _apply_text_to_plate() -> void:
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
	var existing: Material = plate_mi.material_override
	if existing == null or not (existing is StandardMaterial3D):
		return
	var src: StandardMaterial3D = existing
	var mat: StandardMaterial3D = src.duplicate()
	# Sample the viewport for BOTH albedo (the plate's base color in non-emissive
	# light) and emission (the bright self-lit content). albedo_color stays white
	# so the texture passes through unmodified.
	# Drop emission_energy_multiplier to 1.5 so the tech-blue text doesn't
	# saturate to white — at the shared 3.2 the green+blue channels clip and
	# the text reads as washed white instead of blue. 1.5 keeps it glowy
	# while preserving the source colour.
	var tex: Texture = _viewport.get_texture()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = tex
	mat.emission = Color.WHITE
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 1.5
	plate_mi.material_override = mat

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
