class_name ElevatorPanel
extends Interactable

# Wall-mounted elevator control panel. Spawned in elevator rooms by room.gd.
# Opens a floor-selection overlay with two modes (issue #132):
#
#   POWER OFFLINE — fuses not yet seated / mini-game not completed.
#     Shows a "POWER OFFLINE" banner and a "RESTORE POWER" button.
#     Floor rows are visible but disabled.
#
#   POWER ONLINE — elevator restored.
#     LOCKED-UNKNOWN  — access code not found; "ACCESS CODE REQUIRED" + disabled.
#     LOCKED-KNOWN    — code found; cost label + "UNLOCK" button.
#     UNLOCKED        — "TRAVEL" button active.
#
# Down-floors (SL-1, SL-2…) are hidden until ProceduralShip.is_bridge_discovered()
# returns true — Bridge discovery reveals the lower decks on the panel.
# Down-floors are elevator-only (no stairs), so they obey the same code+parts gate
# as upper floors 3+.
#
# Unlock → ProceduralShip.unlock_floor(n) (verifies code + spends cost).
# Travel → GameState.next_room_id = floor_entry_room + SceneRouter.change_to(room.tscn).
#
# Respects SceneRouter.instant_mode: skips UI animation, operates synchronously.
# Connects to ProceduralShip.elevator_power_changed to refresh UI on power restore.

# How many upper floors beyond Floor 2 the panel shows as options (floors 3…N).
const MAX_FLOORS_SHOWN: int = 3

var _layer: CanvasLayer = null
var _root: Control = null
var _open: bool = false
# Ordered list of floor indices shown as rows. Built in _build_ui / refreshed in
# _refresh_ui. Explicit list so up- and down-floors share identical row machinery;
# avoids the brittle fn=i+2 index math that would mis-map labels to buttons for
# negative floors. ONE list — no parallel _down_floors registry.
var _panel_floors: Array[int] = []
# Cache row labels so _refresh_ui doesn't rebuild from scratch on every signal.
var _floor_labels: Array[Label] = []
var _floor_buttons: Array[Button] = []
# Power banner label — shown/hidden based on ProceduralShip.is_elevator_powered().
var _power_banner: Label = null
var _restore_btn: Button = null


func _ready() -> void:
	super()
	# Interactable._ready() sets collision_layer = 4. Panels also need layer 1
	# so the player capsule doesn't clip through the housing mesh.
	collision_layer = 1 | 4
	_build_visual()
	prompt = "Access elevator panel"
	# Connect to power-change signal so the open UI updates without re-opening.
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	if ps != null:
		ps.elevator_power_changed.connect(_on_elevator_power_changed)


# ── visual ────────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	# Small wall panel: dark housing + bright status strip + label.
	# Strip color reflects power state at build time only; _refresh_ui drives
	# runtime appearance so this never reads power state directly.
	var housing_mat: StandardMaterial3D = StandardMaterial3D.new()
	housing_mat.albedo_color = Color(0.18, 0.18, 0.21)
	housing_mat.metallic = 0.55
	housing_mat.roughness = 0.42

	var housing: MeshInstance3D = MeshInstance3D.new()
	var housing_box: BoxMesh = BoxMesh.new()
	housing_box.size = Vector3(0.08, 0.80, 0.55)
	housing.mesh = housing_box
	housing.material_override = housing_mat
	housing.position = Vector3(0.0, 1.35, 0.0)
	add_child(housing)

	# Emissive status strip — cyan when powered, amber when offline.
	var strip_mat: StandardMaterial3D = StandardMaterial3D.new()
	var strip_col: Color = Color(0.30, 0.85, 1.0)
	strip_mat.albedo_color = strip_col
	strip_mat.emission_enabled = true
	strip_mat.emission = strip_col
	strip_mat.emission_energy_multiplier = 2.5

	var strip: MeshInstance3D = MeshInstance3D.new()
	var strip_box: BoxMesh = BoxMesh.new()
	strip_box.size = Vector3(0.04, 0.66, 0.42)
	strip.mesh = strip_box
	strip.material_override = strip_mat
	strip.position = Vector3(0.03, 1.35, 0.0)
	add_child(strip)

	var lbl: Label3D = Label3D.new()
	lbl.text = "ELEVATOR\nFLOOR ACCESS"
	lbl.pixel_size = 0.0038
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 6
	lbl.shaded = false
	lbl.modulate = Color(0.92, 0.94, 0.98, 1.0)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	lbl.position = Vector3(0.06, 1.85, 0.0)
	add_child(lbl)


