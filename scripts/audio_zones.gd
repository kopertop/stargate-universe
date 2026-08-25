extends Node

## Environmental audio system — positional ambient zones, ship-wide announcements,
## door/elevator/console sounds, planet ambient beds, combat SFX, and dynamic mix.
##
## Complements the existing Audio autoload (music director + SFX queue) with
## environmental audio that reacts to the player's location and game state.
##
## Architecture:
##   • Ambient beds (ship room type + planet biome) crossfade on the Ambient bus.
##   • One-shot SFX (doors, elevators, consoles, combat) route through the SFX bus
##     via the existing Audio.play() queue or pooled AudioStreamPlayer nodes.
##   • Ship-wide announcements and the klaxon alarm loop play on the Announce bus.
##   • Dialog ducking mirrors the music director: ambient beds duck during dialog.
##   • Alert state drives the klaxon: started when ShipAlert.is_alert_active() turns
##     true, stopped when it clears.
##
## All streams are optional — missing files degrade to silence (warned once).
## No persistent gameplay state; nothing to serialize (@no-save).
##
## Config: data/audio_zones.json

const CONFIG_PATH: String = "res://data/audio_zones.json"

signal zone_changed(zone_id: String)
signal announcement_played(text: String)

# --- Config (loaded from JSON) ----------------------------------------------
var _ship_ambient: Dictionary = {}
var _planet_ambient: Dictionary = {}
var _doors_cfg: Dictionary = {}
var _elevator_cfg: Dictionary = {}
var _console_cfg: Dictionary = {}
var _announce_cfg: Dictionary = {}
var _combat_cfg: Dictionary = {}
var _defaults: Dictionary = {}

# --- Runtime state -----------------------------------------------------------
var _ambient_bus: String = "Ambient"
var _announce_bus: String = "Announce"
var _sfx_bus: String = "SFX"

var _current_zone: String = ""
var _ambient_player: AudioStreamPlayer = null
var _ambient_target_db: float = -40.0
var _ambient_tween: Tween = null
var _wildlife_player: AudioStreamPlayer = null
var _wildlife_timer: SceneTreeTimer = null
var _wildlife_gap_min: float = 8.0
var _wildlife_gap_max: float = 22.0
var _wildlife_stream: AudioStream = null
var _wildlife_db: float = -18.0

var _klaxon_player: AudioStreamPlayer = null
var _klaxon_active: bool = false

var _duck_db: float = 0.0
var _warned: Dictionary = {}

# --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	call_deferred("_install_hooks")

	# Create the ambient bed player (looping, on the Ambient bus).
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientBed"
	_ambient_player.bus = _ambient_bus
	_ambient_player.volume_db = _silence_db()
	_ambient_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambient_player)

	# Create the wildlife player (one-shot melodic layer on Ambient bus).
	_wildlife_player = AudioStreamPlayer.new()
	_wildlife_player.name = "WildlifeLayer"
	_wildlife_player.bus = _ambient_bus
	_wildlife_player.volume_db = _silence_db()
	_wildlife_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_wildlife_player)
	_wildlife_player.finished.connect(_on_wildlife_finished)

	# Create the klaxon loop player (Announce bus).
	_klaxon_player = AudioStreamPlayer.new()
	_klaxon_player.name = "KlaxonLoop"
	_klaxon_player.bus = _announce_bus
	_klaxon_player.volume_db = float(_announce_cfg.get("klaxon_volume_db", -8.0))
	_klaxon_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_klaxon_player)

# --- Config loading ----------------------------------------------------------

