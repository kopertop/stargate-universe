extends Node

# @no-save: accessibility preferences persisted via user://settings.cfg under
# the [accessibility] section — independent of the gameplay save pipeline,
# exactly like the Settings autoload. Holds no gameplay state.
#
# Central store for ALL accessibility options in Stargate Universe:
#   • Colorblind correction mode (off/protanopia/deuteranopia/tritanopia)
#   • Subtitle options (size, color, speaker labels, background)
#   • Input remapping (keyboard + controller actions)
#   • Aim assist (strength, snap, friction)
#   • Puzzle hints (enable, delay, detail level)
#   • Auto-fail retry (enable, max retries, auto-restart)
#
# All options emit signals on change so listeners can react immediately.
# Persistence is via ConfigFile (shared path with Settings.gd) so a save wipe
# never destroys accessibility preferences.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "accessibility"

# ── Colorblind modes ──────────────────────────────────────────────────────────
enum ColorblindMode { OFF, PROTANOPIA, DEUTERANOPIA, TRITANOPIA }

# ── Subtitle sizes ─────────────────────────────────────────────────────────────
enum SubtitleSize { SMALL, MEDIUM, LARGE, EXTRA_LARGE }

# ── Subtitle colors ──────────────────────────────────────────────────────────────
enum SubtitleColor { WHITE, YELLOW, CYAN, GREEN }

# ── Hint detail levels ──────────────────────────────────────────────────────────
enum HintDetail { BRIEF, DETAILED, FULL_SOLUTION }

# ── Signals ─────────────────────────────────────────────────────────────────────
signal colorblind_mode_changed(mode: int)
signal subtitle_size_changed(size: int)
signal subtitle_color_changed(color: int)
signal speaker_labels_changed(enabled: bool)
signal subtitle_background_changed(enabled: bool)
signal aim_assist_strength_changed(value: float)
signal aim_assist_snap_changed(enabled: bool)
signal aim_assist_friction_changed(enabled: bool)
signal hints_enabled_changed(enabled: bool)
signal hint_delay_changed(seconds: float)
signal hint_detail_changed(level: int)
signal auto_retry_enabled_changed(enabled: bool)
signal auto_retry_max_changed(count: int)
signal auto_retry_restart_changed(enabled: bool)
signal input_remap_changed(action: String)

# ── Colorblind ──────────────────────────────────────────────────────────────────
var colorblind_mode: int = ColorblindMode.OFF

# ── Subtitles ─────────────────────────────────────────────────────────────────────
var subtitle_size: int = SubtitleSize.MEDIUM
var subtitle_color: int = SubtitleColor.WHITE
var speaker_labels: bool = true
var subtitle_background: bool = true

# ── Aim assist ────────────────────────────────────────────────────────────────────
var aim_assist_strength: float = 0.0    # 0.0 = off, 1.0 = max
var aim_assist_snap: bool = false       # snap-to-target on button press
var aim_assist_friction: bool = false    # slow cursor near valid targets

# ── Puzzle hints ───────────────────────────────────────────────────────────────────
var hints_enabled: bool = true
var hint_delay_seconds: float = 30.0    # seconds before hint auto-appears
var hint_detail: int = HintDetail.BRIEF

# ── Auto-fail retry ───────────────────────────────────────────────────────────────
var auto_retry_enabled: bool = false
var auto_retry_max: int = 3             # max auto-retries before giving up
var auto_retry_restart: bool = false    # restart from checkpoint vs full reset

# ── Subtitle color palette (maps SubtitleColor enum to Color) ─────────────────────
const SUBTITLE_COLORS: Dictionary = {
	SubtitleColor.WHITE: Color(1.0, 1.0, 1.0, 1.0),
	SubtitleColor.YELLOW: Color(1.0, 1.0, 0.3, 1.0),
	SubtitleColor.CYAN: Color(0.3, 0.9, 1.0, 1.0),
	SubtitleColor.GREEN: Color(0.4, 1.0, 0.4, 1.0),
}

# ── Subtitle font sizes (points) ──────────────────────────────────────────────────
const SUBTITLE_FONT_SIZES: Dictionary = {
	SubtitleSize.SMALL: 14,
	SubtitleSize.MEDIUM: 18,
	SubtitleSize.LARGE: 24,
	SubtitleSize.EXTRA_LARGE: 32,
}


# Colorblind viewport filter — a CanvasLayer + ColorRect with the colorblind
# shader material applied. Created lazily in _ready and updated on mode change.
var _colorblind_layer: CanvasLayer = null
var _colorblind_rect: ColorRect = null
const COLORBLIND_SHADER_PATH := "res://shaders/colorblind.gdshader"


