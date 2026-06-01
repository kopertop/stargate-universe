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
# dialog lets us update copy without touching the scene. New Game now prompts
# for a PROFILE NAME (a named playthrough) rather than wiping a single global
# save — each New Game mints its own profile, so a misclick can never destroy
# an existing playthrough.
var _new_game_dialog: ConfirmationDialog
var _new_game_name_edit: LineEdit
# Per-profile delete confirm in the Load browser (deleting a profile removes
# its whole checkpoint set, permanent saves included).
var _delete_confirm: ConfirmationDialog
var _delete_pending_profile_id: String = ""
# Code-owned "Load Game" button (inserted after Continue) + two-level
# load browser overlay, both built in _ready so the .tscn stays untouched.
var _btn_load: Button
var _load_overlay: Control
# Cached node refs for the code-built overlay. Looking them up by string path is
# brittle: code-built nodes added without an explicit name get an auto-name like
# "@MarginContainer@119", so a literal "Panel/MarginContainer/..." path fails,
# the populate aborts mid-call, and the overlay shows zero rows (the load-game
# empty-list bug, #80). Hold the references instead.
var _load_rows: VBoxContainer
var _load_header: Label
var _load_back_btn: Button

# Two-level browser state: pick a PROFILE, then a CHECKPOINT within it.
enum LoadLevel { PROFILE, CHECKPOINT }
var _load_level: int = LoadLevel.PROFILE
var _selected_profile_id: String = ""
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

	# New Game prompts for a PROFILE NAME (a named playthrough). Each New Game
	# creates its own profile, so starting a new game NEVER destroys a prior
	# one — the old destructive single-save wipe is gone. Per-profile delete
	# lives in the Load browser instead.
	_build_new_game_dialog()
	# Per-profile delete confirm (shared by the Load-browser delete buttons).
	_build_delete_confirm()

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

	# Code-owned "Configure Controller" button in the Settings overlay. Opens the
	# face-button mapping wizard for the active pad (the same wizard that pops on
	# hot-plug), so a player whose A/B/X/Y are swapped can remap on demand. Built
	# here rather than in the .tscn to keep the scene minimal (same approach as
	# the Load button). Inserted just above the Back button.
	_build_controller_button()

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


# ---- Load Game two-level browser (profile -> checkpoint) ----------------
#
# Level 1 lists save PROFILES (named playthroughs). Selecting one drills into
# level 2: that profile's checkpoints, sectioned into permanent (episode +
# manual) vs. the rolling autosave/quicksave ring. Back walks checkpoint ->
# profile -> title. Every node is built with a CACHED reference (not a string
# get_node path) — auto-named code-built containers broke the old flat overlay
# (the load-game empty-list bug, #80).

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
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -240
	panel.offset_bottom = 240
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
	header.name = "Header"
	header.text = "LOAD GAME"
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	vbox.add_child(header)
	_load_header = header

	# Scrollable rows so a profile with many manual/episode checkpoints doesn't
	# overflow the panel.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(520, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	_load_rows = rows

	var close: Button = Button.new()
	close.name = "BackButton"
	close.text = "Back"
	close.pressed.connect(_on_load_back_pressed)
	Audio.attach_ui_hover(close)
	vbox.add_child(close)
	_load_back_btn = close


func _on_load_pressed() -> void:
	_show_profile_level()
	_load_overlay.visible = true


# Back walks one level in (checkpoint -> profile), then out (profile -> title).
func _on_load_back_pressed() -> void:
	if _load_level == LoadLevel.CHECKPOINT:
		_show_profile_level()
		return
	_load_overlay.visible = false
	_btn_load.grab_focus()


# ---- level 1: profiles --------------------------------------------------

func _show_profile_level() -> void:
	_load_level = LoadLevel.PROFILE
	_selected_profile_id = ""
	_populate_profile_rows()


