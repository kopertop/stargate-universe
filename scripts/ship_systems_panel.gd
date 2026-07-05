class_name ShipSystemsPanel
# Path-based extends: class_name registration can lag in headless `-s` runs
# (same reason room.gd preloads its scripts), so don't rely on `ConsolePanel`
# resolving at parse time.
extends "res://scripts/console_panel.gd"

# @no-save: transient UI — state it displays lives in ShipState.
#
# The control-room console surface for the merged-deck flow: remote door
# control (open / close / lock any door on the ship) plus a per-room systems
# readout (structural damage %, shield strength %, installed module). The
# control interface room has Destiny's own schematic, so the list shows every
# door and room — no fog-of-war here (the handheld Kino map keeps its own).

const TAB_DOORS: int = 0
const TAB_ROOMS: int = 1

var _tab: int = TAB_DOORS
var _list: VBoxContainer = null
var _tab_buttons: Array[Button] = []


func _build_ui() -> void:
	var column: VBoxContainer = build_frame("DESTINY — SHIP SYSTEMS")

	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	for spec in [["Doors", TAB_DOORS], ["Rooms", TAB_ROOMS]]:
		var btn: Button = Button.new()
		btn.text = String(spec[0])
		btn.toggle_mode = true
		btn.pressed.connect(_on_tab_pressed.bind(int(spec[1])))
		Audio.attach_ui_hover(btn)
		tabs.add_child(btn)
		_tab_buttons.append(btn)

	_list = make_scroll_list(column)
	build_close_button(column)
	_refresh()


func _on_tab_pressed(tab: int) -> void:
	_tab = tab
	_refresh()


func _refresh() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = (i == _tab)
	for child in _list.get_children():
		child.queue_free()
	if _tab == TAB_DOORS:
		_fill_doors()
	else:
		_fill_rooms()


# ---- Doors tab ---------------------------------------------------------------

func _fill_doors() -> void:
	var pairs: Array = ShipLayout.door_pairs()
	pairs.sort_custom(_sort_pairs)
	for pair: Dictionary in pairs:
		var a: String = String(pair["a"])
		var b: String = String(pair["b"])
		var is_lift: bool = String(pair["dir"]) == "elevator"
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list.add_child(row)

		var door_id: String = GameState.door_key(a, b)
		var name_label: Label = make_label("%s ↔ %s" % [_room_name(a), _room_name(b)])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(380.0, 0.0)
		row.add_child(name_label)

		if is_lift:
			# Inter-deck lift pair — gated by main power, not by door state.
			row.add_child(make_label(
				"LIFT — %s" % ("ONLINE" if GameState.elevator_repaired else "POWER OFFLINE"),
				OK_COLOR if GameState.elevator_repaired else WARN_COLOR))
			continue

		var open: bool = ShipState.is_door_open(door_id)
		var locked: bool = ShipState.is_door_locked(door_id)
		var status: String = "LOCKED" if locked else ("OPEN" if open else "CLOSED")
		var status_color: Color = WARN_COLOR if locked else (OK_COLOR if open else DIM_TEXT_COLOR)
		var status_label: Label = make_label(status, status_color)
		status_label.custom_minimum_size = Vector2(80.0, 0.0)
		row.add_child(status_label)

		var toggle_btn: Button = Button.new()
		toggle_btn.text = "Close" if open else "Open"
		toggle_btn.disabled = locked
		toggle_btn.pressed.connect(_on_door_toggle.bind(door_id))
		Audio.attach_ui_hover(toggle_btn)
		row.add_child(toggle_btn)

		var lock_btn: Button = Button.new()
		lock_btn.text = "Unlock" if locked else "Lock"
		lock_btn.pressed.connect(_on_door_lock.bind(door_id))
		Audio.attach_ui_hover(lock_btn)
		row.add_child(lock_btn)


func _on_door_toggle(door_id: String) -> void:
	var target: bool = not ShipState.is_door_open(door_id)
	if ShipState.set_door_open(door_id, target):
		GameState.add_log("Console: door %s %s." % [door_id, "opened" if target else "closed"])
	_refresh()


func _on_door_lock(door_id: String) -> void:
	var target: bool = not ShipState.is_door_locked(door_id)
	ShipState.set_door_locked(door_id, target)
	GameState.add_log("Console: door %s %s." % [door_id, "locked" if target else "unlocked"])
	_refresh()


# ---- Rooms tab ---------------------------------------------------------------

func _fill_rooms() -> void:
	var rooms: Array = ShipLayout.all_rooms()
	rooms.sort_custom(_sort_rooms)
	for room: Dictionary in rooms:
		var room_id: String = String(room["id"])
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list.add_child(row)

		var name_label: Label = make_label("%s  (deck %d)" % [_room_name(room_id), int(room.get("floor", 0))])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(320.0, 0.0)
		row.add_child(name_label)

		var dmg: float = ShipState.room_damage(room_id)
		var dmg_color: Color = OK_COLOR if dmg < 5.0 else (WARN_COLOR if dmg > ShipState.BUILD_DAMAGE_THRESHOLD else TEXT_COLOR)
		var dmg_label: Label = make_label("DMG %3d%%" % int(round(dmg)), dmg_color)
		dmg_label.custom_minimum_size = Vector2(90.0, 0.0)
		row.add_child(dmg_label)

		var shield: float = ShipState.room_shield(room_id)
		var shield_color: Color = OK_COLOR if shield > 75.0 else (WARN_COLOR if shield < 35.0 else TEXT_COLOR)
		var shield_label: Label = make_label("SHD %3d%%" % int(round(shield)), shield_color)
		shield_label.custom_minimum_size = Vector2(90.0, 0.0)
		row.add_child(shield_label)

		var module_id: String = ShipState.room_module(room_id)
		var module_text: String = "—"
		if module_id != "":
			module_text = String(ShipState.module(module_id).get("name", module_id))
		elif not ShipState.is_room_buildable(room_id):
			module_text = ""
		row.add_child(make_label(module_text, DIM_TEXT_COLOR))


# ---- helpers -------------------------------------------------------------------

func _room_name(room_id: String) -> String:
	var row: Dictionary = ShipLayout.room(room_id)
	var display: String = String(row.get("name", room_id))
	# Several corridors share the JSON name "Corridor"; disambiguate with the id.
	if display == "Corridor":
		return room_id.capitalize()
	return display


func _sort_pairs(a: Dictionary, b: Dictionary) -> bool:
	return _room_name(String(a["a"])) + _room_name(String(a["b"])) \
		< _room_name(String(b["a"])) + _room_name(String(b["b"]))


func _sort_rooms(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("floor", 0)) != int(b.get("floor", 0)):
		return int(a.get("floor", 0)) < int(b.get("floor", 0))
	return _room_name(String(a["id"])) < _room_name(String(b["id"]))
