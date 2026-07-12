extends Node

## Unified sound manager — SFX + music director.
##
## SFX (bus="SFX", available=12 players) handles UI hover, one-shot effects, and
## ambient short sounds.
##
## Music (bus="Music", stems from data/music_moods.json) handles adaptive
## background music via set_mood() + signals. All music operations are
## @no-save — derives the active mood entirely from live GameState / FtlLoop signals,
## holds no persistent gameplay state so there's nothing to serialize.
##
## Code adapted from KidsCanCode.

var num_players = 12
var bus = "SFX"

# Music director fields
var music_bus = "Music"
var current_mood: String = ""
var _moods: Dictionary = {}
var _defaults: Dictionary = {}
var _melodic: Array = []
var _room_moods: Dictionary = {}
var _quest_moods: Dictionary = {}
var _crisis_cfg: Dictionary = {}
var _tracks: Dictionary = {}          # stem_id -> AudioStreamPlayer
var _targets: Dictionary = {}         # stem_id -> float, authored target dB (pre-duck)
var _tweens: Dictionary = {}          # stem_id -> Tween (active fade)
var _duck_db: float = 0.0
var _warned: Dictionary = {}          # stem_id -> true, warn-once on missing file

const MOODS_PATH: String = "res://data/music_moods.json"
const STEM_DIR: String = "res://sounds/music/loops/"
const RISER_TO_IMPACT_SEC: float = 3.5

# --- config (loaded from data/music_moods.json) -------------------------------
signal mood_changed(mood_id: String)

func _ready():
	# Run during paused tree so the SFX queue still drains while the pause
	# menu / settings overlay / dialog screen are up. Without this, hover
	# blips fired during pause sit in `queue` until the tree unpauses, then
	# cascade-fire all at once. Children inherit ALWAYS too, so any sample
	# already mid-playback continues instead of stalling.
	PROCESS_MODE = Node.PROCESS_MODE.ALWAYS

	# SFX queue
	for i in range(num_players):
		var p = AudioStreamPlayer.new()
		add_child(p)
		available.append(p)
		p.volume_db = -10
		p.finished.connect(_on_stream_finished.bind(p))
		p.bus = bus

	# Music director init
	_load_config()
	call_deferred("_install_hooks")


# --- SFX API ----------------------------------------------------------------

var available = []  # The available players.
var queue = []  # The queue of sounds to play.

func _on_stream_finished(stream): available.append(stream)

func play(sound_path): queue.append(sound_path)

func play_ui_hover() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_ui_hover_ms < UI_HOVER_MIN_INTERVAL_MS:
		return
	_last_ui_hover_ms = now
	play(UI_HOVER_SOUND)

const UI_HOVER_SOUND: String = "res://sounds/bong_001.ogg"
const UI_HOVER_MIN_INTERVAL_MS: int = 70
var _last_ui_hover_ms: int = -10000

func attach_ui_hover(control: Control) -> void:
	if control == null:
		return
	if not control.focus_entered.is_connected(play_ui_hover):
		control.focus_entered.connect(play_ui_hover)
	if not control.mouse_entered.is_connected(play_ui_hover):
		control.mouse_entered.connect(play_ui_hover)

func _process(_delta):
	if not queue.is_empty() and not available.is_empty():
		available[0].stream = load(queue.pop_front())
		available[0].play()
		available[0].pitch_scale = randf_range(0.9, 1.1)
		available.pop_front()


# --- Music API ---------------------------------------------------------------