func _populate_profile_rows() -> void:
	var rows: VBoxContainer = _load_rows
	if rows == null:
		return
	_load_header.text = "LOAD GAME — PROFILES"
	_clear_rows(rows)
	var profiles: Array[Dictionary] = SaveManager.list_profiles()
	# Only show profiles that have at least one loadable checkpoint.
	var playable: Array[Dictionary] = []
	for prof in profiles:
		if not SaveManager.list_checkpoints(String(prof.get("id", ""))).is_empty():
			playable.append(prof)
	if playable.is_empty():
		_add_empty_row(rows, "(no saved profiles)")
		_focus_first_row(rows)
		return
	# Most-recently-played first.
	playable.sort_custom(func(a, b): return int(a.get("last_played", 0)) > int(b.get("last_played", 0)))
	for prof in playable:
		_add_profile_row(rows, prof)
	_focus_first_row(rows)


# A profile row is the profile-select button plus a small Delete button, so the
# player can remove a whole playthrough (its entire checkpoint set, permanent
# saves included) from the Load browser — there's no destructive New Game path
# anymore. Delete routes through a confirm.
func _add_profile_row(rows: VBoxContainer, prof: Dictionary) -> void:
	var pid: String = String(prof.get("id", ""))
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var b: Button = Button.new()
	b.text = _profile_row_label(prof)
	b.custom_minimum_size = Vector2(420, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_profile_chosen.bind(pid))
	Audio.attach_ui_hover(b)
	hbox.add_child(b)

	var del: Button = Button.new()
	del.name = "DeleteButton"
	del.text = "Delete"
	del.custom_minimum_size = Vector2(72, 48)
	del.pressed.connect(_on_profile_delete_pressed.bind(pid, String(prof.get("display_name", pid))))
	Audio.attach_ui_hover(del)
	hbox.add_child(del)

	rows.add_child(hbox)


func _on_profile_delete_pressed(profile_id: String, display_name: String) -> void:
	_delete_pending_profile_id = profile_id
	_delete_confirm.dialog_text = "Delete \"%s\"?\n\nThis permanently removes every save in this profile, including manual and episode checkpoints." % display_name
	_delete_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _delete_pending_profile_id == "":
		return
	SaveManager.delete_profile(_delete_pending_profile_id)
	_delete_pending_profile_id = ""
	# Refresh the profile list in place; if it's now empty, the empty row shows.
	_show_profile_level()
	# Continue / Load buttons may need to grey out if the last save is gone.
	_refresh_save_dependent_buttons()


func _on_profile_chosen(profile_id: String) -> void:
	_selected_profile_id = profile_id
	_show_checkpoint_level()


# "Default · Episode 1: Air · Find the CO2 scrubber · 2026-05-30 14:02"
func _profile_row_label(prof: Dictionary) -> String:
	var name: String = String(prof.get("display_name", prof.get("id", "?")))
	var pid: String = String(prof.get("id", ""))
	# Pull episode / objective from the profile's most-recent checkpoint meta.
	var episode: String = ""
	var objective: String = ""
	var checkpoints: Array[Dictionary] = SaveManager.list_checkpoints(pid)
	if not checkpoints.is_empty():
		var newest: Dictionary = checkpoints[0]  # list is newest-first
		episode = String(newest.get("episode", ""))
		objective = String(newest.get("objective", ""))
		if objective == "":
			objective = String(newest.get("room_id", ""))
	var when: String = _format_timestamp(int(prof.get("last_played", 0)))
	var ep_part: String = "Episode %s" % episode if episode != "" else "—"
	return "%s  ·  %s  ·  %s  ·  %s" % [name, ep_part, objective, when]


# ---- level 2: checkpoints for the chosen profile ------------------------

func _show_checkpoint_level() -> void:
	_load_level = LoadLevel.CHECKPOINT
	_populate_checkpoint_rows()


