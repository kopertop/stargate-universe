extends Label
class_name AncientText

# Shared "Ancient" scramble-resolve decode effect (issue #61).
#
# Animates a string from obfuscated "alien" glyphs into resolved English,
# locking characters left-to-right (a classic "decryption" reveal). The cipher
# is a PURE STATIC FUNCTION (`scramble`) so both a 2D `Label` and a 3D `Label3D`
# can drive it without sharing a node type — the caller just assigns the result
# to its own `.text`. This thin `Label` subclass is an OPTIONAL convenience for
# the 2D toast consumer (#31): `play(text, duration)` tweens the progress and
# writes `.text` each step.
#
# Foundation for:
#   - the room discovery toast (#31, 2D Label)
#   - the door plaque obfuscation (#31, 3D Label3D)
#
# @no-save handled at the autoload layer — this is a node script, not an
# autoload, so the save-registration policy does not apply.

# Glyph set drawn for un-resolved positions. Restricted to printable ASCII
# punctuation/symbols so it renders cleanly in lilita_one_regular.ttf and the
# Godot default font — box-drawing / Unicode runes risk tofu boxes in the kit
# fonts (see issue notes). These read as terse alien sigils while staying in
# the safe BMP/Latin range.
const ANCIENT_GLYPHS: String = "/\\|=+#%&@$*<>~^?!:;-_[]{}()"

@export var auto_play_on_ready: bool = false
@export var play_text: String = ""
@export var play_duration: float = 1.2

var _tween: Tween


# --- Pure cipher ------------------------------------------------------------
#
# Returns `text` with every non-space character left of the resolve frontier
# shown verbatim and every character right of it replaced by a deterministic
# "ancient" glyph. Spaces, tabs and newlines ALWAYS pass through so word shape
# (and string length) is preserved at every progress value.
#
#   progress <= 0.0  → every non-space char is a glyph
#   progress >= 1.0  → returns `text` verbatim
#
# `seed` keeps the per-call glyph churn stable for a given node: animate it
# per frame (e.g. seed = frame_index) for a shimmer, or hold it constant for a
# static obfuscated plaque. Same (text, progress, seed) is deterministic.
static func scramble(text: String, progress: float, seed: int = 0) -> String:
	if progress >= 1.0:
		return text
	var glyph_count: int = ANCIENT_GLYPHS.length()
	var n: int = text.length()
	# Frontier = index of the first still-unresolved character. Clamp progress
	# into [0,1] so callers can't push the frontier past either end.
	var p: float = clampf(progress, 0.0, 1.0)
	var resolved: int = int(floor(p * float(n)))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var out: String = ""
	for i in range(n):
		var ch: String = text[i]
		# Word shape: whitespace is structural, never scrambled.
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			out += ch
			continue
		if i < resolved:
			out += ch
			continue
		# Deterministic glyph for this (seed, position): seeding per char keeps
		# neighbours independent so the field looks like noise, not a pattern.
		rng.seed = hash([seed, i])
		var glyph: String = ANCIENT_GLYPHS[rng.randi_range(0, glyph_count - 1)]
		# If the source char is itself a glyph (e.g. punctuation input), the draw
		# can coincide with it and leak the original — re-roll deterministically
		# until it differs, so an un-resolved position NEVER shows its real char.
		var guard: int = 0
		while glyph == ch and guard < glyph_count:
			rng.seed = hash([seed, i, guard])
			glyph = ANCIENT_GLYPHS[rng.randi_range(0, glyph_count - 1)]
			guard += 1
		out += glyph
	return out


# --- 2D Label convenience helper --------------------------------------------

func _ready() -> void:
	if auto_play_on_ready and play_text != "":
		play(play_text, play_duration)


# Tween this Label's `.text` from fully scrambled to the resolved `text` over
# `duration` seconds, shimmering the un-resolved glyphs each step. Respects
# SceneRouter.instant_mode (headless / fast-travel): resolves on the same frame
# so smoke + playthrough tests never wait on a tween.
func play(text: String, duration: float = 1.2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	var router: Node = get_node_or_null("/root/SceneRouter")
	if duration <= 0.0 or (router != null and router.get("instant_mode") == true):
		reveal_instant(text)
		return
	# tween_method rewrites .text each tick. A live frame counter feeds `seed` so
	# the un-resolved field shimmers, not strobes.
	self.text = scramble(text, 0.0, 0)
	_tween = create_tween()
	_tween.tween_method(
		func(v: float) -> void:
			self.text = scramble(text, v, Engine.get_process_frames()),
		0.0, 1.0, duration)
	_tween.tween_callback(func() -> void: self.text = text)


# Skip the animation entirely — assign the fully-resolved text now. The
# instant_mode / headless shortcut.
func reveal_instant(text: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	self.text = text