# ── interaction ───────────────────────────────────────────────────────────────

func _on_interact(_by: Node) -> void:
	var router: Node = get_node_or_null("/root/SceneRouter")
	var instant: bool = router != null and router.get("instant_mode") == true
	if instant:
		# In headless/instant_mode, no UI to show — the panel is inert unless
		# a test calls unlock_floor / travel directly.
		return
	AudioZones.play_console_beep()
	if _open:
		_close_panel()
	else:
		_open_panel()


func _open_panel() -> void:
	if _open:
		return
	_open = true
	_build_ui()
	if _root != null:
		_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_panel() -> void:
	if not _open:
		return
	_open = false
	if _root != null:
		_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	if _layer != null:
		_refresh_ui()
		return

	_layer = CanvasLayer.new()
	_layer.layer = 85
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	# Semi-transparent backdrop.
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.06, 0.88)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.gui_input.connect(_on_bg_input)
	_root.add_child(bg)

	# Centered panel.
	var frame: PanelContainer = PanelContainer.new()
	frame.anchor_left = 0.3
	frame.anchor_right = 0.7
	frame.anchor_top = 0.2
	frame.anchor_bottom = 0.8
	_root.add_child(frame)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.12, 0.97)
	style.border_color = Color(0.30, 0.75, 1.0, 0.9)
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
	title.text = "ELEVATOR — FLOOR ACCESS CONTROL"
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# ── Power offline banner (hidden when powered) ──
	_power_banner = Label.new()
	_power_banner.text = "POWER OFFLINE — Seat required fuses and restore main bus."
	_power_banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15, 1.0))
	_power_banner.add_theme_font_size_override("font_size", 14)
	_power_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_power_banner)

	_restore_btn = Button.new()
	_restore_btn.text = "RESTORE POWER"
	_restore_btn.custom_minimum_size = Vector2(0, 40)
	_restore_btn.focus_mode = Control.FOCUS_NONE
	_restore_btn.add_theme_font_size_override("font_size", 15)
	_restore_btn.pressed.connect(_on_restore_power)
	vbox.add_child(_restore_btn)

	var sep_power: HSeparator = HSeparator.new()
	vbox.add_child(sep_power)

	# Build the ordered floor list: upper floors first (2…MAX_FLOORS_SHOWN+1),
	# then down-floors (-1…MIN_FLOOR) only when Bridge is discovered.
	# ONE list — indices are explicit so label/button mapping is never ambiguous.
	_panel_floors.clear()
	for fn in range(2, MAX_FLOORS_SHOWN + 1):
		_panel_floors.append(fn)
	if ProceduralShip.is_bridge_discovered():
		var min_fl: int = ProceduralShip.MIN_FLOOR
		for fn in range(-1, min_fl - 1, -1):
			_panel_floors.append(fn)

	# Floor rows — one per floor in _panel_floors.
	_floor_labels.clear()
	_floor_buttons.clear()
	for fn in _panel_floors:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)

		var floor_lbl: Label = Label.new()
		# SL-n label for negative floors; FLOOR n for positive.
		floor_lbl.text = "SL-%d" % (-fn) if fn < 0 else "FLOOR %d" % fn
		floor_lbl.custom_minimum_size = Vector2(90, 0)
		floor_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0, 1.0))
		floor_lbl.add_theme_font_size_override("font_size", 16)
		row.add_child(floor_lbl)

		var status_lbl: Label = Label.new()
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(status_lbl)
		_floor_labels.append(status_lbl)

		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(120, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_floor_button.bind(fn))
		row.add_child(btn)
		_floor_buttons.append(btn)

	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	var close_btn: Button = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_close_panel)
	vbox.add_child(close_btn)

	_refresh_ui()


