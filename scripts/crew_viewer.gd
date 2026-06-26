extends Node

# @no-save: dev/preview UI overlay only. Edits a transient preview character built
# from CharacterFactory profiles (which live in code); persists nothing of its own.
#
# In-game CREW VIEWER (#preview-and-tweak). A WoW-style full-screen overlay that
# renders each registered crew member as a live 3D turntable and lets you tweak their
# look — hairstyle, hair colour, skin tone, and ship/mission outfit — to dial in the
# correct likeness (e.g. TJ blonde, Greer dark-skinned). Tweaks are PREVIEW-only; the
# "Copy profile snippet" button puts the chosen `"mod": {…}` line on the clipboard so
# the values can be baked into scripts/character_factory.gd (profiles are code — the
# project's single source of truth — so we don't persist a runtime override file).
#
# Built programmatically onto its own CanvasLayer so it attaches to every gameplay
# scene with no per-scene wiring — same pattern as CharacterPanel / PauseMenu / Kino.
# Toggled with the `crew_viewer` action ([V]); respects the shared overlay gotchas:
#   - Only the OPEN path of the toggle is gated (other overlays up → [V] ignored).
#   - Mouse mode forced VISIBLE on open, prior mode restored on close.
#   - Tree paused while open; the overlay processes ALWAYS (turntable keeps spinning).
#
# The 3D preview uses a SubViewport with its OWN world (own_world_3d) so the lab
# lighting can't leak into — or be lit by — the paused gameplay scene behind it.

const CharacterFactoryRef: Script = preload("res://scripts/character_factory.gd")

const ACCENT: Color = Color(0.60, 0.78, 0.95, 0.85)
const ACCENT_GOLD: Color = Color(1.0, 0.84, 0.42, 1.0)
const PANEL_BG: Color = Color(0.04, 0.06, 0.09, 0.96)
const TEXT_PRIMARY: Color = Color(0.95, 0.98, 1.0, 1.0)
const TEXT_DIM: Color = Color(0.70, 0.82, 0.95, 0.85)

# Tweakable option pools. Hair meshes are the pack's full set (+ none); the pack has
# no curly mesh, so Hair_Long stands in for curly/long looks (e.g. TJ).
const HAIR_STYLES: Array[String] = [
	"(none)", "Hair_Long", "Hair_Buns", "Hair_Buzzed", "Hair_BuzzedFemale",
	"Hair_SimpleParted", "Hair_Beard",
]
const HAIR_COLORS: Array = [
	["Black", Color(0.07, 0.06, 0.06)], ["Dark brown", Color(0.22, 0.14, 0.08)],
	["Brown", Color(0.42, 0.27, 0.14)], ["Auburn", Color(0.40, 0.18, 0.10)],
	["Blonde", Color(0.83, 0.69, 0.40)], ["Grey", Color(0.62, 0.62, 0.64)],
]
# Skin tones as albedo MULTIPLY over the base skin texture (Color.WHITE = pack default,
# i.e. no tint). Darker tones via set_skin_tint (the pack "_Dark" body is actually tan).
const SKIN_TONES: Array = [
	["Default", Color.WHITE], ["Tan", Color(0.78, 0.58, 0.44)],
	["Brown", Color(0.55, 0.36, 0.24)], ["Dark", Color(0.40, 0.24, 0.16)],
	["Deep", Color(0.28, 0.17, 0.11)],
]
const CONTEXTS: Array[String] = ["ship", "mission"]

var _layer: CanvasLayer
var _root: Control
var _name_label: Label
var _detail_label: Label
var _viewport: SubViewport
var _char: Node3D
var _char_pivot: Node3D

var _open: bool = false
var _initialized: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

var _names: Array = []
var _idx: int = 0
# Per-session tweak state for the current character (seeded from its profile on select).
var _hair_i: int = 0
var _haircol_i: int = 0
var _skin_i: int = 0
var _ctx_i: int = 0


# Dev/QA capture: `--cli-arg crewviewer_shot=<Name>` (or index) auto-opens the viewer
# on that crew member and saves user://crew_viewer.png after a few frames. 0/empty off.
var _shot_name: String = ""
var _shot_frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("crewviewer_shot="):
			_shot_name = arg.substr(16).replace("+", " ")
	call_deferred("_init_ui")
	if _shot_name != "":
		call_deferred("_begin_shot")


func _begin_shot() -> void:
	GameState.current_scene_path = "res://scenes/title.tscn"   # satisfy open()'s guard
	var i: int = _names.find(_shot_name)
	if i < 0 and _shot_name.is_valid_int():
		i = int(_shot_name)
	_idx = maxi(0, i)
	open()


