class_name WoWAncientText
extends Control

# WoW UI AncientText scramble-resolve decode component (issue #61).
#
# A reusable Control that renders a line of text which starts as obfuscated
# "Ancient" glyphs and resolves left-to-right into readable English over time.
# This is the WoW-UI-layer widget that the discovery toast (#63), door plaques
# (#64), and any future "decrypt" affordance share so the decode effect reads
# as ONE consistent mechanic across the HUD.
#
# Layering:
#   scripts/ancient_text.gd  — the pure cipher engine (static scramble/decode,
#                              the Lantean font, Label/Label3D/TextMesh helpers).
#                              Heavily referenced by hud.gd, door.gd, room.gd,
#                              kino_remote.gd + 3 smoke tests. NOT changed here.
#   scripts/ui/ancient_text.gd (THIS) — the WoW UI Control component. Encapsulates
#                              the decode animation as a self-contained Control
#                              with a RichTextLabel body, so a parent widget
#                              (toast, plaque, HUD line) just calls `play(text)`
#                              and gets the scramble→resolve effect for free.
#
# The body is a RichTextLabel (not a Label) so the per-character decode can mix
# the readable font prefix with the shimmering Ancient-glyph suffix on one line
# (see AncientText.decode_richtext). The Control sizes itself to its content
# (fit_content) so the parent can centre it without measuring.
#
# Honors SceneRouter.instant_mode (resolves same-frame, no tween) so headless
# tests / fast-travel never depend on timing.
#
# @no-save: this is a display-only node script — no state to persist. The
# save-registration policy does not apply (not an autoload).

const _ANCIENT_TEXT: GDScript = preload("res://scripts/ancient_text.gd")

# Visual tunables — kept cohesive with the shared WoW skin (hud.gd::SKIN_* /
# HudTheme). Defaults match the discovery toast so a parent that doesn't
# override them still reads as the same skin.
const DEFAULT_FONT_SIZE: int = 34
const DEFAULT_OUTLINE_SIZE: int = 6
const DEFAULT_TEXT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const DEFAULT_OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.9)
# Per-character decode cadence (seconds per character). Total decode time
# scales with the name length — the same rate the discovery toast uses.
const DEFAULT_SECS_PER_CHAR: float = 0.08

var _label: RichTextLabel = null
var _tween: Tween = null
# Last text we resolved to — callers can read it back to compare against the
# expected final value (used by the cohesion test).
var _resolved_text: String = ""


func _ready() -> void:
	# Build the body once. fit_content keeps the Control sized to the text so
	# the parent VBox/CenterContainer can centre it without measuring.
	if _label == null:
		_label = RichTextLabel.new()
		_label.name = "Body"
		_label.bbcode_enabled = true
		_label.fit_content = true
		_label.scroll_active = false
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.add_theme_font_size_override("normal_font_size", DEFAULT_FONT_SIZE)
		_label.add_theme_color_override("default_color", DEFAULT_TEXT_COLOR)
		_label.add_theme_color_override("font_outline_color", DEFAULT_OUTLINE_COLOR)
		_label.add_theme_constant_override("outline_size", DEFAULT_OUTLINE_SIZE)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The Control itself is display-only — never eat world clicks.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)


# Decode `text` from obfuscated Ancient glyphs into readable English, locking
# left→right one character at a time at `secs_per_char`. Respects
# SceneRouter.instant_mode (resolves same-frame). Safe to call again before a
# prior decode finishes — the old tween is killed first.
func play(text: String, secs_per_char: float = DEFAULT_SECS_PER_CHAR) -> void:
	_ensure_body()
	_resolved_text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	# Delegate to the cipher engine's RichTextLabel path — it handles the
	# per-character shimmer + the readable-font flip + instant_mode.
	_ANCIENT_TEXT.decode_richtext(_label, text, self, secs_per_char)


# Skip the animation entirely — assign the fully-resolved text now. The
# instant_mode / headless shortcut.
func reveal_instant(text: String) -> void:
	_ensure_body()
	_resolved_text = text
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	_label.text = _escape_bbcode(text)


# Put the label into the locked (Ancient-glyph) steady state — the real text
# rendered in the Lantean font (a consistent cipher). Use this for a plaque /
# sign that should read as encrypted until a decode is triggered.
func set_locked(text: String) -> void:
	_ensure_body()
	_resolved_text = text
	_ANCIENT_TEXT.set_locked(_label, text)


# Revert the label to the readable font + plain text. Use this to clear a
# locked state without running the decode animation.
func set_readable(text: String) -> void:
	_ensure_body()
	_resolved_text = text
	_ANCIENT_TEXT.set_readable_font(_label)
	_label.text = _escape_bbcode(text)


# The text this component last resolved to (the "real" name). Callers can read
# this to compare against the expected value without depending on the tween
# having finished.
func resolved_text() -> String:
	return _resolved_text


# The body RichTextLabel — exposed so a parent that needs to read the live
# (mid-decode) text can do so (the cohesion test asserts it ends up readable).
func body() -> RichTextLabel:
	return _label


func _ensure_body() -> void:
	if _label == null:
		_ready()


# BBCode opening-bracket escape — same defensive escape the cipher engine uses
# (room names never contain `[`, but escape so a stray bracket can't swallow
# the rest of the line).
static func _escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")