func _load_config() -> void:
	var f: FileAccess = FileAccess.open(MOODS_PATH, FileAccess.READ)
	if f == null:
		push_warning("Audio: cannot open %s" % MOODS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Audio: %s is not a JSON object" % MOODS_PATH)
		return
	var cfg: Dictionary = parsed
	_moods = cfg.get("moods", {})
	_defaults = cfg.get("defaults", {})
	_melodic = cfg.get("melodic_stems", [])
	_room_moods = cfg.get("rooms", {})
	_quest_moods = cfg.get("quest_steps", {})
	_crisis_cfg = cfg.get("crisis_intensity", "")


func _install_hooks() -> void:
	var gs: Node = _autoload("GameState")
	if gs != null:
		_connect(gs, "current_room_changed", _on_room_changed)
		_connect(gs, "quest_step_changed", _on_quest_step_changed)
		_connect(gs, "scrubber_level_changed", _on_scrubber_changed)
		_connect(gs, "dialog_started", _on_dialog_started)
		_connect(gs, "dialog_closed", _on_dialog_closed)
	var ftl: Node = _autoload("FtlLoop")
	if ftl != null and ftl.has_signal("phase_changed"):
		_connect(ftl, "phase_changed", _on_ftl_phase)


# Crossfade the live mix toward `mood_id`. Stems present in the mood fade in to their
# target dB; stems no longer present fade out and stop. fade_s < 0 uses the configured
# default. Unknown mood is a warned no-op.
func set_mood(mood_id: String, fade_s: float = -1.0) -> void:
	if not _moods.has(mood_id):
		push_warning("Audio: unknown mood '%s'" % mood_id)
		return
	current_mood = mood_id
	var fade: float = fade_s if fade_s >= 0.0 else float(_defaults.get("fade_s", 3.0))
	var targets: Dictionary = _scaled_targets(mood_id)
	# Stems leaving the mood: fade the track out (if one exists) and forget the target.
	for sid in _targets.keys():
		if not targets.has(sid):
			if _tracks.has(sid):
				_fade_track(sid, _silence_db(), fade, true)
			else:
				_targets.erase(sid)
	# Fade in / re-aim stems in the mood (always record the intended target, even
	# if the file is missing — tests assert the mix from _targets).
	for sid in targets.keys():
		_targets[sid] = float(targets[sid])
		_ensure_track(sid)
		if _tracks.has(sid):
			_fade_track(sid, _effective_db(sid), fade, false)
	mood_changed.emit(mood_id)


# Fire a one-shot accent (sting / riser / impact). Non-looping, fire-and-forget on the
# Music bus, ducked along with everything else. Missing file is a silent no-op.
func play_sting(stem_id: String) -> void:
	var stream = _load_stem(stem_id)
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", false)
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = music_bus
	p.volume_db = _duck_db
	p.process_mode = Node.PROCESS_MODE.ALWAYS
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


# Fire a sting after `delay` seconds (process_always so it survives a pause). Used to
# sequence the FTL riser → impact so the boom lands at the riser's peak, not on top of it.
func _play_sting_delayed(stem_id: String, delay: float) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		play_sting(stem_id)
		return
	tree.create_timer(delay, true, false, true).timeout.connect(play_sting.bind(stem_id))


# Re-derive the mood from current world state (room + quest step). Public so scenes can
# force a refresh after staging.
func refresh(fade_s: float = -1.0) -> void:
	var gs = _autoload("GameState")
	var mood = String(_defaults.get("default_room_mood", "ship_calm"))
	if gs != null:
		var room = String(gs.get("current_room_id"))
		if _room_moods.has(room):
			mood = String(_room_moods[room])
		var step = String(gs.get("quest_step"))
		if _quest_moods.has(step):
			mood = String(_quest_moods[step])
	set_mood(mood, fade_s)


func stop_all(fade_s: float = -1.0) -> void:
	var fade = fade_s if fade_s >= 0.0 else float(_defaults.get("fade_s", 3.0))
	current_mood = "silent"
	for sid in _tracks.keys():
		_fade_track(sid, _silence_db(), fade, true)


# --- signal handlers ---------------------------------------------------------

func _on_room_changed(_room_id: String) -> void:
	refresh()

func _on_quest_step_changed(_step: String) -> void:
	refresh()

func _on_dialog_started(_npc, _tree) -> void:
	_set_duck(float(_defaults.get("duck_db", -10.0)))

func _on_dialog_closed() -> void:
	_set_duck(0.0)

func _on_scrubber_changed(level: float) -> void:
	if current_mood != String(_crisis_cfg.get("mood", "")):
		return
	var scale_stems = _crisis_cfg.get("scale_stems", [])
	var min_db = float(_crisis_cfg.get("min_db", -22.0))
	var frac = clampf(1.0 - (level / 100.0), 0.0, 1.0)
	for sid in scale_stems:
		if not _tracks.has(sid):
			continue
		var authored = float((_moods[current_mood] as Dictionary).get("stems", {}).get(sid, min_db))
		_targets[sid] = lerpf(min_db, authored, frac)
		_tracks[sid].volume_db = _effective_db(sid)

func _on_ftl_phase(phase: int) -> void:
	match phase:
		0:
			pass
		1:
			refresh()
		2:
			play_sting("riser_jump")
			_play_sting_delayed("impact_jump", RISER_TO_IMPACT_SEC)
		3:
			set_mood("planet")


# --- internals ----------------------------------------------------------------

# Copy of the mood's stem->dB map, with crisis-intensity scaling pre-applied for the
# initial set_mood (live updates afterwards come through _on_scrubber_changed).
func _scaled_targets(mood_id: String) -> Dictionary:
	var stems = (_moods[mood_id] as Dictionary).get("stems", {})
	var out = {}
	for sid in stems.keys():
		out[sid] = float(stems[sid])
	if mood_id == String(_crisis_cfg.get("mood", "")):
		var gs = _autoload("GameState")
		var level = float(gs.get("scrubber_level")) if gs != null else 0.0
		var min_db = float(_crisis_cfg.get("min_db", -22.0))
		var frac = clampf(1.0 - (level / 100.0), 0.0, 1.0)
		for sid in _crisis_cfg.get("scale_stems", []):
			if out.has(sid):
				out[sid] = lerpf(min_db, float(out[sid]), frac)
	return out


func _effective_db(sid: String) -> float:
	return float(_targets.get(sid, _silence_db())) + _duck_db


func _silence_db() -> float:
	return float(_defaults.get("silence_db", -40.0))


func _set_duck(db: float) -> void:
	_duck_db = db
	for sid in _tracks.keys():
		_tracks[sid].volume_db = _effective_db(sid)


func _ensure_track(sid: String) -> void:
	if _tracks.has(sid):
		return
	var stream = _load_stem(sid)
	if stream == null:
		return
	var is_melodic = _melodic.has(sid)
	if "loop" in stream:
		stream.set("loop", not is_melodic)
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = music_bus
	p.process_mode = Node.PROCESS_MODE.ALWAYS
	p.volume_db = _silence_db()
	p.name = sid
	add_child(p)
	_tracks[sid] = p
	if is_melodic:
		p.finished.connect(_schedule_melodic_replay.bind(sid))
	p.play()


func _schedule_melodic_replay(sid: String) -> void:
	if not _tracks.has(sid):
		return
	var lo = float(_defaults.get("melodic_gap_min", 6.0))
	var hi = float(_defaults.get("melodic_gap_max", 16.0))
	var gap = randf_range(lo, hi)
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var timer = tree.create_timer(gap, true, false, true)
	timer.timeout.connect(func(): if _tracks.has(sid): _tracks[sid].play())


func _fade_track(sid: String, to_db: float, fade: float, free_after: bool) -> void:
	if not _tracks.has(sid):
		return
	var p = _tracks[sid]
	if _tweens.has(sid) and is_instance_valid(_tweens[sid]):
		_tweens[sid].kill()
		_tweens.erase(sid)
	if fade <= 0.0 or _instant():
		p.volume_db = to_db
		if free_after:
			_stop_track(sid)
		return
	var tw = create_tween()
	tw.tween_property(p, "volume_db", to_db, fade)
	_tweens[sid] = tw
	if free_after:
		tw.finished.connect(_stop_track.bind(sid))


func _stop_track(sid: String) -> void:
	if not _tracks.has(sid):
		return
	var p = _tracks[sid]
	if is_instance_valid(p):
		p.stop()
		remove_child(p)
		p.queue_free()
	_tracks.erase(sid)
	_targets.erase(sid)
	_tweens.erase(sid)


func _load_stem(sid: String) -> AudioStream:
	var path = STEM_DIR + sid + ".ogg"
	if not ResourceLoader.exists(path):
		if not _warned.has(sid):
			_warned[sid] = true
			push_warning("Audio: stem not baked yet: %s (run tools/music-bake)" % path)
		return null
	return load(path) as AudioStream


func _instant() -> bool:
	var router = _autoload("SceneRouter")
	return router != null and router.get("instant_mode") == true


func _connect(obj, sig, target) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, target):
		obj.connect(sig, target)


func _autoload(autoload_name: String) -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)