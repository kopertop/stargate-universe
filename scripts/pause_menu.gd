extends Node

# @no-save: UI overlay only. The menu drives SaveManager and SceneRouter
# but holds no persistent state of its own.
#
# In-game pause menu. Esc opens it from any gameplay scene; on the title
# scene Esc is a no-op (the title IS the menu). Built programmatically
# onto a CanvasLayer so it attaches to every scene without per-scene
# wiring, same pattern as KinoRemote.
#
# Layered above KinoRemote behaviorally: when the Kino map/console is open,
# Esc must close THAT, not stack a pause menu over it. PauseMenu's
# _unhandled_input runs before KinoRemote's (autoload order), so it
# explicitly bails when KinoRemote is open and lets the event fall through
# to KinoRemote's own pause handler. This keeps Tab=Kino and Esc=pause
# distinct without a global priority system.

const RESTART_CONFIRM_PROMPT: String = "Confirm? This wipes your save."

var _layer: CanvasLayer
var _root: Control
var _panel: PanelContainer
var _btn_resume: Button
var _btn_save: Button
var _btn_kino: Button
var _btn_title: Button
var _btn_restart: Button
var _status: Label

var _open: bool = false
var _initialized: bool = false
var _restart_armed: bool = false
# We restore the player's prior mouse_mode on close so mouselook resumes
# without an extra RMB tap. Recorded at open time.
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Defer UI build until after autoloads finish wiring so KinoRemote
	# (whose Esc handler runs first per autoload order) is fully ready.
	call_deferred("_init_ui")


func _init_ui() -> void:
	if _initialized:
		return
	_initialized = true

	_layer = CanvasLayer.new()
	_layer.layer = 90  # Above KinoRemote (80), below fade (100).
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_layer)

	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	# Dim backdrop swallows clicks so they don't bleed into the world below.
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
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
	_panel.offset_left = -200
	_panel.offset_right = 200
	_panel.offset_top = -220
	_panel.offset_bottom = 220
	_root.add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var header: Label = Label.new()
	header.text = "PAUSED"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	vbox.add_child(header)

	_btn_resume  = _build_button(vbox, "Resume",         _on_resume_pressed)
	_btn_save    = _build_button(vbox, "Save Now",       _on_save_pressed)
	_btn_kino    = _build_button(vbox, "Open Kino Map",  _on_kino_pressed)
	_btn_title   = _build_button(vbox, "Save and Quit",  _on_title_pressed)
	_btn_restart = _build_button(vbox, "Restart Episode", _on_restart_pressed)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0, 0.85))
	_status.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(_status)

	var footer: Label = Label.new()
	footer.text = "[Esc] Resume"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.7))
	vbox.add_child(footer)


func _build_button(parent: Node, label: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(280, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _button_stylebox(false))
	b.add_theme_stylebox_override("hover", _button_stylebox_hover())
	b.add_theme_stylebox_override("pressed", _button_stylebox(true))
	b.add_theme_stylebox_override("focus", _button_stylebox(true))
	b.pressed.connect(handler)
	Audio.attach_ui_hover(b)
	parent.add_child(b)
	return b


func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.96)
	sb.border_color = Color(0.4, 0.7, 1.0, 0.85)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	return sb


func _button_stylebox(active: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.44, 0.78, 0.9) if not active else Color(0.36, 0.72, 1.0, 0.95)
	sb.border_color = Color(0.4, 0.72, 1.0, 0.85) if not active else Color(0.65, 0.92, 1.0, 1.0)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb


