extends Node

# @no-save: UI overlay only. The loadout it edits is owned by the Inventory
# autoload (which IS save-registered); this panel holds no persistent state.
#
# Character paper-doll / equip pane (#74). A WoW-style "character pane" to view
# and change the crew loadout: one slot widget per equipment slot
# (head / torso / back / legs) showing the equipped item's icon (or an
# empty-slot glyph), beside a scrollable list of every equippable item the
# player currently carries. Clicking an inventory item equips it into its slot
# (Inventory.equip); clicking a filled slot unequips it (Inventory.unequip).
#
# The 3D character model stays in sync automatically: EquipmentMount (#72) and
# this panel both listen to Inventory.equipment_changed — equip/unequip flips
# the ONE _equipped registry in Inventory and both views refresh. The panel
# never touches the model directly.
#
# Built programmatically onto its own CanvasLayer so it attaches to every
# gameplay scene without per-scene wiring — the same pattern as PauseMenu /
# KinoRemote. Toggled with [C]; respects the input + pause gotchas:
#   - Only the OPEN path of the toggle is gated (memory:
#     feedback_godot_autoload_input_order) — when another overlay (pause menu
#     or Kino map) is up, [C] is ignored so we don't stack panes.
#   - Mouse mode is forced VISIBLE on open and the prior mode restored on close
#     so mouselook resumes without an extra RMB tap (memory:
#     feedback_godot_paused_input_stale_mouse_mode).
#   - The tree is paused while open and the panel processes ALWAYS.

# Palette mirrors the shared WoW UI skin (hud.gd SKIN_* / pause_menu styleboxes)
# for visual cohesion with the #31 cohesion pass.
const ACCENT: Color = Color(0.60, 0.78, 0.95, 0.85)        # primary cool-blue border
const ACCENT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)     # filled-slot / title accent
const PANEL_BG: Color = Color(0.04, 0.06, 0.09, 0.96)      # opaque dark fill
const SLOT_BG: Color = Color(0.06, 0.10, 0.15, 0.85)       # slot well fill
const TEXT_PRIMARY: Color = Color(0.95, 0.98, 1.0, 1.0)
const TEXT_DIM: Color = Color(0.70, 0.82, 0.95, 0.85)
const SLOT_SIZE: Vector2 = Vector2(72, 72)

# Empty-slot glyph per slot (Unicode). Display-only; communicates which body
# region the slot covers when nothing is equipped there.
const SLOT_GLYPH: Dictionary = {
	"head": "⛑",   # rescue helmet
	"torso": "\U0001f9ba",  # safety vest
	"back": "\U0001f392",   # backpack
	"legs": "\U0001f45f",   # athletic shoe
}

const SLOT_LABEL: Dictionary = {
	"head": "Head",
	"torso": "Torso",
	"back": "Back",
	"legs": "Legs",
}

var _layer: CanvasLayer
var _root: Control
var _panel: PanelContainer
var _slot_row: HBoxContainer
var _item_list: VBoxContainer
var _empty_label: Label

# slot -> the Panel widget for that slot. ONE registry of slot widgets keyed by
# slot id (not per-slot vars) so refresh iterates the collection uniformly.
var _slot_widgets: Dictionary = {}

var _open: bool = false
var _initialized: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Defer the UI build until autoloads finish wiring (KinoRemote / PauseMenu
	# share this deferral so input-order assumptions hold).
	call_deferred("_init_ui")


func _init_ui() -> void:
	if _initialized:
		return
	_initialized = true

	_layer = CanvasLayer.new()
	_layer.layer = 88  # Below PauseMenu (90), above the HUD/Kino map.
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_tree().root.add_child(_layer)

	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	# Dim backdrop swallows clicks so they don't bleed into the world below.
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_stylebox())
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = -240
	_panel.offset_bottom = 240
	_root.add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var header: Label = Label.new()
	header.text = "CHARACTER"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", ACCENT_GOLD)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	# Paper-doll: the four equipment slots in canonical order, in a row.
	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", 18)
	vbox.add_child(_slot_row)
	_build_slots()

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	var sub: Label = Label.new()
	sub.text = "EQUIPMENT"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub)

	# Scrollable list of every equippable item the player carries.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_item_list)

	_empty_label = Label.new()
	_empty_label.text = "No equipment in your pack."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 13)
	_empty_label.add_theme_color_override("font_color", TEXT_DIM)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.visible = false
	vbox.add_child(_empty_label)

	var footer: Label = Label.new()
	footer.text = "[C] / [Esc] Close"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.7))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(footer)

	_connect_inventory()


