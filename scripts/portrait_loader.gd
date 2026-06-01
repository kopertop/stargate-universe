class_name PortraitLoader
extends RefCounted

# Shared character-portrait loader. Reads a PNG as raw bytes and wraps it in an
# ImageTexture, sidestepping Godot's .import pipeline so new portraits can be
# dropped into sprites/portraits/ without re-opening the editor (and so headless
# runs can load them at all). Used by BOTH the windowed dialog screen
# (dialog_screen.gd) and the HUD unit frame (hud.gd) so the import-sidestep is
# implemented ONCE.
#
# Two registries are cached statically and shared across all callers:
#   • _characters  — display name → { portrait, role, short_name } from
#     data/characters.json.
#   • _textures     — res:// path → decoded ImageTexture, so a PNG is decoded once.

const CHARACTERS_PATH: String = "res://data/characters.json"

static var _characters: Dictionary = {}
static var _textures: Dictionary = {}


# Resolve a speaker/character display name to its portrait Texture2D as declared
# in data/characters.json. Returns null for an unknown name or a missing/invalid
# PNG so the frame stays blank rather than showing a wrong or broken face.
static func portrait_for(display_name: String) -> Texture2D:
	if _characters.is_empty():
		_load_characters()
	var entry: Variant = _characters.get(display_name, null)
	if not (entry is Dictionary):
		return null
	var path: String = String((entry as Dictionary).get("portrait", ""))
	return texture_at(path)


# Load (and cache) the ImageTexture at a res:// PNG path. Returns null on a
# missing or undecodable file. Exposed separately so callers that already hold a
# path (not a character name) can reuse the same decode + cache.
static func texture_at(path: String) -> Texture2D:
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = _decode(path)
	if tex != null:
		_textures[path] = tex
	return tex


static func _decode(path: String) -> Texture2D:
	# Imported-resource fast path: if the editor HAS imported the PNG, load()
	# returns the GPU-uploaded .ctex which is ideal.
	if FileAccess.file_exists(path + ".import"):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	# Fallback: read PNG bytes and decode in-process. Works for fresh PNGs the
	# editor hasn't imported yet, and for headless runs.
	if not FileAccess.file_exists(path):
		push_warning("portrait_loader: file not found: %s" % path)
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("portrait_loader: empty file: %s" % path)
		return null
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK:
		push_warning("portrait_loader: failed to decode PNG %s (err %d)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)


static func _load_characters() -> void:
	var file: FileAccess = FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	if file == null:
		push_warning("portrait_loader: could not open %s" % CHARACTERS_PATH)
		return
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		_characters = parsed
