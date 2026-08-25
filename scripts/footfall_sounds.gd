class_name FootfallSounds
extends RefCounted

# Issue #33 — per-environment footstep sounds for the player.
#
# This is the player-facing companion to FootstepLibrary (which owns the
# canonical surface→sample registry). FootstepLibrary covers the ship + the
# five planet biomes (metal / dirt / desert / water / swamp). FootfallSounds
# EXTENDS that registry with the additional surfaces the issue calls out
# explicitly — metal deck, dirt, grass, stone, ship hull — and provides the
# player-facing helpers the locomotion controller (player.gd) consumes:
#
#   • resolve_surface(context) — pick the surface for a location/biome context
#   • stream_pool(surface_id) — a loaded, ready-to-play AudioStream pool
#   • gain_db(surface_id) — per-surface playback gain (soft ground = quieter)
#   • register_surface(id, paths, gain_db) — add a surface at runtime
#
# The new surfaces (grass, stone, ship_hull) supplement the existing set so
# the ship's hull plating reads differently from the interior deck, and so
# temperate/jungle planets can use a grass surface distinct from bare dirt.
# Existing surfaces (metal / dirt / desert / water / swamp) are inherited
# from FootstepLibrary so there is one canonical registry, not two.

const FootstepLibrary: Script = preload("res://scripts/footstep_library.gd")

# ── New surfaces (issue #33 explicit list) ───────────────────────────────────
# metal deck = FootstepLibrary.metal (ship interior). ship hull = a distinct
# exterior-hull surface (raw plating, no interior damping). grass + stone are
# the temperate/ruin surfaces the issue names that FootstepLibrary lacks.
const HULL_SURFACES: Dictionary = {
	"grass": [
		"res://sounds/footstep_grass_00.ogg", "res://sounds/footstep_grass_01.ogg",
		"res://sounds/footstep_grass_02.ogg", "res://sounds/footstep_grass_03.ogg",
	],
	"stone": [
		"res://sounds/footstep_stone_00.ogg", "res://sounds/footstep_stone_01.ogg",
		"res://sounds/footstep_stone_02.ogg", "res://sounds/footstep_stone_03.ogg",
	],
	"ship_hull": [
		"res://sounds/footstep_ship_hull_00.ogg", "res://sounds/footstep_ship_hull_01.ogg",
		"res://sounds/footstep_ship_hull_02.ogg", "res://sounds/footstep_ship_hull_03.ogg",
	],
}

const HULL_GAIN_DB: Dictionary = {
	"grass": -6.0,     # soft ground, quiet
	"stone": -3.0,     # hard but not ringing
	"ship_hull": +1.5, # raw plating — louder/ringier than the interior deck
}

# Runtime registry for surfaces added via register_surface (mirrors the
# FootstepLibrary.SURFACES shape so the lookup path is uniform).
var _extra_surfaces: Dictionary = {}
var _extra_gain_db: Dictionary = {}
# Loaded-stream cache so repeated stream_pool() calls don't re-load.
var _pool_cache: Dictionary = {}

func _init() -> void:
	# Seed the extra-surface registry with the issue's hull/grass/stone sets.
	for id in HULL_SURFACES.keys():
		_extra_surfaces[id] = HULL_SURFACES[id]
	for id in HULL_GAIN_DB.keys():
		_extra_gain_db[id] = HULL_GAIN_DB[id]

# ── Registry queries ─────────────────────────────────────────────────────────
# True when `surface_id` is registered (either in FootstepLibrary or here).
func has_surface(surface_id: String) -> bool:
	if FootstepLibrary.has_surface(surface_id):
		return true
	return _extra_surfaces.has(surface_id)

# Sample paths for a surface, falling back to the default (metal) surface when
# the id is unknown or empty.
func paths_for(surface_id: String) -> Array:
	if FootstepLibrary.SURFACES.has(surface_id):
		return (FootstepLibrary.SURFACES[surface_id] as Array).duplicate()
	if _extra_surfaces.has(surface_id):
		return (_extra_surfaces[surface_id] as Array).duplicate()
	return (FootstepLibrary.SURFACES[FootstepLibrary.DEFAULT_SURFACE] as Array).duplicate()

# Loaded AudioStreams for a surface. Skips any sample that fails to load so a
# missing file degrades to a shorter list rather than a crash. Cached.
func stream_pool(surface_id: String) -> Array:
	if _pool_cache.has(surface_id):
		return (_pool_cache[surface_id] as Array).duplicate()
	var out: Array = []
	for path in paths_for(surface_id):
		var s: AudioStream = load(path)
		if s != null:
			out.append(s)
	_pool_cache[surface_id] = out
	return out.duplicate()

# Per-surface playback gain (dB), ADDED to the player's base footstep volume.
# Metal (the ship) is the 0 dB reference; soft ground reads quieter; raw hull
# plating reads louder/ringier.
func gain_db(surface_id: String) -> float:
	if FootstepLibrary.SURFACE_GAIN_DB.has(surface_id):
		return float(FootstepLibrary.SURFACE_GAIN_DB[surface_id])
	if _extra_gain_db.has(surface_id):
		return float(_extra_gain_db[surface_id])
	return 0.0

# The default surface (ship interior) — used when a location has no biome.
const DEFAULT_SURFACE: String = "metal"

func default_surface() -> String:
	return DEFAULT_SURFACE

# ── Context → surface resolution ─────────────────────────────────────────────
# Resolve the surface for a location context. `context` is a Dictionary with
# optional keys:
#   • "location": "ship" | "planet" | "exterior_hull"
#   • "biome": a planet biome id (desert/temperate/jungle/toxic/urban/alien_tech)
#   • "footstep_surface": an explicit surface id (wins over biome)
# An empty / non-dict context means "on the ship" → metal.
func resolve_surface(context: Variant) -> String:
	if not (context is Dictionary) or (context as Dictionary).is_empty():
		return DEFAULT_SURFACE
	var d: Dictionary = context
	# Explicit surface wins.
	var explicit: String = String(d.get("footstep_surface", ""))
	if explicit != "" and has_surface(explicit):
		return explicit
	# Hull location → ship_hull (distinct from the interior metal deck).
	var loc: String = String(d.get("location", ""))
	if loc == "exterior_hull":
		return "ship_hull"
	if loc == "ship":
		return "metal"
	# Planet biome → surface. temperate/jungle prefer grass when grass is
	# registered (richer than bare dirt); other biomes fall back to
	# FootstepLibrary's biome map (desert/jungle/toxic/urban/alien_tech).
	var biome: String = String(d.get("biome", ""))
	if biome != "":
		if (biome == "temperate" or biome == "jungle") and has_surface("grass"):
			return "grass"
		var surf: String = String(FootstepLibrary.BIOME_SURFACE_FALLBACK.get(biome, ""))
		if surf != "" and has_surface(surf):
			return surf
	return DEFAULT_SURFACE

# ── Runtime registration ─────────────────────────────────────────────────────
# Add a surface at runtime (e.g. a mod planet with a custom biome). Idempotent.
func register_surface(surface_id: String, sample_paths: Array, gain_db: float = 0.0) -> void:
	if surface_id.is_empty():
		return
	_extra_surfaces[surface_id] = sample_paths.duplicate()
	_extra_gain_db[surface_id] = gain_db
	_pool_cache.erase(surface_id)  # invalidate any cached pool

# All registered surface ids (FootstepLibrary + extras).
func all_surface_ids() -> Array[String]:
	var out: Array[String] = []
	for id in FootstepLibrary.SURFACES.keys():
		out.append(String(id))
	for id in _extra_surfaces.keys():
		out.append(String(id))
	return out