func _build_slots() -> void:
	var inv: Node = _inventory()
	var slots: Array = _slot_order(inv)
	for slot in slots:
		var slot_s: String = String(slot)
		var widget: Panel = _make_slot_widget(slot_s)
		_slot_row.add_child(widget)
		_slot_widgets[slot_s] = widget


# Canonical slot list — sourced from Inventory.EQUIP_SLOTS when available so the
# panel never hardcodes the slot set (single source of truth).
func _slot_order(inv: Node) -> Array:
	if inv != null:
		var s: Variant = inv.get("EQUIP_SLOTS")
		if s is Array and not (s as Array).is_empty():
			return s
	return ["head", "torso", "back", "legs"]


func _make_slot_widget(slot: String) -> Panel:
	var slot_panel: Panel = Panel.new()
	slot_panel.custom_minimum_size = SLOT_SIZE
	slot_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slot_panel.add_theme_stylebox_override("panel", _slot_stylebox(false))
	# Click a filled slot to unequip it; the handler bails on an empty slot.
	slot_panel.gui_input.connect(_on_slot_input.bind(slot))

	# Empty-slot glyph (shown when nothing equipped).
	var glyph: Label = Label.new()
	glyph.name = "Glyph"
	glyph.text = String(SLOT_GLYPH.get(slot, "?"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 30)
	glyph.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8, 0.55))
	glyph.anchor_right = 1.0
	glyph.anchor_bottom = 1.0
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(glyph)

	# Equipped-item icon (hidden until something is equipped).
	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.visible = false
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(icon)

	# Slot caption under the well (head / torso / …).
	var caption: Label = Label.new()
	caption.name = "Caption"
	caption.text = String(SLOT_LABEL.get(slot, slot))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", TEXT_DIM)
	caption.anchor_top = 1.0
	caption.anchor_right = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_top = 2
	caption.offset_bottom = 18
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(caption)

	return slot_panel


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("character_pane"):
		return
	# Title scene has no scene path registered — [C] there is a no-op so we
	# don't pop the pane before the player has started a game.
	if not _open and GameState.current_scene_path == "":
		return
	# Gate ONLY the OPEN path (memory: feedback_godot_autoload_input_order): if
	# another full-screen overlay is already up, don't stack the character pane.
	# While the pane IS open, [C] always closes it (so a user who opened it can
	# always toggle it back off).
	if not _open:
		var pause: Node = _autoload("PauseMenu")
		if pause != null and pause.get("_open") == true:
			return
		var kino: Node = _autoload("KinoRemote")
		if kino != null and kino.get("_open") == true:
			return
	get_viewport().set_input_as_handled()
	_toggle()


func _toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if not _initialized:
		_init_ui()
	_open = true
	_root.visible = true
	_refresh()
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t: SceneTree = _tree()
	if t != null:
		t.paused = true


func close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	var t: SceneTree = _tree()
	if t != null:
		t.paused = false
	# Restore prior mouselook capture and re-sync view.gd's bookkeeping the same
	# way PauseMenu / KinoRemote do on close (shared kino_closed signal).
	Input.mouse_mode = _saved_mouse_mode
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_signal("kino_closed"):
		gs.emit_signal("kino_closed")


func is_open() -> bool:
	return _open


# --- inventory wiring + refresh ----------------------------------------------

func _connect_inventory() -> void:
	var inv: Node = _inventory()
	if inv == null:
		return
	if inv.has_signal("equipment_changed") and not inv.is_connected("equipment_changed", _on_equipment_changed):
		inv.connect("equipment_changed", _on_equipment_changed)
	# Picking up / consuming items can change which equippables are available,
	# so refresh the browse list on any inventory mutation too.
	if inv.has_signal("changed") and not inv.is_connected("changed", _on_inventory_changed):
		inv.connect("changed", _on_inventory_changed)


func _on_equipment_changed(_slot: String, _item_id: String) -> void:
	if _open:
		_refresh()


func _on_inventory_changed() -> void:
	if _open:
		_refresh()


func _refresh() -> void:
	_refresh_slots()
	_refresh_item_list()


func _refresh_slots() -> void:
	var inv: Node = _inventory()
	for slot in _slot_widgets.keys():
		var widget: Panel = _slot_widgets[slot]
		if widget == null or not is_instance_valid(widget):
			continue
		var item_id: String = ""
		if inv != null and inv.has_method("equipped_in"):
			item_id = String(inv.call("equipped_in", slot))
		var icon: TextureRect = widget.get_node_or_null("Icon")
		var glyph: Label = widget.get_node_or_null("Glyph")
		var filled: bool = item_id != ""
		if icon != null:
			icon.visible = filled
			icon.texture = _icon_for(item_id) if filled else null
			widget.tooltip_text = ("%s  —  click to unequip" % _name_for(item_id)) if filled else ""
		if glyph != null:
			glyph.visible = not filled
		# Filled slots get the gold accent border; empty slots the cool-blue one.
		widget.add_theme_stylebox_override("panel", _slot_stylebox(filled))


