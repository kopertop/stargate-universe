extends Node

# @no-save: transient full-screen cinematic overlay (letterbox bars + flash).
# Holds no persistent gameplay state worth serializing.
#
# Reusable cutscene PRESENTATION, callable from ANY scene. Owns a top-most
# CanvasLayer with two black letterbox bars and a flash rect. Cutscene LOGIC
# (who walks where, dialogue, camera) lives in the scene/feature that runs the
# beat; this autoload only handles the cinematic framing so every cutscene in
# the game gets the same look from one place.
#
# Typical use from a scene script (all calls are awaitable):
#   await Cinematic.letterbox_in()
#   ... move actors, play dialogue ...
#   await Cinematic.flash(Color(0.6, 0.85, 1.0))
#   await Cinematic.letterbox_out()
#
# In instant_mode (headless tests) every call applies its end state and returns
# immediately, so tests never block on a tween.

const BAR_HEIGHT: float = 90.0
const LAYER: int = 60

var _layer: CanvasLayer = null
var _top: ColorRect = null
var _bottom: ColorRect = null
var _flash: ColorRect = null
var _caption: Label = null
var _bar_height: float = 0.0
var _active: bool = false
# Gameplay CanvasLayers (HUD, quest log, timer readout, dialog) hidden for the
# duration of a cutscene; restored by letterbox_out.
var _hidden_layers: Array[CanvasLayer] = []
# Armed by close_on_next_scene_change(): tells SceneRouter to lift the bars once
# the next scene change finishes — for cutscenes that end by transporting the
# player to another scene (the bars stay up through the cut).
var _close_on_scene_change: bool = false
# Cinematic camera state — the previously-current camera (restored by
# end_camera) and the temporary high-angle camera we spawn.
var _prev_camera: Camera3D = null
var _cine_camera: Camera3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_build")

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "CinematicLayer"
	_layer.layer = LAYER
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_layer)

	_top = ColorRect.new()
	_top.color = Color.BLACK
	_top.anchor_right = 1.0
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_top)

	_bottom = ColorRect.new()
	_bottom.color = Color.BLACK
	_bottom.anchor_top = 1.0
	_bottom.anchor_right = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_bottom)

	# Subtitle floats in the image JUST ABOVE the bottom bar, not inside it — a
	# caption parented to the (thin) bar gets pinned to the bar's top edge and
	# clipped to half-height. Anchoring to the bar's TOP edge (anchor_top/bottom
	# = 0) and lifting the box upward keeps it readable regardless of bar height.
	_caption = Label.new()
	_caption.anchor_left = 0.0
	_caption.anchor_right = 1.0
	_caption.anchor_top = 0.0
	_caption.anchor_bottom = 0.0
	_caption.offset_top = -74.0      # box sits 74px above the bar's top edge…
	_caption.offset_bottom = -10.0   # …down to 10px above it (64px tall band)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	_caption.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_caption.add_theme_constant_override("outline_size", 5)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.add_child(_caption)

	_flash = ColorRect.new()
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.anchor_right = 1.0
	_flash.anchor_bottom = 1.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_flash)

	_apply_bar_height(0.0)


# Subtitle/caption on the bottom letterbox bar. Pass "" to clear.
func set_caption(text: String) -> void:
	if _caption == null:
		_build()
	if _caption != null:
		_caption.text = text


# Slide the letterbox bars in. Await to know they've finished.
func letterbox_in(duration: float = 0.5) -> void:
	if _layer == null:
		_build()
	_active = true
	# Cinematic = no gameplay HUD. Hide health/quest/log/timer layers for the beat.
	_hide_gameplay_ui()
	if SceneRouter.instant_mode:
		_apply_bar_height(BAR_HEIGHT)
		return
	var t: Tween = create_tween()
	t.tween_method(_apply_bar_height, _bar_height, BAR_HEIGHT, duration)
	await t.finished


