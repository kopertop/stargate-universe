class_name BridgeConsole
extends Interactable

# In-world Bridge console that opens a configuration panel for tuning the Core
# Game Loop (issue #133). Modeled on AssignmentConsole / FloorCodeTerminal.
#
# Gating: only interactive after the player has discovered a Bridge room
# (ProceduralShip.is_bridge_discovered()). Before discovery the prompt reads
# "locked" and interact() is a no-op — the Interactable.enabled flag is NOT
# used for this because enabled=false also hides the prompt, and we want to
# show a "locked" hint.
#
# Config values live in Settings (user://settings.cfg, LOOP_SECTION). Each
# slider writes Settings.set_*(), which clamps, emits *_changed, persists, AND
# pushes the value into GameState.ship_phase_override / planet_window_override
# so #130 (FtlLoop) reads the edited value through GameState.*_base_seconds()
# — a single accessor path with no duplicate storage.
#
# Respects SceneRouter.instant_mode (returns early — no CanvasLayer).

# Set by room.gd BEFORE add_child so _ready reads the correct room id.
var console_room_id: String = ""

var _layer: CanvasLayer = null
var _root: Control = null
var _open: bool = false

# Slider widget references — cached to refresh when Settings.*_changed fires.
var _ship_val_lbl: Label = null
var _planet_val_lbl: Label = null
var _band_val_lbl: Label = null


func _ready() -> void:
	super()
	# Interactable._ready sets collision_layer=4; add layer 1 (world) so the
	# room camera-curtain logic doesn't clip through it.
	collision_layer = 1 | 4
	_build_visual()
	_refresh_prompt()


# ── visual ────────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.16, 0.20)
	mat.metallic = 0.60
	mat.roughness = 0.40

	var body: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.07, 0.80, 0.55)
	body.mesh = box
	body.material_override = mat
	body.position = Vector3(0.0, 1.30, 0.0)
	add_child(body)

	# Amber/gold screen — distinct from the purple assignment console.
	var screen_col: Color = Color(1.0, 0.65, 0.10)
	var screen_mat: StandardMaterial3D = StandardMaterial3D.new()
	screen_mat.albedo_color = screen_col
	screen_mat.emission_enabled = true
	screen_mat.emission = screen_col
	screen_mat.emission_energy_multiplier = 2.4

	var screen: MeshInstance3D = MeshInstance3D.new()
	var screen_box: BoxMesh = BoxMesh.new()
	screen_box.size = Vector3(0.04, 0.55, 0.40)
	screen.mesh = screen_box
	screen.material_override = screen_mat
	screen.position = Vector3(0.03, 1.30, 0.0)
	add_child(screen)

	var lbl: Label3D = Label3D.new()
	lbl.text = "BRIDGE\nCONFIG"
	lbl.pixel_size = 0.0036
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 5
	lbl.shaded = false
	lbl.modulate = Color(1.0, 0.88, 0.60, 1.0)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.position = Vector3(0.06, 1.82, 0.0)
	add_child(lbl)


func _refresh_prompt() -> void:
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	var discovered: bool = ps != null and ps.call("is_bridge_discovered") == true
	if discovered:
		prompt = "Configure Core Loop timing"
	else:
		prompt = "[Bridge locked — discover the Bridge first]"


# ── interaction ───────────────────────────────────────────────────────────────

