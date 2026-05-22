extends Node

# Persistent player settings. Loaded on boot from user://settings.cfg and applied
# to the Music / SFX audio buses. Title-screen Settings overlay reads/writes via
# this singleton; gameplay code reads `difficulty` directly.

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION: String = "audio"
const GAMEPLAY_SECTION: String = "gameplay"

enum Difficulty { EASY, NORMAL, HARD }

signal music_volume_changed(value: float)
signal sfx_volume_changed(value: float)
signal difficulty_changed(value: int)

var music_volume: float = 0.8     # 0.0 .. 1.0
var sfx_volume: float = 0.9       # 0.0 .. 1.0
var difficulty: int = Difficulty.NORMAL

func _ready() -> void:
	load_from_disk()
	_apply_music_volume()
	_apply_sfx_volume()

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

func set_difficulty(value: int) -> void:
	difficulty = clampi(value, Difficulty.EASY, Difficulty.HARD)
	difficulty_changed.emit(difficulty)
	save_to_disk()

func difficulty_label() -> String:
	match difficulty:
		Difficulty.EASY: return "Easy"
		Difficulty.HARD: return "Hard"
		_: return "Normal"

func _apply_music_volume() -> void:
	_apply_bus_volume("Music", music_volume)

func _apply_sfx_volume() -> void:
	_apply_bus_volume("SFX", sfx_volume)

func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# AudioServer takes dB. linear→dB: 0.0 maps to -80 (effectively silent).
	# Cap silence at -80 dB to avoid log(0).
	var db: float = -80.0 if linear <= 0.0001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)

func load_from_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SETTINGS_PATH)
	if err != OK:
		return
	music_volume = clampf(float(cfg.get_value(SECTION, "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(SECTION, "sfx_volume", sfx_volume)), 0.0, 1.0)
	difficulty = clampi(int(cfg.get_value(GAMEPLAY_SECTION, "difficulty", difficulty)),
		Difficulty.EASY, Difficulty.HARD)

func save_to_disk() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(GAMEPLAY_SECTION, "difficulty", difficulty)
	cfg.save(SETTINGS_PATH)
