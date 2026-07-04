extends SceneTree

# Swatch calibration — automated garment-region mapping for a mini-char model.
#
# For every atlas cell the model's UVs touch, this renders the model with that
# single cell painted magenta, diffs the frame against a base render, and
# prints WHERE on the body the change landed (pixel count, centroid height,
# horizontal spread). Heights are normalized 0=feet, 1=head-top, so:
#   > 0.80 hair/cap   0.55-0.80 face/head   0.35-0.60 torso/arms
#   0.12-0.40 legs    < 0.15 feet
# Ground truth for CharacterFactory.SWATCH_GROUPS. Run NON-headless:
#   CHAR_MODEL=young CELLS="9:8,9:11" godot --quit-after 2000 \
#     -s res://tests/capture/swatch_calibrate.gd
#
# Front AND back views are diffed together (a garment seen only from behind
# still registers). A contact sheet of the front view per cell is saved to
# user://swatch_<model>.png for spot checks.

const FactoryRef: Script = preload("res://scripts/character_factory.gd")
const MAGENTA: Color = Color(1.0, 0.0, 0.85)

var _holder: Node3D = null
var _cam: Camera3D = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stem: String = OS.get_environment("CHAR_MODEL")
	if stem == "":
		stem = "young"
	var cells: Array[Vector2i] = _parse_cells(OS.get_environment("CELLS"))
	root.size = Vector2i(480, 640)

	var world: Node3D = Node3D.new()
	root.add_child(world)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.34, 0.38)
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 1.3
	env.environment = e
	world.add_child(env)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, -0.6, 0.0)
	world.add_child(sun)

	_holder = Node3D.new()
	_holder.scale = Vector3(2.6, 2.6, 2.6)
	world.add_child(_holder)
	var glb: PackedScene = load("res://models/characters/%s.glb" % stem)
	if glb == null:
		print("[calibrate] no model for stem '%s'" % stem)
		quit(1)
		return
	var inst: Node = glb.instantiate()
	_holder.add_child(inst)
	# Some GLBs autoplay their idle on instantiate (eli does); any sway between
	# baseline and cell shots reads as a whole-character diff. Freeze them.
	_stop_anims(inst)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	world.add_child(_cam)
	_cam.current = true

	var base_img: Image = (load(FactoryRef.COLORMAP_PATH) as Texture2D).get_image()
	if base_img.is_compressed():
		base_img.decompress()
	base_img.convert(Image.FORMAT_RGBA8)

	var base_front: Image = null
	var base_back: Image = null
	FactoryRef.apply_texture(_holder, ImageTexture.create_from_image(base_img))
	# Window resize is async — WAIT until it lands (frame count varies by OS
	# latency) or every later diff compares against a distorted frame.
	# The window resize is async and root.size lies on retina displays — the
	# only trustworthy signal is the RAW captured frame size. Poisoned
	# baselines here made every cell diff as "whole character" (eli bug).
	var tries: int = 0
	while tries < 240:
		await process_frame
		await RenderingServer.frame_post_draw
		if root.get_viewport().get_texture().get_image().get_size() == Vector2i(480, 640):
			break
		tries += 1
	# Cold starts can also present frames before the material finishes
	# uploading — require two consecutive identical frames.
	for attempt in range(10):
		var a: Image = await _shoot(false)
		base_front = await _shoot(false)
		if int(_diff_stats(a, base_front, a, base_front)["count"]) == 0:
			break
	base_back = await _shoot(true)

	print("[calibrate] model=%s cells=%d  (h: 0=feet 1=head)" % [stem, cells.size()])
	var sheet: Image = Image.create(160 * mini(cells.size() + 1, 8),
		213 * int(ceil((cells.size() + 1) / 8.0)), false, Image.FORMAT_RGBA8)
	sheet.blit_rect(base_front, Rect2i(Vector2i.ZERO, base_front.get_size()), Vector2i.ZERO)
	var sheet_cols: int = mini(cells.size() + 1, 8)
	for i in range(cells.size()):
		var cell: Vector2i = cells[i]
		var img: Image = base_img.duplicate()
		for y in range(cell.y * 32, cell.y * 32 + 32):
			for x in range(cell.x * 32, cell.x * 32 + 32):
				img.set_pixel(x, y, MAGENTA)
		FactoryRef.apply_texture(_holder, ImageTexture.create_from_image(img))
		var front: Image = await _shoot(false)
		var back: Image = await _shoot(true)
		var stats: Dictionary = _diff_stats(base_front, front, base_back, back)
		print("  cell %2d:%-2d  px=%-6d h=%.2f  x-spread=%.2f  %s" % [
			cell.x, cell.y, stats["count"], stats["h"], stats["spread"], _hint(stats)])
		var slot: int = i + 1
		sheet.blit_rect(front, Rect2i(Vector2i.ZERO, front.get_size()),
			Vector2i((slot % sheet_cols) * front.get_width(), (slot / sheet_cols) * front.get_height()))
	var out: String = "user://swatch_%s.png" % stem
	sheet.save_png(out)
	print("[calibrate] contact sheet abs=%s" % ProjectSettings.globalize_path(out))
	quit()


func _shoot(from_back: bool) -> Image:
	var z: float = -3.6 if from_back else 3.6
	_cam.position = Vector3(0.0, 1.05, z)
	_cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.resize(160, 213, Image.INTERPOLATE_NEAREST)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _diff_stats(bf: Image, f: Image, bb: Image, b: Image) -> Dictionary:
	var count: int = 0
	var sum_y: float = 0.0
	var min_x: int = 9999
	var max_x: int = -1
	var min_y: int = 9999
	var max_y: int = -1
	for pair in [[bf, f], [bb, b]]:
		var base: Image = pair[0]
		var cur: Image = pair[1]
		for y in range(cur.get_height()):
			for x in range(cur.get_width()):
				var d: Color = cur.get_pixel(x, y) - base.get_pixel(x, y)
				if absf(d.r) + absf(d.g) + absf(d.b) > 0.25:
					count += 1
					sum_y += y
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
	if count == 0:
		return {"count": 0, "h": -1.0, "spread": 0.0}
	# Model occupies roughly rows 30..200 of the 213-row frame; normalize so
	# 1.0 = head top, 0.0 = feet.
	var mean_y: float = sum_y / float(count)
	var h: float = clampf(1.0 - (mean_y - 30.0) / 170.0, 0.0, 1.0)
	var spread: float = float(max_x - min_x) / 160.0
	return {"count": count, "h": h, "spread": spread}


func _hint(stats: Dictionary) -> String:
	if int(stats["count"]) == 0:
		return "(not visible)"
	var h: float = float(stats["h"])
	if h > 0.82:
		return "hair/cap"
	if h > 0.58:
		return "face/head"
	if h > 0.34:
		return "torso/arms"
	if h > 0.14:
		return "legs"
	return "feet"


func _stop_anims(node: Node) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			(n as AnimationPlayer).stop()
		for c in n.get_children():
			stack.append(c)


func _parse_cells(raw: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for part in raw.split(",", false):
		var xy: PackedStringArray = part.split(":")
		if xy.size() == 2:
			cells.append(Vector2i(int(xy[0]), int(xy[1])))
	return cells
