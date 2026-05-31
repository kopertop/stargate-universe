extends Control

# Boot title screen for Stargate Universe — Episode 1: "Air".
# Hero shot background with a left-aligned title block and flat menu list.
# Continue is disabled (greyed) when no save exists; Characters is reserved
# for a future crew-roster screen; Settings opens an overlay; Exit quits.

@onready var _btn_continue: Button = $LeftColumn/MenuList/ContinueButton
@onready var _btn_new_game: Button = $LeftColumn/MenuList/NewGameButton
@onready var _btn_settings: Button = $LeftColumn/MenuList/SettingsButton
@onready var _btn_characters: Button = $LeftColumn/MenuList/CharactersButton
@onready var _btn_exit: Button = $LeftColumn/MenuList/ExitButton

@onready var _settings_overlay: Control = $SettingsOverlay

# Built lazily in _ready since it isn't in the .tscn — a code-owned
# ConfirmationDialog lets us update copy without touching the scene.
var _new_game_confirm: ConfirmationDialog
# Code-owned "Load Game" button (inserted after Continue) + slot-select
# overlay, both built in _ready so the .tscn stays untouched.
var _btn_load: Button
var _load_overlay: Control
@onready var _music_slider: HSlider = $SettingsOverlay/Panel/V/MusicRow/MusicHBox/MusicSlider
@onready var _music_value: Label = $SettingsOverlay/Panel/V/MusicRow/MusicHBox/MusicValue
@onready var _sfx_slider: HSlider = $SettingsOverlay/Panel/V/SfxRow/SfxHBox/SfxSlider
@onready var _sfx_value: Label = $SettingsOverlay/Panel/V/SfxRow/SfxHBox/SfxValue
@onready var _difficulty_option: OptionButton = $SettingsOverlay/Panel/V/DifficultyRow/DifficultyOption
@onready var _back_btn: Button = $SettingsOverlay/Panel/V/BackButton

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Mark that we're no longer in a gameplay scene. The pause menu and
	# autosave both gate on current_scene_path being empty to mean "title /
	# not in-world". "Save and Quit" returns here WITHOUT going through
	# reset(), so if we don't clear it the stale gameplay path lets Esc pop
	# the pause menu over the title (and would let a stray autosave fire).
	GameState.current_scene_path = ""

	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_new_game.pressed.connect(_on_new_game_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_exit.pressed.connect(_on_exit_pressed)
	_back_btn.pressed.connect(_on_back_pressed)

	# Insert a "Load Game" button right after Continue. Cloning Continue's
	# look keeps it visually consistent without duplicating .tscn theme rows.
	_btn_load = _btn_continue.duplicate() as Button
	_btn_load.name = "LoadGameButton"
	_btn_load.text = "Load Game"
	_btn_load.disabled = false
	var menu_list: Node = _btn_continue.get_parent()
	menu_list.add_child(_btn_load)
	menu_list.move_child(_btn_load, _btn_continue.get_index() + 1)
	_btn_load.pressed.connect(_on_load_pressed)
	Audio.attach_ui_hover(_btn_load)
	_build_load_overlay()

	# Menu-hover SFX: fire a short blip when keyboard / controller / mouse
	# focus lands on any of these. Throttled inside Audio.play_ui_hover.
	for b in [_btn_continue, _btn_new_game, _btn_settings, _btn_characters,
			_btn_exit, _back_btn, _difficulty_option]:
		Audio.attach_ui_hover(b)

	# Destructive-action guard: New Game wipes the save file. Without this
	# prompt a misclick during a long playthrough silently destroys hours
	# of progress, so we gate it behind an explicit confirm whenever a
	# save exists. No-save case skips the dialog entirely (nothing to lose).
	_new_game_confirm = ConfirmationDialog.new()
	_new_game_confirm.title = "New Game"
	_new_game_confirm.dialog_text = "Delete the current game?\n\nIf you do this you will lose all previous save data."
	_new_game_confirm.get_ok_button().text = "Delete & Start Over"
	_new_game_confirm.get_cancel_button().text = "Cancel"
	_new_game_confirm.confirmed.connect(_start_new_game)
	add_child(_new_game_confirm)

	# Settings overlay UI wired to the Settings autoload.
	_populate_difficulty_options()
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_difficulty_option.select(Settings.difficulty)
	_update_music_value_label(Settings.music_volume)
	_update_sfx_value_label(Settings.sfx_volume)
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_difficulty_option.item_selected.connect(_on_difficulty_selected)

	# Continue shows as disabled/greyed when there's no save to resume.
	# Load Game mirrors it — both are meaningless with no slots on disk.
	_btn_continue.disabled = not GameState.has_save()
	if _btn_load != null:
		_btn_load.disabled = _btn_continue.disabled
	# Characters is reserved for a future crew-roster screen.
	_btn_characters.disabled = true

	if not _btn_continue.disabled:
		_btn_continue.grab_focus()
	else:
		_btn_new_game.grab_focus()

	if _has_arg("settings-open"):
		_settings_overlay.visible = true
	if _screenshot_requested():
		_capture_and_quit()

func _populate_difficulty_options() -> void:
	_difficulty_option.clear()
	_difficulty_option.add_item("Easy", Settings.Difficulty.EASY)
	_difficulty_option.add_item("Normal", Settings.Difficulty.NORMAL)
	_difficulty_option.add_item("Hard", Settings.Difficulty.HARD)

func _update_music_value_label(linear: float) -> void:
	_music_value.text = "%d%%" % int(round(linear * 100.0))

func _update_sfx_value_label(linear: float) -> void:
	_sfx_value.text = "%d%%" % int(round(linear * 100.0))

func _on_music_changed(value: float) -> void:
	Settings.set_music_volume(value)
	_update_music_value_label(value)

func _on_sfx_changed(value: float) -> void:
	Settings.set_sfx_volume(value)
	_update_sfx_value_label(value)

func _on_difficulty_selected(index: int) -> void:
	Settings.set_difficulty(index)

func _on_continue_pressed() -> void:
	# "" = resume the most-recently-written slot (autosave/quicksave/manual).
	if not SaveManager.load_and_resume(""):
		# Defensive fallback: if the save vanished between the disabled check
		# and click (unlikely but cheap), fall through to a fresh start.
		_on_new_game_pressed()


# ---- Load Game slot-select overlay --------------------------------------

func _build_load_overlay() -> void:
	_load_overlay = Control.new()
	_load_overlay.name = "LoadOverlay"
	_load_overlay.anchor_right = 1.0
	_load_overlay.anchor_bottom = 1.0
	_load_overlay.visible = false
	_load_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_load_overlay)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_load_overlay.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -200
	panel.offset_bottom = 200
	_load_overlay.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header: Label = Label.new()
	header.text = "LOAD GAME"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	vbox.add_child(header)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 6)
	vbox.add_child(rows)

	var close: Button = Button.new()
	close.name = "CloseButton"
	close.text = "Back"
	close.pressed.connect(_on_load_overlay_close)
	Audio.attach_ui_hover(close)
	vbox.add_child(close)


