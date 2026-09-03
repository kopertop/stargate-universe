extends Node

# Composable background-music director (adaptive vertical layering).
#
# @no-save: derives the active mood entirely from live GameState / FtlLoop signals and
# holds no persistent gameplay state — the current mix is fully reconstructible from world
# state on load, so there is nothing to serialize.
#
# Stems are isolated, seamlessly-looping textures baked by tools/music-bake into
# sounds/music/loops/<id>.ogg. A MOOD (data/music_moods.json) is a set of stems each held
# at a target volume in dB; set_mood() crossfades the live mix toward it. The mood is chosen
# from the player's room + active quest step (data-driven) and reacts to the air crisis and
# the FTL loop. All players route through the Music bus, so Settings.music_volume already
# governs the master level.
#
# Robustness: missing stem files are tolerated (that track just never sounds), so a half-
# baked library never crashes the game. Honors SceneRouter.instant_mode — under headless
# tests fades snap instantly (no tweens) so assertions see final gains immediately.

const MOODS_PATH: String = "res://data/music_moods.json"
const STEM_DIR: String = "res://sounds/music/loops/"
const MUSIC_BUS: String = "Music"
# How long after the FTL riser starts the impact boom lands (≈ the riser_jump build length).
const RISER_TO_IMPACT_SEC: float = 3.5

signal mood_changed(mood_id: String)

# --- config (loaded from data/music_moods.json) -------------------------------
var _moods: Dictionary = {}
var _defaults: Dictionary = {}
var _melodic: Array = []
var _room_moods: Dictionary = {}
var _quest_moods: Dictionary = {}
var _crisis_cfg: Dictionary = {}

# --- live mix state -----------------------------------------------------------
var current_mood: String = ""
var _tracks: Dictionary = {}          # stem_id -> AudioStreamPlayer
var _targets: Dictionary = {}         # stem_id -> float, authored target dB (pre-duck)
var _tweens: Dictionary = {}          # stem_id -> Tween (active fade)
var _duck_db: float = 0.0
var _warned: Dictionary = {}          # stem_id -> true, warn-once on missing file


func _ready() -> void:
	# ALWAYS so the duck on dialog (which pauses the tree) and the melodic rest
	# scheduler keep working while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()
	# Defer hook install so every autoload is ready first (mirrors FtlLoop).
	call_deferred("_install_hooks")