func _populate_checkpoint_rows() -> void:
	var rows: VBoxContainer = _load_rows
	if rows == null:
		return
	var prof: Dictionary = {}
	for p in SaveManager.list_profiles():
		if String(p.get("id", "")) == _selected_profile_id:
			prof = p
			break
	var name: String = String(prof.get("display_name", _selected_profile_id))
	_load_header.text = "LOAD GAME — %s" % name.to_upper()
	_clear_rows(rows)

	var checkpoints: Array[Dictionary] = SaveManager.list_checkpoints(_selected_profile_id)
	if checkpoints.is_empty():
		_add_empty_row(rows, "(no checkpoints)")
		_focus_first_row(rows)
		return

	# Partition: permanent (episode + manual) vs. rolling (autosave + quicksave).
	var permanent: Array[Dictionary] = []
	var rolling: Array[Dictionary] = []
	for cp in checkpoints:
		if cp.get("permanent", false) == true:
			permanent.append(cp)
		else:
			rolling.append(cp)

	# Both lists arrive newest-first from list_checkpoints.
	if not permanent.is_empty():
		_add_section_header(rows, "Checkpoints")
		for cp in permanent:
			_add_checkpoint_row(rows, cp)
	if not rolling.is_empty():
		_add_section_header(rows, "Recent")
		for cp in rolling:
			_add_checkpoint_row(rows, cp)
	_focus_first_row(rows)


func _add_checkpoint_row(rows: VBoxContainer, cp: Dictionary) -> void:
	var cid: String = String(cp.get("checkpoint_id", cp.get("slot_id", "")))
	var b: Button = Button.new()
	b.text = _checkpoint_row_label(cp)
	b.custom_minimum_size = Vector2(480, 40)
	b.pressed.connect(_on_checkpoint_chosen.bind(cid))
	Audio.attach_ui_hover(b)
	rows.add_child(b)


func _on_checkpoint_chosen(checkpoint_id: String) -> void:
	_load_overlay.visible = false
	if not SaveManager.load_and_resume_checkpoint(_selected_profile_id, checkpoint_id):
		_on_new_game_pressed()


# "Episode 1: Air — Complete · breached_section_south · 02:14 · 2026-05-30 14:02"
# Reuses the slot label shape but leads with the human kind/label instead of the
# raw checkpoint id.
func _checkpoint_row_label(cp: Dictionary) -> String:
	var label: String = String(cp.get("label", ""))
	if label == "":
		label = _kind_display(String(cp.get("kind", "")))
	var obj: String = String(cp.get("objective", ""))
	if obj == "":
		obj = String(cp.get("room_id", ""))
	var playtime: String = _format_playtime(float(cp.get("playtime_seconds", 0.0)))
	var when: String = _format_timestamp(int(cp.get("timestamp", 0)))
	return "%s  ·  %s  ·  %s  ·  %s" % [label, obj, playtime, when]


func _kind_display(kind: String) -> String:
	match kind:
		"autosave":
			return "Autosave"
		"quicksave":
			return "Quicksave"
		"manual":
			return "Manual save"
		"episode":
			return "Episode"
		_:
			return "Save"


# ---- shared row helpers -------------------------------------------------

func _clear_rows(rows: VBoxContainer) -> void:
	# remove_child BEFORE queue_free so the old rows are gone synchronously —
	# queue_free is deferred, so re-reading get_children() in the same frame
	# (a rapid re-populate, or a headless test) would otherwise still see the
	# stale rows from the previous level.
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()


func _add_empty_row(rows: VBoxContainer, text: String) -> void:
	var empty: Label = Label.new()
	empty.text = text
	rows.add_child(empty)


func _add_section_header(rows: VBoxContainer, text: String) -> void:
	var sec: Label = Label.new()
	sec.text = text.to_upper()
	sec.add_theme_font_size_override("font_size", 13)
	sec.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.85))
	rows.add_child(sec)


# Grab focus on the first selectable Button so keyboard / controller can drive
# the browser immediately (mouse focus is automatic). Profile rows wrap their
# select button in an HBox (alongside Delete), so recurse one level.
func _focus_first_row(rows: VBoxContainer) -> void:
	for child in rows.get_children():
		if child is Button:
			(child as Button).grab_focus()
			return
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button:
					(sub as Button).grab_focus()
					return
	# No rows to focus — fall back to Back so focus is never lost.
	if _load_back_btn != null:
		_load_back_btn.grab_focus()


