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
# The "locked" steady state (a room found but not yet DECIPHERED) is now drawn
# in a real Ancient/Lantean glyph font (Anquietas) instead of churning ASCII:
# rendering the plain text in that font yields a CONSISTENT 1:1 substitution
# cipher (the same name always maps to the same glyphs), which reads as
# encryption rather than random static. `scramble()` is still used for the
# brief decode ANIMATION (the cascade into readable English), drawn in the
# readable font so its ASCII churn never hits a missing-glyph tofu box.
#
# @no-save handled at the autoload layer — this is a node script, not an
# autoload, so the save-registration policy does not apply.

# Glyph set drawn for un-resolved positions. Restricted to printable ASCII
# punctuation/symbols so it renders cleanly in lilita_one_regular.ttf and the
# Godot default font — box-drawing / Unicode runes risk tofu boxes in the kit
# fonts (see issue notes). These read as terse alien sigils while staying in
# the safe BMP/Latin range.
const ANCIENT_GLYPHS: String = "/\\|=+#%&@$*<>~^?!:;-_[]{}()"

# Glyph pool used when the churn is drawn IN the Ancient font (the decode
# animation). A-Z map 1:1 to Lantean glyphs in anquietas, so churning over
# letters yields shuffling alien glyphs — not punctuation tofu. Distinct from
# ANCIENT_GLYPHS above, which is the readable-font fallback (printable ASCII).
const LETTER_GLYPHS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# Ancient/Lantean glyph font. load()ed once (NOT preload) so a missing asset
# degrades gracefully to the ASCII scramble instead of failing to parse this
# script — see fonts/AGENTS.md for why this font is the documented exception
# to the "reference fonts through scenes" rule (it's applied procedurally to
# code-built Label3D / TextMesh / canvas draws, none of them editor scenes).
const ANCIENT_FONT_PATH: String = "res://fonts/ancient_anquietas.ttf"
static var _ancient_font: Font = null
static var _ancient_font_loaded: bool = false


# Lazily load + cache the Ancient font. Returns null if the asset is absent,
# so every caller can fall back to the readable-font scramble.
static func ancient_font() -> Font:
	if not _ancient_font_loaded:
		_ancient_font_loaded = true
		if ResourceLoader.exists(ANCIENT_FONT_PATH):
			_ancient_font = load(ANCIENT_FONT_PATH)
	return _ancient_font


# --- Locked-state font API (Label / Label3D / TextMesh) ---------------------
#
# `set_locked` puts a text node into the encrypted steady state: the real text,
# upper-cased, rendered in the Ancient font (consistent cipher). If the font is
# missing it falls back to a STATIC scramble (seed 0 — stable, not shimmering)
# in whatever font the node already uses, so the obfuscation still holds.
#
# `set_readable_font` reverts the node to its default (readable) font — call it
# at the START of a decode animation so the resolve cascade is legible Latin.
#
# Works across the three text carriers the game uses without a shared base type:
#   - 2D `Label`   → theme font override
#   - `Label3D`    → `.font` property
#   - `TextMesh`   → `.font` property (a Mesh resource, not a Node)
static func set_locked(node: Object, text: String) -> void:
	var font: Font = ancient_font()
	if font == null:
		_assign_text(node, scramble(text, 0.0, 0))
		return
	_assign_font(node, font)
	_assign_text(node, text.to_upper())


static func set_readable_font(node: Object) -> void:
	_assign_font(node, null)


static func _assign_font(node: Object, font: Font) -> void:
	if node is Label:
		if font == null:
			(node as Label).remove_theme_font_override("font")
		else:
			(node as Label).add_theme_font_override("font", font)
	elif node is Label3D or node is TextMesh:
		# Both expose a `font` property; null reverts to the theme default.
		node.set("font", font)


static func _assign_text(node: Object, value: String) -> void:
	node.set("text", value)


# Animated decode of any text carrier (Label / Label3D / TextMesh) from its
# locked Ancient state into readable `final_text`. The churn is drawn IN the
# Ancient font over the LETTER_GLYPHS pool, so the "decrypting" frames are
# shuffling Lantean glyphs (not ASCII punctuation) that lock in left→right;
# the final callback flips the whole line to the readable font + English.
# `host` is any Node — used for the tween + the SceneRouter lookup. instant_mode
# / zero duration settle immediately (readable, no tween) so the headless
# playthrough and captures never depend on timing.
static func decode(node: Object, final_text: String, host: Node, duration: float = 1.0) -> void:
	var router: Node = host.get_node_or_null("/root/SceneRouter")
	if duration <= 0.0 or (router != null and router.get("instant_mode") == true):
		set_readable_font(node)
		_assign_text(node, final_text)
		return
	# Churn the upper-cased name in the Ancient font (falls back to readable +
	# letter churn if the font asset is missing — still no punctuation).
	var glyphs: String = final_text.to_upper()
	_assign_font(node, ancient_font())
	var tw: Tween = host.create_tween()
	tw.tween_method(
		func(v: float) -> void: _assign_text(node, scramble(glyphs, v, Engine.get_process_frames(), LETTER_GLYPHS)),
		0.0, 1.0, duration)
	tw.tween_callback(func() -> void:
		set_readable_font(node)
		_assign_text(node, final_text))

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
# static obfuscated plaque. Same (text, progress, seed, pool) is deterministic.
#
# `pool` is the character set drawn for unresolved positions. Defaults to the
# ASCII ANCIENT_GLYPHS (safe in any font). Pass LETTER_GLYPHS when the node is
# rendered in the Ancient font so the churn shows shuffling Lantean glyphs.
static func scramble(text: String, progress: float, seed: int = 0, pool: String = ANCIENT_GLYPHS) -> String:
	if progress >= 1.0:
		return text
	var glyph_count: int = pool.length()
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
		var glyph: String = pool[rng.randi_range(0, glyph_count - 1)]
		# If the source char is itself a glyph (e.g. punctuation input), the draw
		# can coincide with it and leak the original — re-roll deterministically
		# until it differs, so an un-resolved position NEVER shows its real char.
		var guard: int = 0
		while glyph == ch and guard < glyph_count:
			rng.seed = hash([seed, i, guard])
			glyph = pool[rng.randi_range(0, glyph_count - 1)]
			guard += 1
		out += glyph
	return out


# --- 2D Label convenience helper --------------------------------------------

func _ready() -> void:
	if auto_play_on_ready and play_text != "":
		play(play_text, play_duration)


# Decode `text` into this Label: shuffling Ancient glyphs (drawn in the Ancient
# font) locking in left→right, then a flip to readable English — the shared
# decode() drives it. Respects SceneRouter.instant_mode (resolves same frame).
func play(text: String, duration: float = 1.2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	AncientText.decode(self, text, self, duration)


# Skip the animation entirely — assign the fully-resolved text now. The
# instant_mode / headless shortcut.
func reveal_instant(text: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	AncientText.set_readable_font(self)
	self.text = text
