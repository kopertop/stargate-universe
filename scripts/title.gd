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
@onready var _music_slider: HSlider = $SettingsOverlay/Panel/V/MusicRow/MusicHBox/MusicSlider
@onready var _music_value: Label = $SettingsOverlay/Panel/V/MusicRow/MusicHBox/MusicValue
@onready var _sfx_slider: HSlider = $SettingsOverlay/Panel/V/SfxRow/SfxHBox/SfxSlider
@onready var _sfx_value: Label = $SettingsOverlay/Panel/V/SfxRow/SfxHBox/SfxValue
@onready var _difficulty_option: OptionButton = $SettingsOverlay/Panel/V/DifficultyRow/DifficultyOption
@onready var _back_btn: Button = $SettingsOverlay/Panel/V/BackButton

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_new_game.pressed.connect(_on_new_game_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_exit.pressed.connect(_on_exit_pressed)
	_back_btn.pressed.connect(_on_back_pressed)

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
	_btn_continue.disabled = not GameState.has_save()
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
	if not GameState.load_and_resume():
		# Defensive fallback: if the save vanished between the disabled check
		# and click (unlikely but cheap), fall through to a fresh start.
		_on_new_game_pressed()

func _on_new_game_pressed() -> void:
	GameState.reset()
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