# Slide the letterbox bars out (end the cutscene framing).
func letterbox_out(duration: float = 0.4) -> void:
	if _layer == null:
		return
	if _caption != null:
		_caption.text = ""
	# Cutscene's over: gameplay HUD comes back and the auto-close arm is spent.
	_restore_gameplay_ui()
	_close_on_scene_change = false
	if SceneRouter.instant_mode:
		_apply_bar_height(0.0)
		_active = false
		return
	var t: Tween = create_tween()
	t.tween_method(_apply_bar_height, _bar_height, 0.0, duration)
	await t.finished
	_active = false


# Full-screen flash up to `color` and back to clear (e.g. a gate flare).
func flash(color: Color = Color.WHITE, duration: float = 0.45) -> void:
	if _flash == null:
		return
	if SceneRouter.instant_mode:
		return
	_flash.color = Color(color.r, color.g, color.b, 0.0)
	var t: Tween = create_tween()
	t.tween_property(_flash, "color:a", clampf(color.a if color.a < 1.0 else 0.9, 0.0, 1.0), duration * 0.45)
	t.tween_property(_flash, "color:a", 0.0, duration * 0.55)
	await t.finished


# Spawn a high, slightly-angled overhead camera looking down at `focus` and make
# it current — a generic "establishing / chase" cinematic shot. Defaults are
# tuned to see a large area (visible ground radius ~= height * tan(fov/2)).
# Returns the camera (or null in instant_mode / no scene). Pair with end_camera()
# unless a scene transition will free it.
func begin_camera(focus: Vector3, height: float = 75.0, back: float = 30.0, side: float = 10.0, fov: float = 60.0) -> Camera3D:
	if SceneRouter.instant_mode:
		return null
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	_prev_camera = get_viewport().get_camera_3d()
	_cine_camera = Camera3D.new()
	_cine_camera.name = "CinematicCamera"
	_cine_camera.fov = fov
	scene.add_child(_cine_camera)               # in tree before look_at
	_cine_camera.global_position = focus + Vector3(side, height, back)
	_cine_camera.look_at(focus, Vector3.UP)
	_cine_camera.current = true
	return _cine_camera


# Restore the camera that was current before begin_camera() and drop the
# cinematic one. Safe to call even if no cinematic camera is active.
func end_camera() -> void:
	if _cine_camera != null and is_instance_valid(_cine_camera):
		_cine_camera.queue_free()
	_cine_camera = null
	if _prev_camera != null and is_instance_valid(_prev_camera):
		_prev_camera.current = true
	_prev_camera = null


# Arm an automatic letterbox_out the next time SceneRouter finishes a scene
# change. Use when a cutscene ends by transporting the player to another scene
# (e.g. the planet-departure recall): the bars stay up THROUGH the cut and lift
# once the destination scene has faded in.
func close_on_next_scene_change() -> void:
	_close_on_scene_change = true


# SceneRouter polls this after a transition to know whether to lift the bars.
func wants_scene_change_close() -> bool:
	return _active and _close_on_scene_change


# Hide every gameplay CanvasLayer in the active scene (HUD, quest log, the
# departure-timer readout, dialog panels) so a cutscene reads clean. Remembers
# what it hid so letterbox_out can restore exactly that set. The Cinematic and
# SceneRouter overlays are parented to root (not current_scene), so they're
# never touched here.
func _hide_gameplay_ui() -> void:
	_restore_gameplay_ui()   # drop any stale handles before re-scanning
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	_hide_layers_under(scene)


func _hide_layers_under(node: Node) -> void:
	for c in node.get_children():
		if c is CanvasLayer and (c as CanvasLayer).visible:
			(c as CanvasLayer).visible = false
			_hidden_layers.append(c as CanvasLayer)
		_hide_layers_under(c)


func _restore_gameplay_ui() -> void:
	for cl in _hidden_layers:
		if is_instance_valid(cl):
			cl.visible = true
	_hidden_layers.clear()


func _apply_bar_height(h: float) -> void:
	_bar_height = h
	if _top != null:
		_top.offset_bottom = h
	if _bottom != null:
		_bottom.offset_top = -h