func _button_stylebox_hover() -> StyleBoxFlat:
	var sb: StyleBoxFlat = _button_stylebox(false)
	sb.bg_color = Color(0.28, 0.58, 0.92, 0.95)
	sb.border_color = Color(0.55, 0.85, 1.0, 1.0)
	return sb


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	# Title scene has no scene path registered — Esc there is a no-op so we
	# don't intercept the user before they've started a game.
	if not _open and GameState.current_scene_path == "":
		return
	# Defer to KinoRemote when its map/console surface is open: Esc should
	# CLOSE the map, not stack the pause menu over it. PauseMenu's
	# _unhandled_input actually runs BEFORE KinoRemote's (autoload order puts
	# PauseMenu lower in the tree, so it gets unhandled input first), so we
	# must bail WITHOUT consuming the event and let it fall through to
	# KinoRemote's own pause handler.
	if not _open and KinoRemote.get("_open"):
		return
	get_viewport().set_input_as_handled()
	_toggle()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_menu()


func _open_menu() -> void:
	if not _initialized:
		_init_ui()
	_open = true
	_root.visible = true
	_panel.visible = true
	_restart_armed = false
	_refresh_buttons()
	_set_status("")
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_btn_resume.grab_focus()


func _close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	get_tree().paused = false
	# Restore prior mouselook capture state so the player isn't forced to
	# re-engage with a RMB hold after pausing mid-walk.
	Input.mouse_mode = _saved_mouse_mode
	# Re-sync view.gd's mouse-mode bookkeeping the same way KinoRemote does
	# on close. Same signal — both menus share the pattern.
	GameState.kino_closed.emit()


func _refresh_buttons() -> void:
	# Kino button only meaningful once the player has picked it up.
	_btn_kino.visible = Inventory.has("kino_remote")
	# Restart label flips into a two-click confirm pattern. _restart_armed
	# resets every time the menu opens (in _open_menu).
	_btn_restart.text = RESTART_CONFIRM_PROMPT if _restart_armed else "Restart Episode"


func _set_status(msg: String) -> void:
	if _status == null:
		return
	_status.text = msg


func _on_resume_pressed() -> void:
	_close()


func _on_save_pressed() -> void:
	# Write a PERMANENT manual checkpoint into the active profile. Each press
	# is its own timestamped checkpoint (manual saves are unlimited + never
	# pruned), so there's no slot to pick — just save and confirm. Falls back
	# to the legacy slot save only on an older SaveManager without save_manual.
	var cid: String = ""
	if SaveManager.has_method("save_manual"):
		cid = String(SaveManager.call("save_manual"))
	elif SaveManager.has_method("save"):
		SaveManager.save("manual_1")
		cid = "manual_1"
	if cid != "":
		_set_status("Game saved.")
		GameState.add_log("Game saved.")
	else:
		_set_status("Save unavailable — nothing to record yet.")


func _on_kino_pressed() -> void:
	if not Inventory.has("kino_remote"):
		return
	# Close the pause menu first so the Kino's "Esc closes me" handler
	# isn't shadowed by ours. Unpause happens inside _close; KinoRemote
	# pauses again from its own _open_remote.
	_close()
	# KinoRemote.open_remote() is the public entrypoint added for diegetic
	# in-world consoles; here we're using the same surface from the pause
	# menu. Fall back to call_group / _toggle if open_remote isn't present
	# (older KinoRemote revisions don't expose a public open).
	if KinoRemote.has_method("open_remote"):
		KinoRemote.call("open_remote")
	elif KinoRemote.has_method("_open_remote"):
		KinoRemote.call("_open_remote")


func _on_title_pressed() -> void:
	# Save-and-quit: write the current state before leaving so Continue
	# resumes exactly here. _can_autosave gating lives inside save(), so a
	# title-screen press (no scene) is a safe no-op.
	if SaveManager.has_method("save"):
		SaveManager.save()
	_close()
	SceneRouter.change_to("res://scenes/title.tscn", "")


func _on_restart_pressed() -> void:
	if not _restart_armed:
		# First press arms the confirm prompt; second press actually
		# wipes. Cheaper than a full modal and the label change makes the
		# stakes obvious.
		_restart_armed = true
		_refresh_buttons()
		_set_status("Restart wipes your save file.")
		return
	_restart_armed = false
	SaveManager.wipe()
	SaveManager.start_new_game()
	_close()
	SceneRouter.change_to("res://scenes/gate_room.tscn", "FromGate")