# Re-greys Continue + Load Game after a profile delete may have removed the
# last save on disk. Mirrors the _ready() enable logic.
func _refresh_save_dependent_buttons() -> void:
	_btn_continue.disabled = not GameState.has_save()
	if _btn_load != null:
		_btn_load.disabled = _btn_continue.disabled


func _format_playtime(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]


func _format_timestamp(ts: int) -> String:
	if ts <= 0:
		return "—"
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

# Default profile name: "Destiny — 2026-05-31". A new playthrough never
# clobbers an existing one, so no destructive confirm is needed — just name it.
func _default_profile_name() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "Destiny — %04d-%02d-%02d" % [dt.year, dt.month, dt.day]


func _build_new_game_dialog() -> void:
	_new_game_dialog = ConfirmationDialog.new()
	_new_game_dialog.title = "New Game"
	_new_game_dialog.get_ok_button().text = "Start"
	_new_game_dialog.get_cancel_button().text = "Cancel"

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	var prompt: Label = Label.new()
	prompt.text = "Name this playthrough:"
	vbox.add_child(prompt)
	_new_game_name_edit = LineEdit.new()
	_new_game_name_edit.custom_minimum_size = Vector2(320, 0)
	_new_game_name_edit.text_submitted.connect(_on_new_game_name_submitted)
	vbox.add_child(_new_game_name_edit)
	_new_game_dialog.add_child(vbox)

	_new_game_dialog.confirmed.connect(_on_new_game_confirmed)
	add_child(_new_game_dialog)


func _build_delete_confirm() -> void:
	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.title = "Delete Profile"
	_delete_confirm.get_ok_button().text = "Delete"
	_delete_confirm.get_cancel_button().text = "Cancel"
	_delete_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_confirm)


func _on_new_game_pressed() -> void:
	# Prompt for a profile name. Pre-fill a dated default and select it so the
	# player can either accept it or type over it immediately.
	_new_game_name_edit.text = _default_profile_name()
	_new_game_dialog.popup_centered()
	_new_game_name_edit.grab_focus()
	_new_game_name_edit.select_all()


func _on_new_game_name_submitted(_text: String) -> void:
	# Enter in the name field confirms the dialog.
	_new_game_dialog.hide()
	_on_new_game_confirmed()


func _on_new_game_confirmed() -> void:
	var name: String = _new_game_name_edit.text.strip_edges()
	if name == "":
		name = _default_profile_name()
	_start_new_game(name)


# Starts a brand-new playthrough in its OWN named profile. start_new_game
# resets every registered system's in-memory state AND mints a fresh profile
# (with the chosen name) — no on-disk profile is wiped, so prior playthroughs
# survive untouched.
func _start_new_game(profile_name: String) -> void:
	SaveManager.start_new_game(profile_name)
	SceneRouter.change_to("res://scenes/gate_room.tscn", "FromGate")

func _build_controller_button() -> void:
	var settings_vbox: Node = _back_btn.get_parent()
	if settings_vbox == null:
		return
	var btn: Button = Button.new()
	btn.name = "ConfigureControllerButton"
	btn.text = "Configure Controller"
	btn.pressed.connect(_on_configure_controller_pressed)
	Audio.attach_ui_hover(btn)
	settings_vbox.add_child(btn)
	# Sit it directly above Back.
	settings_vbox.move_child(btn, _back_btn.get_index())


func _on_configure_controller_pressed() -> void:
	# Launch the wizard for the active pad if one is connected; otherwise use a
	# sentinel GUID so a player can pre-configure with no pad (the wizard simply
	# won't capture until a pad button is pressed, and Esc skips).
	var device: int = int(Gamepad.active_device)
	var guid: String = String(Gamepad.active_guid())
	if guid == "":
		guid = "manual-config"
	GamepadConfigDialog.open_wizard(device, guid)


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
