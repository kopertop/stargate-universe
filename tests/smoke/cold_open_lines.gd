extends SceneTree

# Drift guard for the E1 cold-open dialog (#142): every `open-*` VO id referenced
# in scripts/gate_room.gd (via _cold_open_line / _bark) must be declared as a line
# in design/voice-line-manifest.md section 18. Catches a renamed or typo'd vo-id
# that would silently drop a cold-open beat to caption-only — and guards that the
# six climax hand-off beats stay wired. Headless, no assets, no autoloads.
#
# Run with:
#   godot --headless -s res://tests/smoke/cold_open_lines.gd

const GATE_ROOM: String = "res://scripts/gate_room.gd"
const MANIFEST: String = "res://design/voice-line-manifest.md"

# The closing hand-off, exactly as _play_rush_handoff sequences it. If any of these
# stops being referenced in code, the climax lost a beat — fail loudly.
const REQUIRED_HANDOFF: Array[String] = [
	"open-crew-whatwasthat", "open-scott-norush", "open-scott-rush",
	"open-scott-findhim", "open-scott-eli-now", "open-eli-coming",
]

var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	# Arrange: pull the vo-ids out of the code and the manifest.
	var code: String = _read(GATE_ROOM)
	var manifest: String = _read(MANIFEST)
	if code == "" or manifest == "":
		_report()
		return
	var referenced: Array[String] = _ids_in(code)
	var declared: Dictionary = {}
	for id: String in _ids_in(manifest):
		declared[id] = true

	# Act / Assert.
	test_cold_open_vo_ids_all_declared_in_manifest(referenced, declared)
	test_cold_open_handoff_beats_present_in_code(referenced)
	_report()


# Every vo-id the cinematic plays must be a real manifest line.
func test_cold_open_vo_ids_all_declared_in_manifest(referenced: Array[String], declared: Dictionary) -> void:
	if referenced.is_empty():
		_fail("no open-* vo-ids found in gate_room.gd (extraction broken?)")
		return
	for id: String in referenced:
		if declared.has(id):
			_passes += 1
		else:
			_fail("vo-id '%s' referenced in gate_room.gd but missing from voice-line-manifest.md §18" % id)


# The six climax beats must all still be wired in code.
func test_cold_open_handoff_beats_present_in_code(referenced: Array[String]) -> void:
	for id: String in REQUIRED_HANDOFF:
		if referenced.has(id):
			_passes += 1
		else:
			_fail("required hand-off beat '%s' is no longer referenced in gate_room.gd" % id)


func _ids_in(text: String) -> Array[String]:
	var out: Array[String] = []
	var re: RegEx = RegEx.new()
	re.compile("open-[a-z0-9]+(?:-[a-z0-9]+)*")
	for m: RegExMatch in re.search_all(text):
		var id: String = m.get_string()
		if not out.has(id):
			out.append(id)
	return out


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot open %s" % path)
		return ""
	return f.get_as_text()


func _fail(reason: String) -> void:
	print("  FAIL: ", reason)
	_failures.append(reason)


func _report() -> void:
	print("\n=== cold_open_lines summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f: String in _failures:
		print("  - ", f)
	quit(1)