func _refresh_ui() -> void:
	var powered: bool = ProceduralShip.is_elevator_powered()

	# Power banner + restore button visibility.
	if _power_banner != null:
		_power_banner.visible = not powered
	if _restore_btn != null:
		_restore_btn.visible = not powered

	# Iterate via _panel_floors so label/button index mapping is never ambiguous.
	# _panel_floors is built once in _build_ui; both up- and down-floors share
	# the same machinery here.
	for i in _panel_floors.size():
		if i >= _floor_labels.size() or i >= _floor_buttons.size():
			break
		var fn: int = _panel_floors[i]
		var lbl: Label = _floor_labels[i]
		var btn: Button = _floor_buttons[i]

		if not powered:
			# Elevator offline — floor rows visible but all disabled.
			lbl.text = "UNAVAILABLE"
			lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50, 1.0))
			btn.text = "OFFLINE"
			btn.disabled = true
			continue

		var cost: int = ProceduralShip.floor_unlock_cost(fn)
		var inv: Node = get_node_or_null("/root/Inventory")
		var held: int = inv.call("count", ProceduralShip.FLOOR_UNLOCK_ITEM) if inv != null else 0

		if ProceduralShip.is_floor_unlocked(fn):
			lbl.text = "UNLOCKED"
			lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55, 1.0))
			btn.text = "TRAVEL"
			btn.disabled = false
		elif ProceduralShip.is_floor_code_known(fn):
			var suffix: String = "  [%d/%d %s]" % [held, cost, ProceduralShip.FLOOR_UNLOCK_ITEM]
			lbl.text = "CODE FOUND — COST: %d PARTS%s" % [cost, suffix]
			lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.36, 1.0))
			btn.text = "UNLOCK"
			btn.disabled = (held < cost)
		else:
			lbl.text = "ACCESS CODE REQUIRED"
			lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70, 1.0))
			btn.text = "LOCKED"
			btn.disabled = true


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_close_panel()


# Called when the player presses "RESTORE POWER".
# Seam: the real mini-game scene later launches here instead of the stub call.
func _on_restore_power() -> void:
	var ps: Node = get_node_or_null("/root/ProceduralShip")
	if ps == null:
		return
	# Stub path: solve mini-game deterministically then attempt restore.
	ps.call("solve_elevator_minigame")
	var ok: bool = ps.call("restore_elevator_power")
	if ok:
		_refresh_ui()
	else:
		# Not enough fuses — refresh to show any partial state.
		_refresh_ui()


func _on_floor_button(fn: int) -> void:
	if ProceduralShip.is_floor_unlocked(fn):
		_travel_to_floor(fn)
	elif ProceduralShip.is_floor_code_known(fn):
		var ok: bool = ProceduralShip.unlock_floor(fn)
		if ok:
			_refresh_ui()
		else:
			# Show feedback (refresh to update cost label).
			_refresh_ui()


# Slot for ProceduralShip.elevator_power_changed signal.
func _on_elevator_power_changed(_powered: bool) -> void:
	if _layer != null:
		_refresh_ui()


func _travel_to_floor(fn: int) -> void:
	_close_panel()
	AudioZones.play_elevator_hum()
	var landing_id: String = ProceduralShip.floor_entry_room(fn)
	GameState.next_room_id = landing_id
	var router: Node = get_node_or_null("/root/SceneRouter")
	if router != null:
		router.call("change_to", "res://scenes/room.tscn", "FromElevator")