func _load_config() -> void:
	var f: FileAccess = FileAccess.open(MOODS_PATH, FileAccess.READ)
	if f == null:
		push_warning("MusicDirector: cannot open %s" % MOODS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MusicDirector: %s is not a JSON object" % MOODS_PATH)
		return
	var cfg: Dictionary = parsed
	_moods = cfg.get("moods", {})
	_defaults = cfg.get("defaults", {})
	_melodic = cfg.get("melodic_stems", [])
	_room_moods = cfg.get("rooms", {})
	_quest_moods = cfg.get("quest_steps", {})
	_crisis_cfg = cfg.get("crisis_intensity", {})


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


# ── public API ────────────────────────────────────────────────────────────────

# Crossfade the live mix toward `mood_id`. Stems present in the mood fade in to their
# target dB; stems no longer present fade out and stop. fade_s < 0 uses the configured
# default. Unknown mood is a warned no-op.
func set_mood(mood_id: String, fade_s: float = -1.0) -> void:
	if not _moods.has(mood_id):
		push_warning("MusicDirector: unknown mood '%s'" % mood_id)
		return
	current_mood = mood_id
	var fade: float = fade_s if fade_s >= 0.0 else float(_defaults.get("fade_s", 3.0))
	var targets: Dictionary = _scaled_targets(mood_id)
	# Stems leaving the mood: fade the track out (if one exists) and forget the target.
	# Keyed off _targets (the intended mix) not _tracks, so unbaked stems are still
	# dropped from the mix bookkeeping. keys() returns a copy — safe to erase while iterating.
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
	var stream: AudioStream = _load_stem(stem_id)
	if stream == null:
		return
	if "loop" in stream:
		stream.set("loop", false)   # a sting fires once, never loops
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = MUSIC_BUS
	p.volume_db = _duck_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


# Fire a sting after `delay` seconds (process_always so it survives a pause). Used to
# sequence the FTL riser → impact so the boom lands at the riser's peak, not on top of it.
func _play_sting_delayed(stem_id: String, delay: float) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		play_sting(stem_id)
		return
	tree.create_timer(delay, true, false, true).timeout.connect(play_sting.bind(stem_id))


# Re-derive the mood from current world state (room + quest step). Public so scenes can
# force a refresh after staging.
func refresh(fade_s: float = -1.0) -> void:
	var gs: Node = _autoload("GameState")
	var mood: String = String(_defaults.get("default_room_mood", "ship_calm"))
	if gs != null:
		var room: String = String(gs.get("current_room_id"))
		if _room_moods.has(room):
			mood = String(_room_moods[room])
		var step: String = String(gs.get("quest_step"))
		if _quest_moods.has(step):   # quest crisis beats override the room mood
			mood = String(_quest_moods[step])
	set_mood(mood, fade_s)


func stop_all(fade_s: float = -1.0) -> void:
	var fade: float = fade_s if fade_s >= 0.0 else float(_defaults.get("fade_s", 3.0))
	current_mood = "silent"
	for sid in _tracks.keys():
		_fade_track(sid, _silence_db(), fade, true)


# ── signal handlers ────────────────────────────────────────────────────────────

func _on_room_changed(_room_id: String) -> void:
	refresh()

func _on_quest_step_changed(_step: String) -> void:
	refresh()

func _on_dialog_started(_npc: Variant, _tree: Variant) -> void:
	_set_duck(float(_defaults.get("duck_db", -10.0)))

func _on_dialog_closed() -> void:
	_set_duck(0.0)

# While the crisis mood is active, scale the danger stems by scrubber charge: full charge
# sits near min_db (barely there), empty reaches the mood's authored target — the air
# crisis musically tightens as oxygen drains. Adjusts gains directly (no tween) so the
# per-tick decay signal doesn't churn crossfades.
func _on_scrubber_changed(level: float) -> void:
	if current_mood != String(_crisis_cfg.get("mood", "")):
		return
	var scale_stems: Array = _crisis_cfg.get("scale_stems", [])
	var min_db: float = float(_crisis_cfg.get("min_db", -22.0))
	var frac: float = clampf(1.0 - (level / 100.0), 0.0, 1.0)   # level 100 -> 0, level 0 -> 1
	for sid in scale_stems:
		if not _tracks.has(sid):
			continue
		var authored: float = float((_moods[current_mood] as Dictionary).get("stems", {}).get(sid, min_db))
		_targets[sid] = lerpf(min_db, authored, frac)
		(_tracks[sid] as AudioStreamPlayer).volume_db = _effective_db(sid)

func _on_ftl_phase(phase: int) -> void:
	# FtlLoop.Phase: 0 IDLE, 1 SHIP, 2 JUMPING, 3 PLANET.
	match phase:
		1: refresh()                       # back aboard in FTL
		2:                                 # jump: riser builds, impact lands at its peak
			play_sting("riser_jump")
			_play_sting_delayed("impact_jump", RISER_TO_IMPACT_SEC)
		3: set_mood("planet")


# ── internals ───────────────────────────────────────────────────────────────────

# Copy of the mood's stem->dB map, with crisis-intensity scaling pre-applied for the
# initial set_mood (live updates afterwards come through _on_scrubber_changed).
func _scaled_targets(mood_id: String) -> Dictionary:
	var stems: Dictionary = (_moods[mood_id] as Dictionary).get("stems", {})
	var out: Dictionary = {}
	for sid in stems.keys():
		out[sid] = float(stems[sid])
	if mood_id == String(_crisis_cfg.get("mood", "")):
		var gs: Node = _autoload("GameState")
		var level: float = float(gs.get("scrubber_level")) if gs != null else 0.0
		var min_db: float = float(_crisis_cfg.get("min_db", -22.0))
		var frac: float = clampf(1.0 - (level / 100.0), 0.0, 1.0)
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
	# Instant (dialog pauses the tree, so a tween wouldn't advance).
	for sid in _tracks.keys():
		(_tracks[sid] as AudioStreamPlayer).volume_db = _effective_db(sid)


func _ensure_track(sid: String) -> void:
	if _tracks.has(sid):
		return
	var stream: AudioStream = _load_stem(sid)
	if stream == null:
		return
	var is_melodic: bool = _melodic.has(sid)
	# Loop sustained stems forever; melodic stems play one phrase then rest, so they
	# must NOT loop (the rest scheduler replays them).
	if "loop" in stream:
		stream.set("loop", not is_melodic)
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = MUSIC_BUS
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.volume_db = _silence_db()   # start silent; the fade brings it in
	p.name = sid
	add_child(p)
	_tracks[sid] = p
	if is_melodic:
		p.finished.connect(_schedule_melodic_replay.bind(sid))
	p.play()


# Replay a melodic stem after a randomized rest, but only while it remains part of the
# active mood (a mood change frees the track, cancelling this).
func _schedule_melodic_replay(sid: String) -> void:
	if not _tracks.has(sid):
		return
	var lo: float = float(_defaults.get("melodic_gap_min", 6.0))
	var hi: float = float(_defaults.get("melodic_gap_max", 16.0))
	var gap: float = randf_range(lo, hi)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var timer: SceneTreeTimer = tree.create_timer(gap, true, false, true)  # process_always
	timer.timeout.connect(func() -> void:
		if _tracks.has(sid):
			(_tracks[sid] as AudioStreamPlayer).play())


func _fade_track(sid: String, to_db: float, fade: float, free_after: bool) -> void:
	if not _tracks.has(sid):
		return
	var p: AudioStreamPlayer = _tracks[sid]
	if _tweens.has(sid) and is_instance_valid(_tweens[sid]):
		(_tweens[sid] as Tween).kill()
		_tweens.erase(sid)
	if fade <= 0.0 or _instant():
		p.volume_db = to_db
		if free_after:
			_stop_track(sid)
		return
	var tw: Tween = create_tween()
	tw.tween_property(p, "volume_db", to_db, fade)
	_tweens[sid] = tw
	if free_after:
		tw.finished.connect(_stop_track.bind(sid))


func _stop_track(sid: String) -> void:
	if not _tracks.has(sid):
		return
	var p: AudioStreamPlayer = _tracks[sid]
	if is_instance_valid(p):
		p.stop()
		remove_child(p)
		p.queue_free()
	_tracks.erase(sid)
	_targets.erase(sid)
	_tweens.erase(sid)


func _load_stem(sid: String) -> AudioStream:
	var path: String = STEM_DIR + sid + ".ogg"
	if not ResourceLoader.exists(path):
		if not _warned.has(sid):
			_warned[sid] = true
			push_warning("MusicDirector: stem not baked yet: %s (run tools/music-bake)" % path)
		return null
	return load(path) as AudioStream


func _instant() -> bool:
	var router: Node = _autoload("SceneRouter")
	return router != null and router.get("instant_mode") == true


func _connect(obj: Object, sig: String, target: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, target):
		obj.connect(sig, target)


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
