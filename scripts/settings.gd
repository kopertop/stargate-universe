extends Node

# @no-save: user preferences (music/sfx volume, difficulty, loop tuning) are
# persisted via a separate ConfigFile at user://settings.cfg — independent of
# the gameplay save pipeline so settings survive a save wipe.
#
# Persistent player settings. Loaded on boot from user://settings.cfg and applied
# to the Music / SFX audio buses. Title-screen Settings overlay reads/writes via
# this singleton; gameplay code reads `difficulty` directly.
#
# Loop-timing section (issue #133 — Bridge Core-Loop config):
#   ship_phase_seconds    — base ship-phase duration fed into GameState.ship_phase_override.
#   planet_phase_seconds  — base planet-window duration fed into GameState.planet_window_override.
#   randomization_band    — ±fraction applied by FtlLoop around the base.
#   jump_destination_pref — enum stub (0 = any); reserved for future use.
# These are the SINGLE source of truth for loop tuning. #130 (FtlLoop) reads
# GameState.ship_phase_base_seconds() / planet_window_base_seconds(), which in
# turn read GameState.ship_phase_override / planet_window_override. Settings
# writes those overrides whenever the player tunes values via the Bridge console,
# so the edit path is: Bridge → Settings.set_* → GameState.*_override → #130.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "audio"
const GAMEPLAY_SECTION: String = "gameplay"
const LOOP_SECTION: String = "loop"
const UI_SECTION: String = "ui"

# HUD interface size (#141): scales the whole HUD uniformly. 1.0 = authored size.
const HUD_SCALE_MIN: float = 0.7
const HUD_SCALE_MAX: float = 1.6

# Clamp bounds for loop-tuning fields — enforced in set_* and load_from_disk.
const LOOP_PHASE_MIN: float = 60.0
const LOOP_PHASE_MAX: float = 7200.0
const LOOP_BAND_MIN: float = 0.0
const LOOP_BAND_MAX: float = 0.5

enum Difficulty { EASY, NORMAL, HARD }
enum JumpDestinationPref { ANY = 0 }   # stub — future: NEAREST, RICHEST, etc.

signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal voice_volume_changed(value: float)
signal difficulty_changed(value: int)
signal ship_phase_seconds_changed(value: float)
signal planet_phase_seconds_changed(value: float)
signal randomization_band_changed(value: float)
signal jump_destination_pref_changed(value: int)
signal hud_scale_changed(value: float)
signal compass_filter_changed()

var music_volume: float = 0.8     # 0.0 .. 1.0
var sfx_volume: float = 0.9       # 0.0 .. 1.0
var voice_volume: float = 1.0    # 0.0 .. 1.0 — TTS dialogue voice bus
var difficulty: int = Difficulty.NORMAL
var hud_scale: float = 1.0        # HUD interface size, HUD_SCALE_MIN .. MAX

# Compass marker filters — configured on the Kino Remote COMPASS settings page,
# read live by planet_compass.gd each _draw, persisted via settings.cfg.
var compass_show_lime: bool = true
var compass_show_kinos: bool = true
var compass_show_companions: bool = true
var compass_show_gate: bool = true
var compass_show_pois: bool = true

# Core-loop timing defaults — Bridge console writes these via set_*.
var ship_phase_seconds: float = 1800.0    # default ~30 min ship phase
var planet_phase_seconds: float = 1200.0  # default ~20 min planet window
var randomization_band: float = 0.20      # ±20 % jitter around base
var jump_destination_pref: int = JumpDestinationPref.ANY


func _ready() -> void:
	load_from_disk()
	_apply_music_volume()
	_apply_sfx_volume()
	_apply_voice_volume()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_music_volume()
	music_volume_changed.emit(music_volume)
	save_to_disk()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_sfx_volume()
	sfx_volume_changed.emit(sfx_volume)
	save_to_disk()


func set_voice_volume(value: float) -> void:
	voice_volume = clampf(value, 0.0, 1.0)
	_apply_voice_volume()
	voice_volume_changed.emit(voice_volume)
	save_to_disk()


func set_difficulty(value: int) -> void:
	difficulty = clampi(value, Difficulty.EASY, Difficulty.HARD)
	difficulty_changed.emit(difficulty)
	save_to_disk()


func set_hud_scale(value: float) -> void:
	hud_scale = clampf(value, HUD_SCALE_MIN, HUD_SCALE_MAX)
	hud_scale_changed.emit(hud_scale)
	save_to_disk()

func set_compass_filter(flag: String, value: bool) -> void:
	match flag:
		"compass_show_lime", "compass_show_kinos", "compass_show_companions", \
		"compass_show_gate", "compass_show_pois":
			set(flag, value)
			compass_filter_changed.emit()
			save_to_disk()


# ── Core-loop tuning setters (Bridge console) ─────────────────────────────────
# Each setter: clamp → assign → push to GameState override → emit → persist.
# GameState.*_base_seconds() reads the override, so #130 (FtlLoop) automatically
# honors any edit through a single accessor path with no duplication.

func set_ship_phase_seconds(value: float) -> void:
	ship_phase_seconds = clampf(value, LOOP_PHASE_MIN, LOOP_PHASE_MAX)
	_push_loop_to_game_state()
	ship_phase_seconds_changed.emit(ship_phase_seconds)
	save_to_disk()