func _on_interact(_by: Node) -> void:
	# Gating: locked before bridge discovery.
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	var discovered: bool = ps != null and ps.call("is_bridge_discovered") == true
	if not discovered:
		return  # Still shows prompt but does nothing.

	# Headless / instant_mode: no CanvasLayer — return immediately.
	var router: Node = get_node_or_null("/root/SceneRouter")
	var instant: bool = router != null and router.get("instant_mode") == true
	if instant:
		return

	if _open:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	if _open:
		return
	_open = true
	_build_ui()
	if _root != null:
		_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_menu() -> void:
	if not _open:
		return
	_open = false
	if _root != null:
		_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	if _layer != null:
		if _root != null:
			_root.visible = true
		return

	var settings: Node = get_node_or_null("/root/Settings")

	_layer = CanvasLayer.new()
	_layer.layer = 85
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.06, 0.88)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.gui_input.connect(_on_bg_input)
	_root.add_child(bg)

	var frame: PanelContainer = PanelContainer.new()
	frame.anchor_left = 0.25
	frame.anchor_right = 0.75
	frame.anchor_top = 0.15
	frame.anchor_bottom = 0.88
	_root.add_child(frame)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.10, 0.97)
	style.border_color = Color(1.0, 0.65, 0.10, 0.9)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	frame.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	frame.add_child(vbox)

	var title: Label = Label.new()
	title.text = "BRIDGE — CORE LOOP CONFIGURATION"
	title.add_theme_color_override("font_color", Color(1.0, 0.80, 0.30, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep0: HSeparator = HSeparator.new()
	vbox.add_child(sep0)

	var note: Label = Label.new()
	note.text = "Changes take effect on the next FTL jump."
	note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70, 1.0))
	note.add_theme_font_size_override("font_size", 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note)

	# ── Ship phase slider ──────────────────────────────────────────────────────
	var ship_cur: float = 1800.0
	if settings != null:
		ship_cur = float(settings.get("ship_phase_seconds"))

	_add_slider_row(vbox, "Ship Phase Duration",
		"Time aboard ship between gate drops (seconds)",
		60.0, 7200.0, ship_cur,
		func(v: float) -> void:
			if settings != null:
				settings.call("set_ship_phase_seconds", v)
			_ship_val_lbl.text = "%.0f s  (%.1f min)" % [v, v / 60.0],
		func(lbl: Label) -> void: _ship_val_lbl = lbl,
		"%.0f s  (%.1f min)" % [ship_cur, ship_cur / 60.0])

	# ── Planet phase slider ────────────────────────────────────────────────────
	var planet_cur: float = 1200.0
	if settings != null:
		planet_cur = float(settings.get("planet_phase_seconds"))

	_add_slider_row(vbox, "Planet Window Duration",
		"Gate-run window duration (seconds)",
		60.0, 7200.0, planet_cur,
		func(v: float) -> void:
			if settings != null:
				settings.call("set_planet_phase_seconds", v)
			_planet_val_lbl.text = "%.0f s  (%.1f min)" % [v, v / 60.0],
		func(lbl: Label) -> void: _planet_val_lbl = lbl,
		"%.0f s  (%.1f min)" % [planet_cur, planet_cur / 60.0])

	# ── Randomization band slider ──────────────────────────────────────────────
	var band_cur: float = 0.20
	if settings != null:
		band_cur = float(settings.get("randomization_band"))

	_add_slider_row(vbox, "Randomization Band",
		"Phase-duration jitter (±fraction around base, 0 = exact)",
		0.0, 0.5, band_cur,
		func(v: float) -> void:
			if settings != null:
				settings.call("set_randomization_band", v)
			_band_val_lbl.text = "±%.0f%%" % (v * 100.0),
		func(lbl: Label) -> void: _band_val_lbl = lbl,
		"±%.0f%%" % (band_cur * 100.0))

	# ── Jump destination stub ──────────────────────────────────────────────────
	var dest_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(dest_row)
	var dest_lbl: Label = Label.new()
	dest_lbl.text = "Jump Destination"
	dest_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dest_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85, 1.0))
	dest_row.add_child(dest_lbl)
	var dest_btn: OptionButton = OptionButton.new()
	dest_btn.add_item("Any (automatic)")
	dest_btn.disabled = true
	dest_row.add_child(dest_btn)

	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 38)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_close_menu)
	vbox.add_child(close_btn)


# Helper: add a labeled slider row to vbox.
# value_label_setter is called with the Label so the outer scope can cache it.
func _add_slider_row(
		vbox: VBoxContainer,
		label_text: String,
		_hint: String,
		min_val: float,
		max_val: float,
		cur_val: float,
		on_change: Callable,
		cache_label: Callable,
		initial_text: String) -> void:

	var row_lbl: Label = Label.new()
	row_lbl.text = label_text
	row_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78, 1.0))
	row_lbl.add_theme_font_size_override("font_size", 15)
	vbox.add_child(row_lbl)

	var hbox: HBoxContainer = HBoxContainer.new()
	vbox.add_child(hbox)

	var slider: HSlider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = cur_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Step: 60 s for phase sliders; 0.01 for band.
	slider.step = 0.01 if max_val <= 1.0 else 60.0
	hbox.add_child(slider)

	var val_lbl: Label = Label.new()
	val_lbl.text = initial_text
	val_lbl.custom_minimum_size = Vector2(140, 0)
	val_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.40, 1.0))
	val_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(val_lbl)

	cache_label.call(val_lbl)
	slider.value_changed.connect(on_change)


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_close_menu()
