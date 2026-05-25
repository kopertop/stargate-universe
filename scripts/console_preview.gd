@tool
extends Node3D

# Editor workbench for the gate-console screen plate. Attach to the root of
# scenes/console_test.tscn. Runs in @tool mode so changes to the @export
# values below update the screen LIVE in the editor (no F6 needed).
#
# Workflow:
#   1. Open scenes/console_test.tscn in the editor.
#   2. Select the "ConsoleTest" root node.
#   3. In the Inspector, edit:
#        screen_text   — what shows on the screen (use \n for newlines)
#        bg_color      — background color of the screen
#        text_color    — foreground text color
#        font_size     — text size in pixels (in the viewport)
#        emission_energy — how brightly the plate glows
#   4. When the screen looks how you want it, copy the values into
#      scripts/gate_console.gd::_build_screen_readout() and
#      scripts/gate_console.gd::_apply_text_to_plate().

@export_multiline var screen_text: String = "GATE CONTROL\nSTANDBY":
	set(value):
		screen_text = value
		_refresh_label()

@export var bg_color: Color = Color(0.03, 0.04, 0.06):
	set(value):
		bg_color = value
		_refresh_bg()

@export var text_color: Color = Color(0.32, 0.72, 1.0):
	set(value):
		text_color = value
		_refresh_label()

@export var font_size: int = 64:
	set(value):
		font_size = value
		_refresh_label()

@export_range(0.0, 5.0, 0.1) var emission_energy: float = 1.5:
	set(value):
		emission_energy = value
		_refresh_material()

@export_range(64, 1024, 16) var viewport_width: int = 640:
	set(value):
		viewport_width = value
		_refresh_viewport_size()

@export_range(64, 1024, 16) var viewport_height: int = 280:
	set(value):
		viewport_height = value
		_refresh_viewport_size()

# Toggle this in the Inspector to force a full rebuild + texture re-apply.
# Useful when the @tool auto-refresh misses a SubViewport draw frame.
@export var refresh_now: bool = false:
	set(value):
		refresh_now = false  # acts like a button — always reset
		_full_rebuild()

var _viewport: SubViewport
var _bg: ColorRect
var _label: Label
var _plate: MeshInstance3D


func _ready() -> void:
	_full_rebuild()


func _full_rebuild() -> void:
	# Tear down any previous viewport so we always start clean — important
	# in @tool mode where _ready may fire multiple times across script reloads.
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_bg = null
	_label = null

	_build_viewport()
	_find_plate()
	# Force a viewport frame to render BEFORE sampling its texture.
	# RenderingServer.frame_post_draw is a signal that fires after every
	# rendered frame, in BOTH editor and runtime contexts (where
	# get_tree().process_frame is unreliable in @tool mode).
	await RenderingServer.frame_post_draw
	_refresh_material()


func _build_viewport() -> void:
	# Skip if already built (e.g. tool script re-run in editor).
	if _viewport != null and is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = "ReadoutViewport"
	_viewport.size = Vector2i(viewport_width, viewport_height)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	add_child(_viewport)

	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = bg_color
	_viewport.add_child(_bg)

	_label = Label.new()
	_label.name = "TextLabel"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = screen_text
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", text_color)
	_viewport.add_child(_label)


func _find_plate() -> void:
	var stage: Node = get_node_or_null("Stage")
	if stage == null:
		push_warning("console_preview: no Stage child found")
		return
	var p: Node = stage.get_node_or_null("ScreenPlate")
	if p is MeshInstance3D:
		_plate = p
	else:
		push_warning("console_preview: Stage has no ScreenPlate MeshInstance3D")


func _refresh_bg() -> void:
	if _bg != null:
		_bg.color = bg_color
	_schedule_material_resync()


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = screen_text
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_font_size_override("font_size", font_size)
	_schedule_material_resync()


func _refresh_viewport_size() -> void:
	if _viewport != null:
		_viewport.size = Vector2i(viewport_width, viewport_height)
	_schedule_material_resync()


# After any Inspector change, the ColorRect/Label update visually but the
# ViewportTexture sampled by the plate's material may need a fresh frame.
# Wait one more rendered frame then poke the plate's material so the
# texture reference stays live in editor.
func _schedule_material_resync() -> void:
	if _plate == null or _viewport == null:
		return
	await RenderingServer.frame_post_draw
	_refresh_material()


func _refresh_material() -> void:
	if _plate == null or _viewport == null:
		return
	var existing: Material = _plate.material_override
	if not (existing is StandardMaterial3D):
		return
	var src: StandardMaterial3D = existing
	var mat: StandardMaterial3D = src.duplicate()
	var tex: Texture = _viewport.get_texture()
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = tex
	mat.emission = Color.WHITE
	mat.emission_texture = tex
	mat.emission_energy_multiplier = emission_energy
	_plate.material_override = mat