func set_planet_phase_seconds(value: float) -> void:
	planet_phase_seconds = clampf(value, LOOP_PHASE_MIN, LOOP_PHASE_MAX)
	_push_loop_to_game_state()
	planet_phase_seconds_changed.emit(planet_phase_seconds)
	save_to_disk()


func set_randomization_band(value: float) -> void:
	randomization_band = clampf(value, LOOP_BAND_MIN, LOOP_BAND_MAX)
	randomization_band_changed.emit(randomization_band)
	save_to_disk()


func set_jump_destination_pref(value: int) -> void:
	jump_destination_pref = value
	jump_destination_pref_changed.emit(jump_destination_pref)
	save_to_disk()


# Push the current loop-timing values into GameState overrides so #130 reads
# them through GameState.ship_phase_base_seconds() / planet_window_base_seconds().
# GameState may not exist in bare -s script tests — guard gracefully.
func _push_loop_to_game_state() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.set("ship_phase_override", ship_phase_seconds)
	gs.set("planet_window_override", planet_phase_seconds)


# ── Audio helpers ─────────────────────────────────────────────────────────────

func difficulty_label() -> String:
	match difficulty:
		Difficulty.EASY: return "Easy"
		Difficulty.HARD: return "Hard"
		_: return "Normal"


func _apply_music_volume() -> void:
	_apply_bus_volume("Music", music_volume)


func _apply_sfx_volume() -> void:
	_apply_bus_volume("SFX", sfx_volume)


func _apply_voice_volume() -> void:
	_apply_bus_volume("Voice", voice_volume)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# AudioServer takes dB. linear→dB: 0.0 maps to -80 (effectively silent).
	# Cap silence at -80 dB to avoid log(0).
	var db: float = -80.0 if linear <= 0.0001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)


# ── Persistence ───────────────────────────────────────────────────────────────

func load_from_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	music_volume = clampf(float(cfg.get_value(SECTION, "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(SECTION, "sfx_volume", sfx_volume)), 0.0, 1.0)
	voice_volume = clampf(float(cfg.get_value(SECTION, "voice_volume", voice_volume)), 0.0, 1.0)
	difficulty = clampi(int(cfg.get_value(GAMEPLAY_SECTION, "difficulty", difficulty)),
		Difficulty.EASY, Difficulty.HARD)
	hud_scale = clampf(float(cfg.get_value(UI_SECTION, "hud_scale", hud_scale)),
		HUD_SCALE_MIN, HUD_SCALE_MAX)
	ship_phase_seconds = clampf(
		float(cfg.get_value(LOOP_SECTION, "ship_phase_seconds", ship_phase_seconds)),
		LOOP_PHASE_MIN, LOOP_PHASE_MAX)
	planet_phase_seconds = clampf(
		float(cfg.get_value(LOOP_SECTION, "planet_phase_seconds", planet_phase_seconds)),
		LOOP_PHASE_MIN, LOOP_PHASE_MAX)
	randomization_band = clampf(
		float(cfg.get_value(LOOP_SECTION, "randomization_band", randomization_band)),
		LOOP_BAND_MIN, LOOP_BAND_MAX)
	jump_destination_pref = int(cfg.get_value(LOOP_SECTION, "jump_destination_pref",
		jump_destination_pref))
	# Compass marker filters.
	compass_show_lime = cfg.get_value(UI_SECTION, "compass_show_lime", compass_show_lime) == true
	compass_show_kinos = cfg.get_value(UI_SECTION, "compass_show_kinos", compass_show_kinos) == true
	compass_show_companions = cfg.get_value(UI_SECTION, "compass_show_companions", compass_show_companions) == true
	compass_show_gate = cfg.get_value(UI_SECTION, "compass_show_gate", compass_show_gate) == true
	compass_show_pois = cfg.get_value(UI_SECTION, "compass_show_pois", compass_show_pois) == true
	# Push loaded loop values into GameState overrides so #130 reads them immediately.
	_push_loop_to_game_state()


func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION, "voice_volume", voice_volume)
	cfg.set_value(GAMEPLAY_SECTION, "difficulty", difficulty)
	cfg.set_value(UI_SECTION, "hud_scale", hud_scale)
	cfg.set_value(LOOP_SECTION, "ship_phase_seconds", ship_phase_seconds)
	cfg.set_value(LOOP_SECTION, "planet_phase_seconds", planet_phase_seconds)
	cfg.set_value(LOOP_SECTION, "randomization_band", randomization_band)
	cfg.set_value(LOOP_SECTION, "jump_destination_pref", jump_destination_pref)
	cfg.set_value(UI_SECTION, "compass_show_lime", compass_show_lime)
	cfg.set_value(UI_SECTION, "compass_show_kinos", compass_show_kinos)
	cfg.set_value(UI_SECTION, "compass_show_companions", compass_show_companions)
	cfg.set_value(UI_SECTION, "compass_show_gate", compass_show_gate)
	cfg.set_value(UI_SECTION, "compass_show_pois", compass_show_pois)
	cfg.save(SETTINGS_PATH)
