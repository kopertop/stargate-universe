class_name RoomDiscoveryToast
extends Control

# WoW UI room discovery toast (issue #63).
#
# A centred notification that fires when the player discovers a new room: a
# small letter-spaced "DISCOVERED" header above the room name, which starts as
# obfuscated Ancient glyphs and decodes into readable English via the
# WoWAncientText component (#61). The whole stack then fades to transparent
# over DISCOVERY_FADE_SECS. Changing rooms short-circuits the fade.
#
# This is the reusable WoW-UI-layer widget. The HUD (hud.gd) mounts it as a
# child of its DiscoveryToast CenterContainer and drives it via `show_for(room_id)`
# / `hide_now()`. The decode effect + fade timing + audio sting live HERE so
# the HUD doesn't re-implement them per call site.
#
# Honors SceneRouter.instant_mode (resolves + hides same-frame, no tween, no
# audio) so headless tests / fast-travel never depend on timing.
#
# @no-save: display-only node script — no state to persist. Not an autoload.

const _ANCIENT_TEXT_UI: GDScript = preload("res://scripts/ui/ancient_text.gd")
const _HUD_THEME: GDScript = preload("res://scripts/ui/hud_theme.gd")

# Fade duration (seconds) after the decode completes. The whole toast fades
# to transparent over this window.
const FADE_SECS: float = 3.0
# Per-letter decode rate for the room-name reveal. Each character flips from
# its Ancient glyph to readable Latin one at a time, left→right, at this
# cadence — total decode time scales with name length.
const DECODE_SECS_PER_CHAR: float = 0.08
# Discovery header text — letter-spaced "DISCOVERED".
const HEADER_TEXT: String = "D I S C O V E R E D"

# Audio stings (skipped under instant_mode / headless).
const STING_SOUND: String = "res://sounds/discovery_stinger.ogg"
const STING_KEY_SOUND: String = "res://sounds/discovery_stinger_key.ogg"

var _root: CenterContainer = null
var _header: Label = null
var _name_component: Control = null   # WoWAncientText instance (duck-typed)
var _fade: Tween = null
# Room the live toast is announcing. discover_room() is followed immediately by
# set_current_room(SAME id) when entering a room, so the room-change short-circuit
# must ignore a change INTO the room the toast is already for, and only fire
# when the player moves on to a DIFFERENT room.
var _room_id: String = ""


func _ready() -> void:
	# Build the centred stack: header over the AncientText name line.
	# Anchored to the full rect so it sits dead-centre at any resolution.
	_root = CenterContainer.new()
	_root.name = "Stack"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.z_index = 90
	_root.visible = false
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_root)

	var box: VBoxContainer = VBoxContainer.new()
	box.name = "VStack"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_header = Label.new()
	_header.name = "Header"
	_header.text = HEADER_TEXT
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 16)
	# Header shares the shared gold accent at full opacity (the header must
	# read crisply over the world), keeping the hue identical to the unit
	# frame / action-bar borders.
	_header.add_theme_color_override("font_color", _HUD_THEME.ACCENT_GOLD)
	_header.add_theme_color_override("font_outline_color", _HUD_THEME.TEXT_OUTLINE)
	_header.add_theme_constant_override("outline_size", 4)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_header)

	# The AncientText name line — a WoWAncientText Control instance.
	_name_component = _ANCIENT_TEXT_UI.new()
	_name_component.name = "RoomName"
	_name_component.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name_component)

	# The Control itself is display-only.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# Show the toast for `room_id` with its display name. Resolves the name via
# ShipLayout, runs the decode, plays the sting (non-instant only), then fades
# the whole toast out over FADE_SECS. Safe to call again before a prior toast
# finishes — the old fade is killed first.
func show_for(room_id: String, display_name: String) -> void:
	_ensure_built()
	# Cancel a still-running fade from a prior discovery so the new toast
	# shows at full opacity.
	if _fade != null and _fade.is_running():
		_fade.kill()
	_fade = null

	_room_id = room_id
	_root.visible = true
	_root.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Per-letter glyph→Latin decode via the AncientText component.
	_name_component.call("play", display_name, DECODE_SECS_PER_CHAR)

	# Decode sting — skipped under instant_mode (headless / fast-travel) so
	# the playthrough test never queues audio it can't drain. KEY rooms
	# (Control Interface Room, Kino Room, Bridge, …) get the special
	# "magical discovery" cue.
	var router: Node = get_node_or_null("/root/SceneRouter")
	var instant: bool = router != null and router.get("instant_mode") == true
	if not instant and has_node("/root/Audio"):
		var ps: Node = get_node_or_null("/root/ProceduralShip")
		var is_key: bool = false
		if ps != null and ps.has_method("is_key_room"):
			is_key = ps.call("is_key_room", room_id)
		var sting: String = STING_KEY_SOUND if is_key else STING_SOUND
		get_node("/root/Audio").call("play", sting)

	# Under instant_mode the toast resolves + hides immediately.
	if instant:
		hide_now()
		return

	# Hold until the per-letter decode finishes, then fade.
	var decode_total: float = float(display_name.length()) * DECODE_SECS_PER_CHAR
	_fade = create_tween()
	_fade.tween_interval(decode_total)
	_fade.tween_property(_root, "modulate:a", 0.0, FADE_SECS)
	_fade.tween_callback(Callable(self, "hide_now"))


# Hide the toast immediately — used when the player changes rooms (to a
# DIFFERENT room than the one being announced) so a stale toast never lingers.
func hide_now() -> void:
	if _fade != null and _fade.is_running():
		_fade.kill()
	_fade = null
	if _root != null:
		_root.visible = false
		_root.modulate = Color(1.0, 1.0, 1.0, 0.0)


# The room id the live toast is announcing. The HUD uses this to decide
# whether a room change should short-circuit the in-flight toast.
func room_id() -> String:
	return _room_id


# True when the toast is currently visible / animating.
func is_showing() -> bool:
	return _root != null and _root.visible


func _ensure_built() -> void:
	if _root == null:
		_ready()