func _ready() -> void:
	load_from_disk()
	_setup_colorblind_filter()


# Create the CanvasLayer + ColorRect that applies the colorblind shader to
# the whole screen. The shader samples SCREEN_TEXTURE so it post-processes
# everything rendered below the layer.
func _setup_colorblind_filter() -> void:
	if not ResourceLoader.has_cached(COLORBLIND_SHADER_PATH):
		# In headless tests the shader may not load — skip silently.
		var shader_res := load(COLORBLIND_SHADER_PATH)
		if shader_res == null:
			return
	_colorblind_layer = CanvasLayer.new()
	_colorblind_layer.layer = 200  # Above everything (fade=100, pause=90).
	_colorblind_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_colorblind_layer)

	_colorblind_rect = ColorRect.new()
	_colorblind_rect.anchor_right = 1.0
	_colorblind_rect.anchor_bottom = 1.0
	_colorblind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_colorblind_rect.visible = false  # Hidden when mode == OFF.
	_colorblind_layer.add_child(_colorblind_rect)

	# Apply the shader material.
	var shader: Shader = load(COLORBLIND_SHADER_PATH) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_colorblind_rect.material = mat
	_apply_colorblind_mode()


func _apply_colorblind_mode() -> void:
	if _colorblind_rect == null:
		return
	if colorblind_mode == ColorblindMode.OFF:
		_colorblind_rect.visible = false
		return
	_colorblind_rect.visible = true
	var mat: ShaderMaterial = _colorblind_rect.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("mode", colorblind_mode)
		mat.set_shader_parameter("intensity", 1.0)


# ── Setters ───────────────────────────────────────────────────────────────────────

func set_colorblind_mode(mode: int) -> void:
	colorblind_mode = clampi(mode, ColorblindMode.OFF, ColorblindMode.TRITANOPIA)
	_apply_colorblind_mode()
	colorblind_mode_changed.emit(colorblind_mode)
	save_to_disk()


func set_subtitle_size(size: int) -> void:
	subtitle_size = clampi(size, SubtitleSize.SMALL, SubtitleSize.EXTRA_LARGE)
	subtitle_size_changed.emit(subtitle_size)
	save_to_disk()


func set_subtitle_color(color: int) -> void:
	subtitle_color = clampi(color, SubtitleColor.WHITE, SubtitleColor.GREEN)
	subtitle_color_changed.emit(subtitle_color)
	save_to_disk()


func set_speaker_labels(enabled: bool) -> void:
	speaker_labels = enabled
	speaker_labels_changed.emit(speaker_labels)
	save_to_disk()


func set_subtitle_background(enabled: bool) -> void:
	subtitle_background = enabled
	subtitle_background_changed.emit(subtitle_background)
	save_to_disk()


func set_aim_assist_strength(value: float) -> void:
	aim_assist_strength = clampf(value, 0.0, 1.0)
	aim_assist_strength_changed.emit(aim_assist_strength)
	save_to_disk()


func set_aim_assist_snap(enabled: bool) -> void:
	aim_assist_snap = enabled
	aim_assist_snap_changed.emit(aim_assist_snap)
	save_to_disk()


func set_aim_assist_friction(enabled: bool) -> void:
	aim_assist_friction = enabled
	aim_assist_friction_changed.emit(aim_assist_friction)
	save_to_disk()


func set_hints_enabled(enabled: bool) -> void:
	hints_enabled = enabled
	hints_enabled_changed.emit(hints_enabled)
	save_to_disk()


func set_hint_delay(seconds: float) -> void:
	hint_delay_seconds = clampf(seconds, 0.0, 120.0)
	hint_delay_changed.emit(hint_delay_seconds)
	save_to_disk()


func set_hint_detail(level: int) -> void:
	hint_detail = clampi(level, HintDetail.BRIEF, HintDetail.FULL_SOLUTION)
	hint_detail_changed.emit(hint_detail)
	save_to_disk()


func set_auto_retry_enabled(enabled: bool) -> void:
	auto_retry_enabled = enabled
	auto_retry_enabled_changed.emit(auto_retry_enabled)
	save_to_disk()


func set_auto_retry_max(count: int) -> void:
	auto_retry_max = clampi(count, 1, 99)
	auto_retry_max_changed.emit(auto_retry_max)
	save_to_disk()


func set_auto_retry_restart(enabled: bool) -> void:
	auto_retry_restart = enabled
	auto_retry_restart_changed.emit(auto_retry_restart)
	save_to_disk()


# ── Helpers ───────────────────────────────────────────────────────────────────────