func _process(delta: float) -> void:
	if _open and _char_pivot != null and is_instance_valid(_char_pivot):
		_char_pivot.rotation.y += delta * 0.6
	if _shot_name != "" and _open:
		_shot_frames += 1
		if _shot_frames == 2:
			_char_pivot.rotation.y = 0.0   # face camera for the shot
		if _shot_frames >= 40:
			var img: Image = get_viewport().get_texture().get_image()
			img.save_png("user://crew_viewer.png")
			print("[crew_viewer] saved user://crew_viewer.png crew=%s" % _shot_name)
			_tree().quit()


func _init_ui() -> void:
	if _initialized:
		return
	_initialized = true
	_names = CharacterFactoryRef.profile_names()

	_layer = CanvasLayer.new()
	_layer.layer = 89  # below PauseMenu (90), above HUD; peer of CharacterPanel (88).
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_tree().root.add_child(_layer)

	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox())
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -260
	panel.offset_bottom = 260
	_root.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 24)
	panel.add_child(margin)

	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	margin.add_child(cols)

	# --- left: 3D preview ---
	var vp_container: SubViewportContainer = SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.custom_minimum_size = Vector2(360, 460)
	cols.add_child(vp_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(360, 460)
	vp_container.add_child(_viewport)
	_build_preview_stage()

	# --- right: name + tweak controls ---
	var rcol: VBoxContainer = VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 12)
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(rcol)

	var title: Label = Label.new()
	title.text = "CREW VIEWER"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ACCENT_GOLD)
	rcol.add_child(title)

	# crew name + ‹ › cycle row
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	rcol.add_child(name_row)
	name_row.add_child(_nav_button("‹", -1))
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	name_row.add_child(_name_label)
	name_row.add_child(_nav_button("›", 1))

	rcol.add_child(HSeparator.new())

	# tweak rows
	rcol.add_child(_tweak_row("Hair style", _cycle_hair))
	rcol.add_child(_tweak_row("Hair colour", _cycle_haircol))
	rcol.add_child(_tweak_row("Skin tone", _cycle_skin))
	rcol.add_child(_tweak_row("Outfit", _cycle_ctx))

	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", 12)
	_detail_label.add_theme_color_override("font_color", TEXT_DIM)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rcol.add_child(_detail_label)

	var copy_btn: Button = Button.new()
	copy_btn.text = "Copy profile snippet"
	copy_btn.pressed.connect(_copy_snippet)
	rcol.add_child(copy_btn)

	var footer: Label = Label.new()
	footer.text = "[V] / [Esc] Close    ‹ › Cycle crew"
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9, 0.7))
	rcol.add_child(footer)


func _build_preview_stage() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.16)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.9
	env.environment = e
	_viewport.add_child(env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, -0.5, 0.0)
	key.light_energy = 1.3
	_viewport.add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation = Vector3(-0.3, 2.4, 0.0)
	fill.light_energy = 0.4
	_viewport.add_child(fill)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 38.0
	cam.position = Vector3(0.0, 1.05, 3.4)
	cam.rotation = Vector3(-0.06, 0.0, 0.0)
	_viewport.add_child(cam)
	cam.current = true
	_char_pivot = Node3D.new()
	_viewport.add_child(_char_pivot)


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("crew_viewer"):
		return
	if not _open and GameState.current_scene_path == "":
		return
	if not _open:
		for other in ["PauseMenu", "KinoRemote", "CharacterPanel"]:
			var o: Node = _autoload(other)
			if o != null and o.get("_open") == true:
				return
	get_viewport().set_input_as_handled()
	if _open:
		close()
	else:
		open()


func open() -> void:
	if not _initialized:
		_init_ui()
	_open = true
	_root.visible = true
	_idx = clampi(_idx, 0, maxi(0, _names.size() - 1))
	_select(_idx)
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var t: SceneTree = _tree()
	if t != null:
		t.paused = true


func close() -> void:
	_open = false
	if _root != null:
		_root.visible = false
	var t: SceneTree = _tree()
	if t != null:
		t.paused = false
	Input.mouse_mode = _saved_mouse_mode
	var gs: Node = _autoload("GameState")
	if gs != null and gs.has_signal("kino_closed"):
		gs.emit_signal("kino_closed")


func is_open() -> bool:
	return _open


# --- selection + tweaks ------------------------------------------------------

func _cycle(delta: int) -> void:
	if _names.is_empty():
		return
	_idx = (_idx + delta + _names.size()) % _names.size()
	_select(_idx)


func _select(i: int) -> void:
	if _names.is_empty():
		return
	var profile: Dictionary = CharacterFactoryRef.profile_for(String(_names[i]))
	var mod: Dictionary = profile.get("mod", {})
	# Seed the tweak state from the character's actual profile so the controls open
	# reflecting how they currently look, then let the user diverge.
	_hair_i = maxi(0, HAIR_STYLES.find(String(mod.get("hair", "(none)"))))
	_haircol_i = _nearest_color(HAIR_COLORS, mod.get("hair_color", Color(0.3, 0.2, 0.14)))
	_skin_i = _nearest_color(SKIN_TONES, mod.get("skin_tint", Color.WHITE))
	_ctx_i = 0
	_rebuild_char()


