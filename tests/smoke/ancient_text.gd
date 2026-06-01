extends SceneTree

# Smoke test for the AncientText scramble-resolve decode component (issue #61).
#
# The cipher under test is a PURE STATIC FUNCTION, so the boundary / length /
# determinism properties can be asserted synchronously in _initialize without
# any frames ticking. The animated Label helper (play / reveal_instant /
# instant_mode) needs a node in the tree + a frame, so it is deferred.
#
# Per the class_name-headless gotcha, the script is loaded by path and invoked
# via the loaded GDScript object (duck-typed) rather than the `AncientText`
# identifier, which may not be registered in the same headless run.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/ancient_text.gd

const SCRIPT_PATH: String = "res://scripts/ancient_text.gd"

var _AncientText: GDScript
var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== ancient_text smoke test ===")
	_AncientText = load(SCRIPT_PATH) as GDScript
	_expect(_AncientText != null, "scripts/ancient_text.gd loads as a GDScript")
	if _AncientText == null:
		_report()
		return

	_test_glyph_set_renderable()
	_test_boundary_zero_hides_all()
	_test_boundary_one_is_verbatim()
	_test_whitespace_and_length_preserved()
	_test_determinism()
	_test_frontier_advances_left_to_right()

	# The Label helper needs a node in the tree + a tick; defer past frame 0.
	call_deferred("_run_node_checks")


func _scramble(text: String, progress: float, seed: int = 0) -> String:
	return _AncientText.scramble(text, progress, seed)


# --- Glyph set must stay in the renderable ASCII range (no tofu). -----------
func _test_glyph_set_renderable() -> void:
	var glyphs: String = _AncientText.ANCIENT_GLYPHS
	_expect(glyphs.length() > 0, "ANCIENT_GLYPHS is non-empty")
	var all_safe: bool = true
	for i in range(glyphs.length()):
		var code: int = glyphs.unicode_at(i)
		# Printable ASCII excluding space (0x21..0x7E).
		if code < 0x21 or code > 0x7E:
			all_safe = false
	_expect(all_safe, "every glyph is printable ASCII (renders in kit fonts, no tofu)")


# --- progress <= 0.0 → no original non-space char survives. -----------------
func _test_boundary_zero_hides_all() -> void:
	var s: String = "DESTINY GATE ROOM"
	var scrambled: String = _scramble(s, 0.0)
	var leaked: bool = false
	for i in range(s.length()):
		var ch: String = s[i]
		if ch == " ":
			continue
		if scrambled[i] == ch:
			leaked = true
	_expect(not leaked, "scramble(s, 0.0) leaks no original non-space character")
	# Also assert at a hard negative to confirm clamping.
	var negative: String = _scramble(s, -0.5)
	_expect(negative.length() == s.length(), "scramble(s, -0.5) preserves length")
	# Regression (#61 review): input made entirely of glyph-set chars must still
	# never leak — the re-roll guard ensures a drawn glyph != the source char,
	# even when the source char is itself one of ANCIENT_GLYPHS.
	var punct: String = _AncientText.ANCIENT_GLYPHS
	var punct_leaked: bool = false
	for seed in range(2000):
		var out: String = _scramble(punct, 0.0, seed)
		for i in range(punct.length()):
			if out[i] == punct[i]:
				punct_leaked = true
				break
		if punct_leaked:
			break
	_expect(not punct_leaked, "scramble(glyph-only input, 0.0) never leaks (re-roll guard, 2000 seeds)")


# --- progress >= 1.0 → verbatim. --------------------------------------------
func _test_boundary_one_is_verbatim() -> void:
	var s: String = "Eli Wallace"
	_expect(_scramble(s, 1.0) == s, "scramble(s, 1.0) == s")
	_expect(_scramble(s, 2.0) == s, "scramble(s, 2.0) clamps to verbatim")
	_expect(_scramble("", 0.0) == "", "empty string scrambles to empty")


# --- Spaces/newlines preserved + length invariant at every progress. --------
func _test_whitespace_and_length_preserved() -> void:
	var s: String = "ROOM A\nDECK 3\tSECTION B"
	var probes: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
	var length_ok: bool = true
	var whitespace_ok: bool = true
	for p in probes:
		var out: String = _scramble(s, p)
		if out.length() != s.length():
			length_ok = false
		for i in range(s.length()):
			var ch: String = s[i]
			if ch == " " or ch == "\n" or ch == "\t" or ch == "\r":
				if out[i] != ch:
					whitespace_ok = false
	_expect(length_ok, "output length == original length at every progress")
	_expect(whitespace_ok, "spaces/tabs/newlines pass through at every progress")


# --- Same (text, progress, seed) is deterministic. --------------------------
func _test_determinism() -> void:
	var s: String = "ANCIENT CONSOLE"
	_expect(_scramble(s, 0.3, 7) == _scramble(s, 0.3, 7),
		"same (text, progress, seed) is identical")
	# Different seeds should (almost surely) churn the glyphs — sanity that the
	# seed actually feeds the RNG, not that it is guaranteed unequal.
	_expect(_scramble(s, 0.0, 1) != _scramble(s, 0.0, 999),
		"different seeds produce different glyph fields")


# --- Resolve frontier advances left-to-right. -------------------------------
func _test_frontier_advances_left_to_right() -> void:
	var s: String = "ABCDEFGHIJ"
	var half: String = _scramble(s, 0.5, 3)
	# First half resolved, back half scrambled.
	var prefix_ok: bool = half.substr(0, 5) == "ABCDE"
	_expect(prefix_ok, "left half resolves before the right (frontier moves L→R)")
	var more: String = _scramble(s, 0.8, 3)
	_expect(more.substr(0, 5) == "ABCDE", "higher progress keeps earlier chars resolved")


# --- Node helper: play() under instant_mode resolves same frame. ------------
func _run_node_checks() -> void:
	var router: Node = root.get_node_or_null("/root/SceneRouter")
	# Build a Label-subclass node from the script and add it to the tree.
	var label: Node = _AncientText.new()
	root.add_child(label)
	await process_frame

	# reveal_instant assigns verbatim immediately.
	var s: String = "DECODE ME"
	label.reveal_instant(s)
	_expect(label.get("text") == s, "reveal_instant assigns verbatim text")

	# play() with instant_mode set must resolve on the same frame (no tween wait).
	var had_router: bool = router != null
	var prev: bool = false
	if had_router:
		prev = router.get("instant_mode")
		router.set("instant_mode", true)
	label.play("INSTANT REVEAL", 5.0)
	_expect(label.get("text") == "INSTANT REVEAL",
		"play() under instant_mode resolves on the same frame")
	if had_router:
		router.set("instant_mode", prev)

	# play() with a zero/negative duration short-circuits to instant too.
	label.play("ZERO DURATION", 0.0)
	_expect(label.get("text") == "ZERO DURATION", "play(duration<=0) resolves instantly")

	root.remove_child(label)
	label.free()
	_report()


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)