func subtitle_color_value() -> Color:
	return SUBTITLE_COLORS.get(subtitle_color, Color.WHITE)


func subtitle_font_size_value() -> int:
	return SUBTITLE_FONT_SIZES.get(subtitle_size, 18)


func colorblind_mode_label() -> String:
	match colorblind_mode:
		ColorblindMode.PROTANOPIA: return "Protanopia"
		ColorblindMode.DEUTERANOPIA: return "Deuteranopia"
		ColorblindMode.TRITANOPIA: return "Tritanopia"
		_: return "Off"


func subtitle_size_label() -> String:
	match subtitle_size:
		SubtitleSize.SMALL: return "Small"
		SubtitleSize.LARGE: return "Large"
		SubtitleSize.EXTRA_LARGE: return "Extra Large"
		_: return "Medium"


func subtitle_color_label() -> String:
	match subtitle_color:
		SubtitleColor.YELLOW: return "Yellow"
		SubtitleColor.CYAN: return "Cyan"
		SubtitleColor.GREEN: return "Green"
		_: return "White"


func hint_detail_label() -> String:
	match hint_detail:
		HintDetail.DETAILED: return "Detailed"
		HintDetail.FULL_SOLUTION: return "Full Solution"
		_: return "Brief"


# ── Persistence ─────────────────────────────────────────────────────────────────────

func load_from_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	colorblind_mode = clampi(
		int(cfg.get_value(SECTION, "colorblind_mode", colorblind_mode)),
		ColorblindMode.OFF, ColorblindMode.TRITANOPIA)
	subtitle_size = clampi(
		int(cfg.get_value(SECTION, "subtitle_size", subtitle_size)),
		SubtitleSize.SMALL, SubtitleSize.EXTRA_LARGE)
	subtitle_color = clampi(
		int(cfg.get_value(SECTION, "subtitle_color", subtitle_color)),
		SubtitleColor.WHITE, SubtitleColor.GREEN)
	speaker_labels = bool(cfg.get_value(SECTION, "speaker_labels", speaker_labels))
	subtitle_background = bool(cfg.get_value(SECTION, "subtitle_background", subtitle_background))
	aim_assist_strength = clampf(
		float(cfg.get_value(SECTION, "aim_assist_strength", aim_assist_strength)),
		0.0, 1.0)
	aim_assist_snap = bool(cfg.get_value(SECTION, "aim_assist_snap", aim_assist_snap))
	aim_assist_friction = bool(cfg.get_value(SECTION, "aim_assist_friction", aim_assist_friction))
	hints_enabled = bool(cfg.get_value(SECTION, "hints_enabled", hints_enabled))
	hint_delay_seconds = clampf(
		float(cfg.get_value(SECTION, "hint_delay_seconds", hint_delay_seconds)),
		0.0, 120.0)
	hint_detail = clampi(
		int(cfg.get_value(SECTION, "hint_detail", hint_detail)),
		HintDetail.BRIEF, HintDetail.FULL_SOLUTION)
	auto_retry_enabled = bool(cfg.get_value(SECTION, "auto_retry_enabled", auto_retry_enabled))
	auto_retry_max = clampi(
		int(cfg.get_value(SECTION, "auto_retry_max", auto_retry_max)),
		1, 99)
	auto_retry_restart = bool(cfg.get_value(SECTION, "auto_retry_restart", auto_retry_restart))
	# Apply the loaded colorblind mode to the viewport filter.
	_apply_colorblind_mode()


func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	# Load first so we don't clobber other sections (Settings, Gamepad, etc.).
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, "colorblind_mode", colorblind_mode)
	cfg.set_value(SECTION, "subtitle_size", subtitle_size)
	cfg.set_value(SECTION, "subtitle_color", subtitle_color)
	cfg.set_value(SECTION, "speaker_labels", speaker_labels)
	cfg.set_value(SECTION, "subtitle_background", subtitle_background)
	cfg.set_value(SECTION, "aim_assist_strength", aim_assist_strength)
	cfg.set_value(SECTION, "aim_assist_snap", aim_assist_snap)
	cfg.set_value(SECTION, "aim_assist_friction", aim_assist_friction)
	cfg.set_value(SECTION, "hints_enabled", hints_enabled)
	cfg.set_value(SECTION, "hint_delay_seconds", hint_delay_seconds)
	cfg.set_value(SECTION, "hint_detail", hint_detail)
	cfg.set_value(SECTION, "auto_retry_enabled", auto_retry_enabled)
	cfg.set_value(SECTION, "auto_retry_max", auto_retry_max)
	cfg.set_value(SECTION, "auto_retry_restart", auto_retry_restart)
	cfg.save(SETTINGS_PATH)