func _rebuild_char() -> void:
	if _char != null and is_instance_valid(_char):
		_char.queue_free()
	var nm: String = String(_names[_idx])
	_char = CharacterFactoryRef.build_modular(nm)
	_char_pivot.add_child(_char)
	_char_pivot.rotation.y = 0.0
	CharacterFactoryRef.dress_modular(_char, nm, CONTEXTS[_ctx_i])
	# Apply the live tweaks on top of the dressed profile.
	var hair: String = HAIR_STYLES[_hair_i]
	_char.call("set_slot", "Hair", "" if hair == "(none)" else hair)
	if hair != "(none)":
		_char.call("set_hair_color", HAIR_COLORS[_haircol_i][1])
	var skin: Color = SKIN_TONES[_skin_i][1]
	if skin != Color.WHITE:
		_char.call("set_skin_tint", skin)
	_refresh_labels()


func _refresh_labels() -> void:
	if _names.is_empty():
		return
	_name_label.text = String(_names[_idx])
	_detail_label.text = "Hair: %s · %s\nSkin: %s · Outfit: %s" % [
		HAIR_STYLES[_hair_i], String(HAIR_COLORS[_haircol_i][0]),
		String(SKIN_TONES[_skin_i][0]), CONTEXTS[_ctx_i],
	]


# Hair STYLE and OUTFIT swap the equipped GLB parts, so they need a rebuild. Hair
# COLOUR and SKIN tone are just material recolours on the already-built body — call the
# light setters directly instead of reloading every part GLB on each nudge.
func _cycle_hair() -> void:
	_hair_i = (_hair_i + 1) % HAIR_STYLES.size()
	_rebuild_char()

func _cycle_ctx() -> void:
	_ctx_i = (_ctx_i + 1) % CONTEXTS.size()
	_rebuild_char()

func _cycle_haircol() -> void:
	_haircol_i = (_haircol_i + 1) % HAIR_COLORS.size()
	if _char != null and is_instance_valid(_char) and HAIR_STYLES[_hair_i] != "(none)":
		_char.call("set_hair_color", HAIR_COLORS[_haircol_i][1])
	_refresh_labels()

func _cycle_skin() -> void:
	_skin_i = (_skin_i + 1) % SKIN_TONES.size()
	if _char != null and is_instance_valid(_char):
		_char.call("set_skin_tint", SKIN_TONES[_skin_i][1])   # WHITE = pack default (identity multiply)
	_refresh_labels()


# Put the current tweaks on the clipboard as a profile `"mod"` snippet so they can be
# baked into character_factory.gd (profiles are code — the single source of truth).
func _copy_snippet() -> void:
	var hair: String = HAIR_STYLES[_hair_i]
	var col: Color = HAIR_COLORS[_haircol_i][1]
	var parts: Array = []
	parts.append('"hair": "%s"' % ("" if hair == "(none)" else hair))
	parts.append('"hair_color": Color(%.2f, %.2f, %.2f)' % [col.r, col.g, col.b])
	var skin: Color = SKIN_TONES[_skin_i][1]
	if skin != Color.WHITE:
		parts.append('"skin_tint": Color(%.2f, %.2f, %.2f)' % [skin.r, skin.g, skin.b])
	var snippet: String = '"%s": "mod": {%s}' % [String(_names[_idx]), ", ".join(parts)]
	DisplayServer.clipboard_set(snippet)
	_detail_label.text = "Copied:\n" + snippet


# Index of the option whose colour is closest to `c` (so the controls open on the
# character's current look). Works for both [label, Color] pools.
func _nearest_color(pool: Array, c: Color) -> int:
	var best_i: int = 0
	var best_d: float = INF
	for i in pool.size():
		var p: Color = pool[i][1]
		var d: float = (p.r - c.r) * (p.r - c.r) + (p.g - c.g) * (p.g - c.g) + (p.b - c.b) * (p.b - c.b)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


# --- widget builders ---------------------------------------------------------

func _nav_button(text: String, delta: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(40, 0)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(_cycle.bind(delta))
	return b


func _tweak_row(label: String, cb: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l: Label = Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	l.add_theme_color_override("font_color", TEXT_DIM)
	row.add_child(l)
	var b: Button = Button.new()
	b.text = "Next ›"
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	row.add_child(b)
	return row


func _panel_stylebox() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	return sb


# --- autoload access ---------------------------------------------------------

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _autoload(autoload_name: String) -> Node:
	var tree: SceneTree = _tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)
