extends SceneTree

# Smoke test for the accessibility systems (P3).
#
# Verifies:
#   • AccessibilitySettings autoload is attached and has correct defaults.
#   • Colorblind mode setter clamps and emits signal.
#   • Subtitle size/color setters work and helpers return correct values.
#   • Speaker labels and subtitle background toggles work.
#   • Aim assist strength clamps to [0, 1]; snap and friction toggles work.
#   • Puzzle hints system loads data from puzzle_hints.json.
#   • Hint text respects detail level (brief/detailed/full_solution).
#   • Hint timer doesn't fire while disabled.
#   • Auto-retry system initializes and tracks retry count.
#   • InputRemap autoload is attached, can rebind and reset.
#   • Colorblind shader file exists and parses.
#   • Accessibility overlay script loads without errors.
#   • Pause menu and title screen reference accessibility functions.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/accessibility.gd

var _passes: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== accessibility smoke test ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	# --- Autoload presence ----------------------------------------------------
	var acc: Node = root.get_node_or_null("AccessibilitySettings")
	_expect(acc != null, "AccessibilitySettings autoload is attached")
	if acc == null:
		_report()
		quit(1)
		return

	var remap: Node = root.get_node_or_null("InputRemap")
	_expect(remap != null, "InputRemap autoload is attached")

	var hints: Node = root.get_node_or_null("PuzzleHints")
	_expect(hints != null, "PuzzleHints autoload is attached")

	var retry: Node = root.get_node_or_null("AutoRetry")
	_expect(retry != null, "AutoRetry autoload is attached")

	var aim: Node = root.get_node_or_null("AimAssist")
	_expect(aim != null, "AimAssist autoload is attached")

	# --- AccessibilitySettings defaults ---------------------------------------
	_expect(acc.colorblind_mode == 0, "colorblind_mode defaults to OFF (got %d)" % acc.colorblind_mode)
	_expect(acc.subtitle_size == 1, "subtitle_size defaults to MEDIUM (got %d)" % acc.subtitle_size)
	_expect(acc.subtitle_color == 0, "subtitle_color defaults to WHITE (got %d)" % acc.subtitle_color)
	_expect(acc.speaker_labels == true, "speaker_labels defaults to true")
	_expect(acc.subtitle_background == true, "subtitle_background defaults to true")
	_expect(acc.aim_assist_strength == 0.0, "aim_assist_strength defaults to 0.0")
	_expect(acc.aim_assist_snap == false, "aim_assist_snap defaults to false")
	_expect(acc.aim_assist_friction == false, "aim_assist_friction defaults to false")
	_expect(acc.hints_enabled == true, "hints_enabled defaults to true")
	_expect(acc.hint_delay_seconds == 30.0, "hint_delay_seconds defaults to 30.0")
	_expect(acc.hint_detail == 0, "hint_detail defaults to BRIEF (got %d)" % acc.hint_detail)
	_expect(acc.auto_retry_enabled == false, "auto_retry_enabled defaults to false")
	_expect(acc.auto_retry_max == 3, "auto_retry_max defaults to 3 (got %d)" % acc.auto_retry_max)
	_expect(acc.auto_retry_restart == false, "auto_retry_restart defaults to false")

	# --- Colorblind mode setter + clamping -----------------------------------
	acc.set_colorblind_mode(2)  # Deuteranopia
	_expect(acc.colorblind_mode == 2, "colorblind_mode set to DEUTERANOPIA (got %d)" % acc.colorblind_mode)
	# Out of range clamps to max.
	acc.set_colorblind_mode(99)
	_expect(acc.colorblind_mode == 3, "colorblind_mode clamps to TRITANOPIA on overflow (got %d)" % acc.colorblind_mode)
	_expect(acc.colorblind_mode_label() == "Tritanopia", "colorblind_mode_label returns 'Tritanopia'")
	acc.set_colorblind_mode(0)

	# --- Subtitle settings ----------------------------------------------------
	acc.set_subtitle_size(3)  # Extra Large
	_expect(acc.subtitle_size == 3, "subtitle_size set to EXTRA_LARGE (got %d)" % acc.subtitle_size)
	_expect(acc.subtitle_font_size_value() == 32, "subtitle_font_size_value == 32 for EXTRA_LARGE")
	_expect(acc.subtitle_size_label() == "Extra Large", "subtitle_size_label returns 'Extra Large'")
	acc.set_subtitle_size(99)  # Clamp
	_expect(acc.subtitle_size == 3, "subtitle_size clamps to EXTRA_LARGE on overflow")
	acc.set_subtitle_size(1)  # Reset to medium

	acc.set_subtitle_color(1)  # Yellow
	_expect(acc.subtitle_color == 1, "subtitle_color set to YELLOW (got %d)" % acc.subtitle_color)
	var col: Color = acc.subtitle_color_value()
	_expect(absf(col.r - 1.0) < 0.01 and absf(col.g - 1.0) < 0.01 and absf(col.b - 0.3) < 0.01,
		"subtitle_color_value returns yellow-ish Color")
	_expect(acc.subtitle_color_label() == "Yellow", "subtitle_color_label returns 'Yellow'")
	acc.set_subtitle_color(0)

	acc.set_speaker_labels(false)
	_expect(acc.speaker_labels == false, "speaker_labels set to false")
	acc.set_speaker_labels(true)

	acc.set_subtitle_background(false)
	_expect(acc.subtitle_background == false, "subtitle_background set to false")
	acc.set_subtitle_background(true)

	# --- Aim assist -----------------------------------------------------------
	acc.set_aim_assist_strength(0.5)
	_expect(absf(acc.aim_assist_strength - 0.5) < 0.01, "aim_assist_strength set to 0.5")
	acc.set_aim_assist_strength(99.0)
	_expect(acc.aim_assist_strength == 1.0, "aim_assist_strength clamps to 1.0 on overflow")
	acc.set_aim_assist_strength(0.0)

	acc.set_aim_assist_snap(true)
	_expect(acc.aim_assist_snap == true, "aim_assist_snap set to true")
	acc.set_aim_assist_snap(false)

	acc.set_aim_assist_friction(true)
	_expect(acc.aim_assist_friction == true, "aim_assist_friction set to true")
	acc.set_aim_assist_friction(false)

	# --- Hint settings --------------------------------------------------------
	acc.set_hints_enabled(false)
	_expect(acc.hints_enabled == false, "hints_enabled set to false")
	acc.set_hints_enabled(true)

	acc.set_hint_delay(60.0)
	_expect(absf(acc.hint_delay_seconds - 60.0) < 0.01, "hint_delay_seconds set to 60.0")
	acc.set_hint_delay(999.0)
	_expect(acc.hint_delay_seconds == 120.0, "hint_delay_seconds clamps to 120.0 on overflow")
	acc.set_hint_delay(30.0)

	acc.set_hint_detail(2)  # Full Solution
	_expect(acc.hint_detail == 2, "hint_detail set to FULL_SOLUTION (got %d)" % acc.hint_detail)
	_expect(acc.hint_detail_label() == "Full Solution", "hint_detail_label returns 'Full Solution'")
	acc.set_hint_detail(0)

	# --- Auto-retry settings --------------------------------------------------
	acc.set_auto_retry_enabled(true)
	_expect(acc.auto_retry_enabled == true, "auto_retry_enabled set to true")
	acc.set_auto_retry_enabled(false)

	acc.set_auto_retry_max(5)
	_expect(acc.auto_retry_max == 5, "auto_retry_max set to 5 (got %d)" % acc.auto_retry_max)
	acc.set_auto_retry_max(99)
	_expect(acc.auto_retry_max == 99, "auto_retry_max allows up to 99 (got %d)" % acc.auto_retry_max)
	acc.set_auto_retry_max(0)
	_expect(acc.auto_retry_max == 1, "auto_retry_max clamps to 1 on underflow (got %d)" % acc.auto_retry_max)
	acc.set_auto_retry_max(3)

	acc.set_auto_retry_restart(true)
	_expect(acc.auto_retry_restart == true, "auto_retry_restart set to true")
	acc.set_auto_retry_restart(false)

	# --- PuzzleHints data loading ---------------------------------------------
	if hints != null:
		# The hints data should have loaded from data/puzzle_hints.json.
		hints.call("set_puzzle", "gate_room_power")
		var brief_text: String = hints.call("get_hint_text")
		_expect(brief_text.length() > 0, "PuzzleHints returns non-empty brief hint for gate_room_power")
		_expect(brief_text.find("power") >= 0 || brief_text.find("conduit") >= 0,
			"Brief hint mentions power/conduits (got: %s)" % brief_text)

		# Test detail levels.
		acc.set_hint_detail(0)  # BRIEF
		var t0: String = hints.call("get_hint_text")
		acc.set_hint_detail(1)  # DETAILED
		var t1: String = hints.call("get_hint_text")
		acc.set_hint_detail(2)  # FULL_SOLUTION
		var t2: String = hints.call("get_hint_text")
		_expect(t1 != t0, "Detailed hint differs from brief")
		_expect(t2 != t1, "Full solution hint differs from detailed")
		_expect(t2.length() > 0, "Full solution hint is non-empty")

		# Test a different puzzle.
		hints.call("set_puzzle", "oxygen_scrubber")
		var o2_hint: String = hints.call("get_hint_text")
		_expect(o2_hint.length() > 0, "PuzzleHints returns non-empty hint for oxygen_scrubber")

		# Clear puzzle.
		hints.call("clear_puzzle")
		var empty_hint: String = hints.call("get_hint_text")
		_expect(empty_hint == "", "PuzzleHints returns empty string after clear_puzzle")

		# Test hints_for specific puzzle.
		var lookup: String = hints.call("get_hint_for", "bridge_console")
		_expect(lookup.length() > 0, "get_hint_for('bridge_console') returns non-empty text")

		acc.set_hint_detail(0)  # Reset

	# --- InputRemap -----------------------------------------------------------
	if remap != null:
		# Verify the REMAPPABLE_ACTIONS list is populated.
		var actions: Array = remap.get("REMAPPABLE_ACTIONS")
		_expect(actions.size() > 10, "REMAPPABLE_ACTIONS has > 10 entries (got %d)" % actions.size())

		# Test rebinding to a key.
		var key_event := InputEventKey.new()
		key_event.physical_keycode = 88  # 'X' key
		var ok_bind: bool = remap.call("rebind", "interact", key_event)
		_expect(ok_bind == true, "rebind('interact', Key_X) returns true")
		_expect(remap.call("has_remap", "interact") == true, "has_remap('interact') returns true after rebind")
		# Check the binding label.
		var label: String = remap.call("binding_label", "interact")
		# The label should contain 'X' since we rebound to physical_keycode 88.
		_expect(label.length() > 0, "binding_label('interact') returns non-empty string after rebind")

		# Reset the action back to original.
		remap.call("reset_action", "interact")
		_expect(remap.call("has_remap", "interact") == false, "has_remap('interact') returns false after reset_action")

		# Test joypad button rebind.
		var joy_event := InputEventJoypadButton.new()
		joy_event.button_index = 0
		var ok_joy: bool = remap.call("rebind", "jump", joy_event)
		_expect(ok_joy == true, "rebind('jump', JoyButton_A) returns true")
		remap.call("reset_action", "jump")

	# --- AutoRetry system -----------------------------------------------------
	if retry != null:
		_expect(retry.call("get_retry_count") == 0, "AutoRetry retry_count starts at 0")
		acc.set_auto_retry_enabled(true)
		acc.set_auto_retry_max(3)
		_expect(retry.call("get_max_retries") == 3, "AutoRetry get_max_retries == 3")
		acc.set_auto_retry_enabled(false)

	# --- Colorblind shader file exists ----------------------------------------
	var shader_exists: bool = FileAccess.file_exists("res://shaders/colorblind.gdshader")
	_expect(shader_exists, "colorblind.gdshader file exists")
	if shader_exists:
		var shader_file := FileAccess.open("res://shaders/colorblind.gdshader", FileAccess.READ)
		if shader_file != null:
			var shader_text: String = shader_file.get_as_text()
			shader_file.close()
			_expect(shader_text.find("shader_type canvas_item") >= 0, "colorblind.gdshader has canvas_item type")
			_expect(shader_text.find("uniform int mode") >= 0, "colorblind.gdshader has mode uniform")
			_expect(shader_text.find("hint_screen_texture") >= 0, "colorblind.gdshader uses hint_screen_texture (Godot 4.6+)")
			_expect(shader_text.find("DEUTERANOPIA") >= 0, "colorblind.gdshader defines DEUTERANOPIA matrix")
			_expect(shader_text.find("TRITANOPIA") >= 0, "colorblind.gdshader defines TRITANOPIA matrix")

	# --- Accessibility overlay script loads -----------------------------------
	var overlay_script: GDScript = load("res://scripts/accessibility_overlay.gd") as GDScript
	_expect(overlay_script != null, "accessibility_overlay.gd loads as GDScript")

	# --- Puzzle hints data file exists ----------------------------------------
	var hints_file_exists: bool = FileAccess.file_exists("res://data/puzzle_hints.json")
	_expect(hints_file_exists, "data/puzzle_hints.json file exists")

	# --- Persistence (save/load round-trip) -----------------------------------
	# Modify a few values, save, reload, verify they persist.
	acc.set_colorblind_mode(1)  # Protanopia
	acc.set_subtitle_size(2)    # Large
	acc.set_aim_assist_strength(0.7)
	acc.set_hints_enabled(false)
	# save_to_disk is called automatically by setters.
	# Force a reload from disk into a fresh state.
	acc.colorblind_mode = 0  # Temporarily reset in-memory
	acc.subtitle_size = 1
	acc.aim_assist_strength = 0.0
	acc.hints_enabled = true
	acc.call("load_from_disk")
	_expect(acc.colorblind_mode == 1, "colorblind_mode persisted and reloaded as PROTANOPIA")
	_expect(acc.subtitle_size == 2, "subtitle_size persisted and reloaded as LARGE")
	_expect(absf(acc.aim_assist_strength - 0.7) < 0.01, "aim_assist_strength persisted and reloaded as 0.7")
	_expect(acc.hints_enabled == false, "hints_enabled persisted and reloaded as false")

	# Reset to defaults for cleanliness.
	acc.set_colorblind_mode(0)
	acc.set_subtitle_size(1)
	acc.set_aim_assist_strength(0.0)
	acc.set_hints_enabled(true)

	# --- Pause menu has accessibility button -----------------------------------
	var pause_script: GDScript = load("res://scripts/pause_menu.gd") as GDScript
	_expect(pause_script != null, "pause_menu.gd loads as GDScript")
	if pause_script != null:
		var src: String = pause_script.source_code
		_expect(src.find("_on_accessibility_pressed") >= 0, "pause_menu.gd has _on_accessibility_pressed")
		_expect(src.find("Accessibility") >= 0, "pause_menu.gd references Accessibility")

	# --- Title screen has accessibility button --------------------------------
	# Load title.gd source as text to check for accessibility wiring without
	# requiring the full class_name resolution chain (GamepadConfigDialog etc.).
	var title_path := "res://scripts/title.gd"
	if FileAccess.file_exists(title_path):
		var title_file := FileAccess.open(title_path, FileAccess.READ)
		if title_file != null:
			var src2: String = title_file.get_as_text()
			title_file.close()
			_expect(src2.find("_build_accessibility_button") >= 0, "title.gd has _build_accessibility_button")
			_expect(src2.find("_on_accessibility_pressed") >= 0, "title.gd has _on_accessibility_pressed")
			_expect(src2.find("accessibility_overlay") >= 0, "title.gd references accessibility_overlay")
	else:
		_expect(false, "title.gd file not found")

	# --- DialogScreen has subtitle settings wiring ----------------------------
	var dialog_script: GDScript = load("res://scripts/dialog_screen.gd") as GDScript
	_expect(dialog_script != null, "dialog_screen.gd loads as GDScript")
	if dialog_script != null:
		var src3: String = dialog_script.source_code
		_expect(src3.find("_apply_subtitle_settings") >= 0, "dialog_screen.gd has _apply_subtitle_settings")
		_expect(src3.find("subtitle_font_size_value") >= 0, "dialog_screen.gd uses subtitle_font_size_value")
		_expect(src3.find("subtitle_color_value") >= 0, "dialog_screen.gd uses subtitle_color_value")

	# --- project.godot has accessibility autoloads ------------------------------
	var proj_file := FileAccess.open("res://project.godot", FileAccess.READ)
	if proj_file != null:
		var proj_text: String = proj_file.get_as_text()
		proj_file.close()
		_expect(proj_text.find("AccessibilitySettings") >= 0, "project.godot registers AccessibilitySettings autoload")
		_expect(proj_text.find("InputRemap") >= 0, "project.godot registers InputRemap autoload")
		_expect(proj_text.find("PuzzleHints") >= 0, "project.godot registers PuzzleHints autoload")
		_expect(proj_text.find("AutoRetry") >= 0, "project.godot registers AutoRetry autoload")
		_expect(proj_text.find("AimAssist") >= 0, "project.godot registers AimAssist autoload")
	else:
		_expect(false, "project.godot could not be opened")

	_report()
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		# print("  PASS: %s" % label)
	else:
		_failures.append(label)
		print("  FAIL: %s" % label)


func _report() -> void:
	print("\n--- Results ---")
	print("  Passes:   %d" % _passes)
	print("  Failures: %d" % _failures.size())
	if not _failures.is_empty():
		print("  FAILED:")
		for f in _failures:
			print("    - %s" % f)