func _on_load_pressed() -> void:
	_populate_load_rows()
	_load_overlay.visible = true


func _on_load_overlay_close() -> void:
	_load_overlay.visible = false
	_btn_load.grab_focus()


func _populate_load_rows() -> void:
	var rows: Node = _load_overlay.get_node("Panel/MarginContainer/VBox/Rows")
	for child in rows.get_children():
		child.queue_free()
	var slots: Array[Dictionary] = SaveManager.list_slots()
	if slots.is_empty():
		var empty: Label = Label.new()
		empty.text = "(no saves)"
		rows.add_child(empty)
		return
	# Most-recent first so the freshest save reads at the top.
	slots.sort_custom(func(a, b): return int(a.get("timestamp", 0)) > int(b.get("timestamp", 0)))
	for meta in slots:
		var slot_id: String = String(meta.get("slot_id", ""))
		var b: Button = Button.new()
		b.text = _slot_row_label(meta)
		b.custom_minimum_size = Vector2(420, 40)
		b.pressed.connect(_on_slot_chosen.bind(slot_id))
		Audio.attach_ui_hover(b)
		rows.add_child(b)


# "manual_1 · Find the CO2 scrubber · 02:14 · 2026-05-30 14:02"
func _slot_row_label(meta: Dictionary) -> String:
	var slot_id: String = String(meta.get("slot_id", "?"))
	var obj: String = String(meta.get("objective", ""))
	if obj == "":
		obj = String(meta.get("room_id", ""))
	var playtime: String = _format_playtime(float(meta.get("playtime_seconds", 0.0)))
	var when: String = _format_timestamp(int(meta.get("timestamp", 0)))
	return "%s  ·  %s  ·  %s  ·  %s" % [slot_id, obj, playtime, when]


func _format_playtime(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


func _format_timestamp(ts: int) -> String:
	if ts <= 0:
		return "—"
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]


func _on_slot_chosen(slot_id: String) -> void:
	_load_overlay.visible = false
	if not SaveManager.load_and_resume(slot_id):
		_on_new_game_pressed()

func _on_new_game_pressed() -> void:
	# When a save exists, route through the confirmation dialog first.
	# Cancel leaves the menu untouched; confirm calls _start_new_game.
	if SaveManager.has_save():
		_new_game_confirm.popup_centered()
		return
	_start_new_game()


func _start_new_game() -> void:
	# Wipe the on-disk save eagerly so the user's "start over" intent
	# holds even if they quit at the title before any autosave lands.
	SaveManager.wipe()
	# Iterate every registered system and call reset() — keeps GameClock,
	# NPCState, etc. in sync without title.gd having to enumerate them.
	SaveManager.start_new_game()
	SceneRouter.change_to("res://scenes/gate_room.tscn", "FromGate")

func _on_settings_pressed() -> void:
	_settings_overlay.visible = true
	_back_btn.grab_focus()

func _on_back_pressed() -> void:
	_settings_overlay.visible = false
	if not _btn_continue.disabled:
		_btn_continue.grab_focus()
	else:
		_btn_new_game.grab_focus()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _screenshot_requested() -> bool:
	return _has_arg("screenshot")

func _has_arg(needle: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == needle:
			return true
	return false

func _capture_and_quit() -> void:
	# Wait two post-draw frames so the background texture is rendered before
	# grabbing the framebuffer; one frame can race the image load.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("user://title_capture.png")
	get_tree().quit()