func _refresh_item_list() -> void:
	if _item_list == null:
		return
	# Detach before queue_free so stale rows are gone immediately — queue_free
	# alone is deferred (memory: queue_free sync-cap trap), which would leave old
	# rows visible until the next frame (and never, in a headless test).
	for c in _item_list.get_children():
		_item_list.remove_child(c)
		c.queue_free()
	var inv: Node = _inventory()
	var rows: int = 0
	if inv != null and inv.has_method("entries"):
		for entry in inv.call("entries"):
			var id: String = String((entry as Dictionary).get("id", ""))
			if id == "" or not _is_equippable(inv, id):
				continue
			_item_list.add_child(_make_item_row(inv, id, int((entry as Dictionary).get("count", 0))))
			rows += 1
	if _empty_label != null:
		_empty_label.visible = rows == 0


func _make_item_row(inv: Node, item_id: String, count: int) -> Button:
	var slot: String = ""
	if inv.has_method("slot_of"):
		slot = String(inv.call("slot_of", item_id))
	var equipped: bool = inv.has_method("is_equipped") and inv.call("is_equipped", item_id) == true

	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, 40)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_color_override("font_color", TEXT_PRIMARY)
	row.add_theme_stylebox_override("normal", _row_stylebox(false))
	row.add_theme_stylebox_override("hover", _row_stylebox(true))
	row.add_theme_stylebox_override("pressed", _row_stylebox(true))
	row.add_theme_stylebox_override("focus", _row_stylebox(true))
	var suffix: String = "  (equipped)" if equipped else ("  x%d" % count if count > 1 else "")
	row.text = "  %s    [%s]%s" % [_name_for(item_id), String(SLOT_LABEL.get(slot, slot)), suffix]
	# Clicking a list item equips it into its slot (clean swap handled by
	# Inventory.equip). Already-equipped items are a no-op equip (harmless).
	row.pressed.connect(_on_item_pressed.bind(item_id))
	var audio: Node = _autoload("Audio")
	if audio != null and audio.has_method("attach_ui_hover"):
		audio.call("attach_ui_hover", row)
	return row


func _on_item_pressed(item_id: String) -> void:
	var inv: Node = _inventory()
	if inv == null or not inv.has_method("equip"):
		return
	inv.call("equip", item_id)
	# UI refresh happens via the equipment_changed signal.


func _on_slot_input(event: InputEvent, slot: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var inv: Node = _inventory()
	if inv == null:
		return
	var item_id: String = ""
	if inv.has_method("equipped_in"):
		item_id = String(inv.call("equipped_in", slot))
	# Click an empty slot: nothing to do. Click a filled slot: unequip it.
	if item_id == "":
		return
	if inv.has_method("unequip"):
		inv.call("unequip", slot)


# --- catalog helpers ---------------------------------------------------------

func _is_equippable(inv: Node, item_id: String) -> bool:
	if inv != null and inv.has_method("is_equippable"):
		return inv.call("is_equippable", item_id) == true
	return false


func _name_for(item_id: String) -> String:
	var inv: Node = _inventory()
	if inv != null and inv.has_method("definition"):
		var def: Variant = inv.call("definition", item_id)
		if def is Dictionary:
			return String((def as Dictionary).get("name", item_id))
	return item_id


func _icon_for(item_id: String) -> Texture2D:
	var inv: Node = _inventory()
	if inv == null or not inv.has_method("definition"):
		return null
	var def: Variant = inv.call("definition", item_id)
	if not (def is Dictionary):
		return null
	var path: String = String((def as Dictionary).get("icon", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# --- styling -----------------------------------------------------------------

func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	return sb


func _slot_stylebox(filled: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = SLOT_BG
	sb.border_color = ACCENT_GOLD if filled else ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	# Reserve room for the caption that anchors to the bottom edge.
	sb.content_margin_bottom = 16
	return sb


func _row_stylebox(active: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.44, 0.78, 0.55) if active else Color(0.06, 0.10, 0.15, 0.7)
	sb.border_color = ACCENT if active else Color(0.4, 0.6, 0.8, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	return sb


# --- autoload access ---------------------------------------------------------

func _inventory() -> Node:
	return _autoload("Inventory")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = _tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
