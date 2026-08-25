class_name FootstepLibrary
extends RefCounted

# Per-environment footstep sound registry (issue #33).
#
# ONE collection keyed by a surface id → ONE list of footstep sample paths, plus
# ONE resolver (surface_for_spec) and ONE accessor (paths_for / load_streams).
# Adding a surface is a single SURFACES entry + one biome→surface line in
# data/biomes.json — no per-surface bool, no branch-per-surface consumer.
#
# Surfaces (issue #33): metal / dirt / desert / water / swamp.
#  - metal : ship interior + alien-tech decks — Kenney "ES Ship Footsteps" slices.
#  - dirt  : temperate / jungle / urban ground — Kenney "RPG Audio" footsteps.
#  - desert: sand dunes — granular crunch (generated, CC0).
#  - water : shallow water wade — wet splash (generated, CC0).
#  - swamp : toxic mud — thick squelch (generated, CC0).

const DEFAULT_SURFACE: String = "metal"

# surface id → footstep sample paths. The metal set is the legacy ship footstep
# slices; keep it the default so any scene without a biome (ship, menus) still
# sounds correct.
const SURFACES: Dictionary = {
	"metal": [
		"res://sounds/footstep_01.ogg", "res://sounds/footstep_02.ogg",
		"res://sounds/footstep_03.ogg", "res://sounds/footstep_04.ogg",
		"res://sounds/footstep_05.ogg", "res://sounds/footstep_06.ogg",
		"res://sounds/footstep_07.ogg", "res://sounds/footstep_08.ogg",
		"res://sounds/footstep_09.ogg", "res://sounds/footstep_10.ogg",
	],
	"dirt": [
		"res://sounds/footstep_dirt_00.ogg", "res://sounds/footstep_dirt_01.ogg",
		"res://sounds/footstep_dirt_02.ogg", "res://sounds/footstep_dirt_03.ogg",
		"res://sounds/footstep_dirt_04.ogg", "res://sounds/footstep_dirt_05.ogg",
		"res://sounds/footstep_dirt_06.ogg", "res://sounds/footstep_dirt_07.ogg",
		"res://sounds/footstep_dirt_08.ogg", "res://sounds/footstep_dirt_09.ogg",
	],
	"desert": [
		"res://sounds/footstep_desert_00.ogg", "res://sounds/footstep_desert_01.ogg",
		"res://sounds/footstep_desert_02.ogg", "res://sounds/footstep_desert_03.ogg",
	],
	"water": [
		"res://sounds/footstep_water_00.ogg", "res://sounds/footstep_water_01.ogg",
		"res://sounds/footstep_water_02.ogg", "res://sounds/footstep_water_03.ogg",
	],
	"swamp": [
		"res://sounds/footstep_swamp_00.ogg", "res://sounds/footstep_swamp_01.ogg",
		"res://sounds/footstep_swamp_02.ogg", "res://sounds/footstep_swamp_03.ogg",
	],
}

# Per-surface playback gain (dB), ADDED to the player's base footstep volume.
# Metal (the ship) is the 0 dB reference; soft ground reads quieter — desert sand
# is the softest. Tunable here without touching the trigger. Issue tweak: planets
# were "clanky and loud" because metal played everywhere; soft surfaces fix that.
const SURFACE_GAIN_DB: Dictionary = {
	"metal": 0.0,
	"dirt": -4.0,
	"desert": -8.0,
	"water": -5.0,
	"swamp": -5.0,
}


# Extra gain (dB) for a surface, relative to the player's base footstep volume.
# Unknown surfaces play at the base volume (0 dB offset).
static func gain_db_for(surface_id: String) -> float:
	return float(SURFACE_GAIN_DB.get(surface_id, 0.0))


# Fallback biome → surface map. The canonical source is each biome's
# "footstep_surface" key in data/biomes.json; this table only covers a spec that
# predates the key (old saves) or a bare biome string. Keep the ids in sync with
# the biomes.json entries.
const BIOME_SURFACE_FALLBACK: Dictionary = {
	"desert": "desert",
	"temperate": "dirt",
	"jungle": "dirt",
	"toxic": "swamp",
	"urban": "dirt",
	"alien_tech": "metal",
}


# True when surface_id has a registered sample list.
static func has_surface(surface_id: String) -> bool:
	return SURFACES.has(surface_id)


# Sample paths for a surface, falling back to the default (metal) surface when
# the id is unknown or empty.
static func paths_for(surface_id: String) -> Array:
	if SURFACES.has(surface_id):
		return (SURFACES[surface_id] as Array).duplicate()
	return (SURFACES[DEFAULT_SURFACE] as Array).duplicate()


# Loaded AudioStreams for a surface. Skips any sample that fails to load so a
# missing file degrades to a shorter list rather than a crash.
static func load_streams(surface_id: String) -> Array:
	var out: Array = []
	for path in paths_for(surface_id):
		var s: AudioStream = load(path)
		if s != null:
			out.append(s)
	return out


# Resolve the surface for a planet spec. Prefers the spec's explicit
# "footstep_surface" key, else maps the biome through BIOME_SURFACE_FALLBACK,
# else the default (metal — the ship). An empty / non-dict spec means "on the
# ship", so it returns the default.
static func surface_for_spec(spec: Variant) -> String:
	if spec is Dictionary and not (spec as Dictionary).is_empty():
		var d: Dictionary = spec
		var explicit: String = String(d.get("footstep_surface", ""))
		if explicit != "" and SURFACES.has(explicit):
			return explicit
		var biome: String = String(d.get("biome", ""))
		if BIOME_SURFACE_FALLBACK.has(biome):
			return String(BIOME_SURFACE_FALLBACK[biome])
	return DEFAULT_SURFACE