func _load_config() -> void:
	var f: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if f == null:
		push_warning("AudioZones: cannot open %s" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("AudioZones: %s is not a JSON object" % CONFIG_PATH)
		return
	var cfg: Dictionary = parsed
	_ship_ambient = cfg.get("ship_room_ambient", {})
	_planet_ambient = cfg.get("planet_ambient", {})
	_doors_cfg = cfg.get("doors", {})
	_elevator_cfg = cfg.get("elevator", {})
	_console_cfg = cfg.get("console", {})
	_announce_cfg = cfg.get("announcements", {})
	_combat_cfg = cfg.get("combat", {})
	_defaults = cfg.get("defaults", {})


func _install_hooks() -> void:
	var gs: Node = _autoload("GameState")
	if gs != null:
		_connect(gs, "current_room_changed", _on_room_changed)
		_connect(gs, "dialog_started", _on_dialog_started)
		_connect(gs, "dialog_closed", _on_dialog_closed)
	# Klaxon: check alert state periodically via a timer.
	var tree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t = tree.create_timer(1.0, true, true, true)
		t.timeout.connect(_poll_alert_state)


# --- Zone management (ship rooms) --------------------------------------------

# Enter a ship-room ambient zone. `room_type` is the room's type field from
# ship_layout.json (corridor, control_room, gate_room, infirmary, etc.).
# Crossfades the ambient bed to the configured stream. Unknown types fall back
# to the default ship ambient. No-op if the same zone is already active.
func enter_ship_zone(room_type: String) -> void:
	var zone_id: String = "ship:" + room_type
	if zone_id == _current_zone:
		return
	var entry: Dictionary = _ship_ambient.get(room_type, {})
	var stream_path: String = String(entry.get("stream", ""))
	var vol_db: float = float(entry.get("volume_db", -14.0))
	if stream_path == "":
		# Fall back to default ship ambient.
		var fallback: String = String(_defaults.get("default_ship_ambient", "corridor"))
		entry = _ship_ambient.get(fallback, {})
		stream_path = String(entry.get("stream", ""))
		vol_db = float(entry.get("volume_db", -14.0))
	_stop_wildlife()
	_crossfade_ambient(stream_path, vol_db)
	_current_zone = zone_id
	zone_changed.emit(zone_id)


# --- Zone management (planet biomes) -----------------------------------------

# Enter a planet-biome ambient zone. `biome` is a biome id from biomes.json
# (desert, temperate, jungle, toxic, urban, alien_tech). Starts the wind bed
# and schedules the wildlife layer if configured.
func enter_planet_zone(biome: String) -> void:
	var zone_id: String = "planet:" + biome
	if zone_id == _current_zone:
		return
	var entry: Dictionary = _planet_ambient.get(biome, {})
	var wind_path: String = String(entry.get("wind", ""))
	var wind_db: float = float(entry.get("wind_db", -12.0))
	_crossfade_ambient(wind_path, wind_db)
	_current_zone = zone_id
	zone_changed.emit(zone_id)
	# Schedule the wildlife layer.
	var wildlife_path: String = String(entry.get("wildlife", ""))
	_wildlife_db = float(entry.get("wildlife_db", -18.0))
	_wildlife_gap_min = float(entry.get("wildlife_gap_min", 8.0))
	_wildlife_gap_max = float(entry.get("wildlife_gap_max", 22.0))
	_wildlife_stream = _load_stream(wildlife_path) if wildlife_path != "" else null
	_schedule_wildlife()


# --- Ambient crossfade -------------------------------------------------------

func _crossfade_ambient(stream_path: String, target_db: float) -> void:
	if _ambient_player == null or not is_instance_valid(_ambient_player):
		return
	var stream: AudioStream = _load_stream(stream_path) if stream_path != "" else null
	if stream == null:
		# Fade out current bed to silence.
		_fade_ambient_to(_silence_db(), _fade_s())
		return
	# If the stream changed, swap it instantly (start from silence, fade in).
	if _ambient_player.stream != stream:
		_ambient_player.stream = stream
		if "loop" in stream:
			stream.set("loop", true)
		_ambient_player.volume_db = _silence_db()
		_ambient_player.play()
	_ambient_target_db = target_db
	_fade_ambient_to(_effective_ambient_db(), _fade_s())


func _fade_ambient_to(to_db: float, fade: float) -> void:
	if _ambient_player == null or not is_instance_valid(_ambient_player):
		return
	if _ambient_tween != null and _ambient_tween.is_valid():
		_ambient_tween.kill()
	if fade <= 0.0 or _instant():
		_ambient_player.volume_db = to_db
		return
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(_ambient_player, "volume_db", to_db, fade)


func _effective_ambient_db() -> float:
	return _ambient_target_db + _duck_db


func _silence_db() -> float:
	return float(_defaults.get("silence_db", -40.0))


func _fade_s() -> float:
	return float(_defaults.get("fade_s", 2.0))


func _instant() -> bool:
	var router: Node = _autoload("SceneRouter")
	return router != null and router.get("instant_mode") == true


# --- Wildlife layer ----------------------------------------------------------

func _schedule_wildlife() -> void:
	# Clear any pending timer.
	_wildlife_timer = null
	if _wildlife_stream == null:
		return
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var gap: float = randf_range(_wildlife_gap_min, _wildlife_gap_max)
	_wildlife_timer = tree.create_timer(gap, true, false, true)
	_wildlife_timer.timeout.connect(_play_wildlife)


func _play_wildlife() -> void:
	if _wildlife_stream == null or not is_instance_valid(_wildlife_player):
		return
	# Only play if we're still in a planet zone.
	if not _current_zone.begins_with("planet:"):
		return
	_wildlife_player.stream = _wildlife_stream
	_wildlife_player.volume_db = _wildlife_db + _duck_db
	_wildlife_player.pitch_scale = randf_range(0.9, 1.1)
	_wildlife_player.play()


func _on_wildlife_finished() -> void:
	if _current_zone.begins_with("planet:") and _wildlife_stream != null:
		_schedule_wildlife()


func _stop_wildlife() -> void:
	_wildlife_timer = null
	_wildlife_stream = null
	if _wildlife_player != null and is_instance_valid(_wildlife_player):
		_wildlife_player.stop()


# --- Door sounds -------------------------------------------------------------

func play_door_open() -> void:
	_play_sfx(_doors_cfg.get("open", ""), float(_doors_cfg.get("volume_db", -8.0)))

func play_door_close() -> void:
	_play_sfx(_doors_cfg.get("close", ""), float(_doors_cfg.get("volume_db", -8.0)))

func play_door_locked() -> void:
	_play_sfx(_doors_cfg.get("locked", ""), float(_doors_cfg.get("volume_db", -8.0)))


# --- Elevator sounds ---------------------------------------------------------

func play_elevator_hum() -> void:
	_play_sfx(_elevator_cfg.get("hum", ""), float(_elevator_cfg.get("volume_db", -10.0)))

func play_elevator_arrive() -> void:
	_play_sfx(_elevator_cfg.get("arrive", ""), float(_elevator_cfg.get("volume_db", -10.0)))

func play_elevator_beep() -> void:
	_play_sfx(_elevator_cfg.get("beep", ""), float(_elevator_cfg.get("volume_db", -10.0)))


# --- Console sounds ----------------------------------------------------------

func play_console_beep() -> void:
	_play_sfx(_console_cfg.get("beep", ""), float(_console_cfg.get("volume_db", -8.0)))

func play_console_deny() -> void:
	_play_sfx(_console_cfg.get("deny", ""), float(_console_cfg.get("volume_db", -8.0)))

func play_console_boot() -> void:
	_play_sfx(_console_cfg.get("boot", ""), float(_console_cfg.get("volume_db", -8.0)))


# --- Ship announcements ------------------------------------------------------

# Play a ship-wide announcement: chime then optional TTS voice. `text` is the
# announcement text (for TTS if available, or just logged). The chime plays on
# the Announce bus.
func play_announcement(text: String) -> void:
	var chime_path: String = String(_announce_cfg.get("chime", ""))
	var chime_db: float = float(_announce_cfg.get("chime_volume_db", -6.0))
	if chime_path != "":
		_play_on_bus(chime_path, chime_db, _announce_bus)
	announcement_played.emit(text)


# --- Klaxon (alert alarm) ----------------------------------------------------

func _poll_alert_state() -> void:
	var alert_script: Script = load("res://scripts/ship_alert.gd") as Script
	if alert_script == null:
		return
	var alert_active: bool = alert_script.is_alert_active()
	if alert_active and not _klaxon_active:
		_start_klaxon()
	elif not alert_active and _klaxon_active:
		_stop_klaxon()
	# Re-poll every 1s.
	var tree = Engine.get_main_loop() as SceneTree
	if tree != null:
		var t = tree.create_timer(1.0, true, true, true)
		t.timeout.connect(_poll_alert_state)


func _start_klaxon() -> void:
	var klaxon_path: String = String(_announce_cfg.get("klaxon", ""))
	if klaxon_path == "":
		return
	var stream: AudioStream = _load_stream(klaxon_path)
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", true)
	_klaxon_player.stream = stream
	_klaxon_player.volume_db = float(_announce_cfg.get("klaxon_volume_db", -8.0))
	_klaxon_player.play()
	_klaxon_active = true


func _stop_klaxon() -> void:
	if _klaxon_player != null and is_instance_valid(_klaxon_player):
		_klaxon_player.stop()
	_klaxon_active = false


# --- Combat audio ------------------------------------------------------------

func play_combat_fire() -> void:
	_play_sfx(_combat_cfg.get("fire", ""), float(_combat_cfg.get("volume_db", -6.0)))

func play_combat_hit() -> void:
	_play_sfx(_combat_cfg.get("hit", ""), float(_combat_cfg.get("volume_db", -6.0)))

func play_combat_reload() -> void:
	_play_sfx(_combat_cfg.get("reload", ""), float(_combat_cfg.get("volume_db", -6.0)))


# --- SFX helpers -------------------------------------------------------------

# Play a one-shot SFX on the SFX bus via the Audio autoload's queue. Falls back
# to a pooled AudioStreamPlayer if the Audio autoload is unavailable (headless).
func _play_sfx(stream_path: String, volume_db: float) -> void:
	if stream_path == "":
		return
	var audio: Node = _autoload("Audio")
	if audio != null and audio.has_method("play"):
		audio.call("play", stream_path)
	else:
		_play_on_bus(stream_path, volume_db, _sfx_bus)


# Play a one-shot on a specific bus using a fire-and-forget AudioStreamPlayer.
func _play_on_bus(stream_path: String, volume_db: float, bus_name: String) -> void:
	var stream: AudioStream = _load_stream(stream_path)
	if stream == null:
		return
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus_name
	p.volume_db = volume_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


# --- Stream loading ----------------------------------------------------------

func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		if not _warned.has(path):
			_warned[path] = true
			push_warning("AudioZones: stream not found: %s" % path)
		return null
	return load(path) as AudioStream


# --- Signal handlers ---------------------------------------------------------

func _on_room_changed(room_id: String) -> void:
	# Derive the room type from ShipLayout and enter the matching zone.
	var sl: Node = _autoload("ShipLayout")
	if sl == null:
		return
	var room_data: Dictionary = {}
	if sl.has_method("room"):
		room_data = sl.call("room", room_id)
	elif sl.has_method("get_room"):
		room_data = sl.call("get_room", room_id)
	if room_data.is_empty():
		return
	var room_type: String = String(room_data.get("type", ""))
	if room_type != "":
		enter_ship_zone(room_type)


func _on_dialog_started(_npc, _tree) -> void:
	_duck_db = float(_defaults.get("duck_db", -6.0))
	_apply_duck()


func _on_dialog_closed() -> void:
	_duck_db = 0.0
	_apply_duck()


func _apply_duck() -> void:
	if _ambient_player != null and is_instance_valid(_ambient_player):
		var target: float = _effective_ambient_db()
		if _ambient_tween != null and _ambient_tween.is_valid():
			_ambient_tween.kill()
		if _instant():
			_ambient_player.volume_db = target
		else:
			_ambient_tween = create_tween()
			_ambient_tween.tween_property(_ambient_player, "volume_db", target, 0.3)


# --- Stop / cleanup ----------------------------------------------------------

func stop_all(fade_s: float = -1.0) -> void:
	var fade: float = fade_s if fade_s >= 0.0 else _fade_s()
	_fade_ambient_to(_silence_db(), fade)
	_stop_wildlife()
	_stop_klaxon()
	_current_zone = ""


# --- Utilities ---------------------------------------------------------------

func _connect(obj: Object, sig: String, target: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, target):
		obj.connect(sig, target)


func _autoload(autoload_name: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


# --- Test helpers (called from smoke tests in headless mode) -----------------

func get_current_zone() -> String:
	return _current_zone

func is_klaxon_active() -> bool:
	return _klaxon_active

func get_ship_ambient_config() -> Dictionary:
	return _ship_ambient

func get_planet_ambient_config() -> Dictionary:
	return _planet_ambient

func get_doors_config() -> Dictionary:
	return _doors_cfg

func get_elevator_config() -> Dictionary:
	return _elevator_cfg

func get_console_config() -> Dictionary:
	return _console_cfg

func get_announce_config() -> Dictionary:
	return _announce_cfg

func get_combat_config() -> Dictionary:
	return _combat_cfg

func get_defaults() -> Dictionary:
	return _defaults