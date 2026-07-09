class_name BuildPanel
# Path-based extends — class_name registration can lag in headless `-s` runs.
extends "res://scripts/console_panel.gd"

# @no-save: transient UI — the chosen module persists in ShipState.
#
# Per-room build console surface: shows the room's structural damage and
# shield readout, the currently installed module, and the catalog of modules
# (data/room_modules.json) this room type accepts. Building above the damage
# threshold is refused with the repair-robot pointer (see ShipState.build_blocker
# and design/gdd/ship-building-mode.md).

var room_id: String = ""

var _status_label: Label = null
var _blocker_label: Label = null
var _list: VBoxContainer = null


func _build_ui() -> void:
	var room: Dictionary = ShipLayout.room(room_id)
	var display: String = String(room.get("name", room_id))
	var column: VBoxContainer = build_frame("ROOM SYSTEMS — %s" % display.to_upper(), 760.0)

	_status_label = make_label("", TEXT_COLOR, 16)
	column.add_child(_status_label)
	_blocker_label = make_label("", WARN_COLOR, 14)
	_blocker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_blocker_label)
	column.add_child(HSeparator.new())
	column.add_child(make_label("AVAILABLE MODULES", TITLE_COLOR, 16))

	_list = make_scroll_list(column)
	build_close_button(column)
	_refresh()


func _refresh() -> void:
	var dmg: float = ShipState.room_damage(room_id)
	var shield: float = ShipState.room_shield(room_id)
	var module_id: String = ShipState.room_module(room_id)
	var module_name: String = "none"
	if module_id != "":
		module_name = String(ShipState.module(module_id).get("name", module_id))
	_status_label.text = "Structural damage: %d%%    Shield strength: %d%%    Installed: %s" % [
		int(round(dmg)), int(round(shield)), module_name]

	var damage_blocked: bool = dmg > ShipState.BUILD_DAMAGE_THRESHOLD
	if damage_blocked:
		_blocker_label.text = ("Construction offline — structural damage exceeds %d%%. "
			+ "Dispatch a repair robot to restore this compartment first.") % int(ShipState.BUILD_DAMAGE_THRESHOLD)
	else:
		_blocker_label.text = ""

	for child in _list.get_children():
		child.queue_free()
	var catalog: Array = ShipState.modules_for_room(room_id)
	if catalog.is_empty():
		_list.add_child(make_label("No compatible modules for this compartment.", DIM_TEXT_COLOR))
	for m: Dictionary in catalog:
		var mid: String = String(m.get("id", ""))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_list.add_child(row)

		var text: VBoxContainer = VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var installed: bool = mid == module_id
		var name_color: Color = OK_COLOR if installed else TEXT_COLOR
		var name_suffix: String = "   [INSTALLED]" if installed else ""
		text.add_child(make_label(String(m.get("name", mid)) + name_suffix, name_color, 16))
		var desc: Label = make_label(String(m.get("description", "")), DIM_TEXT_COLOR, 13)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(desc)

		var build_btn: Button = Button.new()
		build_btn.text = "Build"
		build_btn.disabled = installed or damage_blocked
		build_btn.pressed.connect(_on_build_pressed.bind(mid))
		Audio.attach_ui_hover(build_btn)
		row.add_child(build_btn)

	if module_id != "":
		var clear_row: HBoxContainer = HBoxContainer.new()
		clear_row.alignment = BoxContainer.ALIGNMENT_END
		_list.add_child(clear_row)
		var clear_btn: Button = Button.new()
		clear_btn.text = "Dismantle installed module"
		clear_btn.pressed.connect(_on_clear_pressed)
		Audio.attach_ui_hover(clear_btn)
		clear_row.add_child(clear_btn)


func _on_build_pressed(module_id: String) -> void:
	var blocker: String = ShipState.build_blocker(room_id, module_id)
	if blocker != "":
		_blocker_label.text = blocker
		return
	if ShipState.build_module(room_id, module_id):
		var m_name: String = String(ShipState.module(module_id).get("name", module_id))
		GameState.add_log("Construction: %s installed in %s." % [
			m_name, String(ShipLayout.room(room_id).get("name", room_id))])
	_refresh()


func _on_clear_pressed() -> void:
	ShipState.clear_room_module(room_id)
	GameState.add_log("Construction: module dismantled in %s." % String(ShipLayout.room(room_id).get("name", room_id)))
	_refresh()
