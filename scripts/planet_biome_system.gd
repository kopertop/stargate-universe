class_name PlanetBiomeSystem
extends RefCounted

# Biome-parameterized generator + per-biome hazards + no-death recovery
# integration with injury_system.gd (issue #151).
#
# A pure helper layering OVER the existing biome data (data/biomes.json), the
# PlanetGenerator biome resolution (biome_params / traps_block / sensors_block),
# and the InjurySystem autoload (no-death knockout → med-bay recovery). It does
# NOT own the hazard zones or the injury registry — it returns render-ready +
# hazard-ready data so a planet scene / test can drive the existing systems.
#
# The existing systems already own:
#   * data/biomes.json                       — the 5 biome blocks (desert,
#                                              jungle, toxic, urban, alien_tech)
#                                              + temperate reference.
#   * PlanetGenerator.biome_params(biome)    — terrain/hazard/prop block.
#   * PlanetGenerator.traps_block / sensors_block — hazard sub-block resolution.
#   * InjurySystem.register_injury(...)      — the no-death recovery entry point
#                                              (cause-tagged, RECOVERABLE/FATAL).
# This system adds the BIOME-FACING surface:
#   * biome_ids() / biome_label()            — the supported biome catalog.
#   * hazards_for(biome)                      — normalized hazard descriptors per
#                                              biome (traps, flora, pressure-suit
#                                              gating, alarms) for the HUD/tests.
#   * hazard_kind()                          — one of NONE/TRAPS/TOXIN/SENSORS/
#                                              SETTLEMENT per biome.
#   * requires_pressure_suit()               — the per-biome gating flag.
#   * register_hazard_injury()               — routes a biome hazard knockout
#                                              through InjurySystem so the
#                                              no-death recovery loop fires with
#                                              the correct InjuryCause mapping.
#
# Headless-safe: data is read via PlanetGenerator (path-preloaded) and the
# InjurySystem autoload is reached via Engine.get_main_loop().root. Returns
# safe defaults when autoloads are absent.

const BIOMES_PATH: String = "res://data/biomes.json"
const GEN_PATH: String = "res://scripts/planet_generator.gd"
const INJURY_PATH: String = "res://scripts/injury_system.gd"

# Hazard kinds surfaced by hazard_kind(). NONE means no biome-specific hazard
# (desert's heat is a drain, not a trap/alarm — handled by the gate-window
# water-drain path, not this system's injury router).
enum HazardKind { NONE, TRAPS, TOXIN, SENSORS, SETTLEMENT }

# InjuryCause enum mirror (injury_system.gd owns the canonical enum; we can't
# reference it across class_name boundaries in a freshly-added script without
# tripping the cold-load class_name race, so we carry the int values here).
const _IC_FALL: int = 0
const _IC_IMPACT: int = 1
const _IC_SUFFOCATION: int = 2
const _IC_HOSTILE: int = 3
const _IC_DEPLOYMENT: int = 4

# Map of biome hazard `cause` strings (from data/biomes.json) → InjuryCause int.
# Used by register_hazard_injury() so a biome hazard routes through the
# InjurySystem with the correct cause tag (trap → IMPACT, alien_defense →
# HOSTILE, asphyxiation → SUFFOCATION).
const CAUSE_TO_INJURY: Dictionary = {
	"trap": _IC_IMPACT,
	"alien_defense": _IC_HOSTILE,
	"asphyxiation": _IC_SUFFOCATION,
	"fall": _IC_FALL,
	"window_closed": _IC_DEPLOYMENT,
}


# --- Biome catalog ----------------------------------------------------------

# The supported biome ids (the keys present in data/biomes.json), in file order.
# Static so tests can enumerate without an instance.
static func biome_ids() -> Array:
	var gen: Script = load(GEN_PATH)
	if gen == null:
		return _builtin_biome_ids()
	var table: Dictionary = gen.biome_table()
	if table.is_empty():
		return _builtin_biome_ids()
	return table.keys()


# The human label for a biome (from its block's `label` field).
static func biome_label(biome: String) -> String:
	var gen: Script = load(GEN_PATH)
	if gen == null:
		return biome.capitalize()
	var bp: Dictionary = gen.biome_params(biome)
	return String(bp.get("label", biome.capitalize()))


# Built-in fallback so biome_ids() never returns empty when biomes.json is
# missing (headless safety — matches the PlanetGenerator fallback philosophy).
static func _builtin_biome_ids() -> Array:
	return ["desert", "temperate", "jungle", "toxic", "urban", "alien_tech"]


# --- Per-biome hazards ------------------------------------------------------

# Normalized hazard descriptor for a biome. Returns a Dictionary with:
#   { kind: HazardKind, cause: String, requires_pressure_suit: bool,
#     telegraph: String, damage_per_second: float, count: int }
# A biome with no biome-specific hazard returns kind == NONE (defaults).
static func hazards_for(biome: String) -> Dictionary:
	var gen: Script = load(GEN_PATH)
	if gen == null:
		return {"kind": HazardKind.NONE}
	var bp: Dictionary = gen.biome_params(biome)
	var hz: Dictionary = bp.get("hazard", {}) if bp.get("hazard", {}) is Dictionary else {}
	var kind: HazardKind = hazard_kind(biome)
	var out: Dictionary = {
		"kind": kind,
		"requires_pressure_suit": requires_pressure_suit(biome),
	}
	match kind:
		HazardKind.TRAPS:
			var traps: Dictionary = gen.traps_block({"biome": biome, "hazard_params": {}})
			out["cause"] = String(traps.get("cause", "trap"))
			out["telegraph"] = String(traps.get("telegraph", "rustling vines"))
			out["damage_per_second"] = float(traps.get("damage_per_second", 0.0))
			out["count"] = int(traps.get("count", 0))
		HazardKind.SENSORS:
			var sensors: Dictionary = gen.sensors_block({"biome": biome, "hazard_params": {}})
			out["cause"] = String(sensors.get("cause", "alien_defense"))
			out["telegraph"] = String(sensors.get("telegraph", "humming light-beam"))
			out["damage_per_second"] = float(sensors.get("base_damage_per_second", 0.0))
			out["count"] = int(sensors.get("count", 0))
		HazardKind.TOXIN:
			out["cause"] = "asphyxiation"
			out["oxygen_drain_per_sec"] = float(hz.get("oxygen_drain_per_sec", 0.0))
			# Store the raw breathable flag (false for toxic). Callers branch on
			# this directly; do NOT invert it here.
			out["breathable"] = bool(hz.get("breathable", true))
		HazardKind.SETTLEMENT:
			out["cause"] = "negotiation"
			out["count"] = int(bp.get("settlement", {}).get("building_count", 0)) \
				if bp.get("settlement", {}) is Dictionary else 0
		_:
			out["cause"] = String(hz.get("type", "none"))
	return out


# The hazard kind a biome presents. Resolution order:
#   alien_tech → SENSORS (security alarms to avoid)
#   jungle     → TRAPS (damage flora)
#   toxic      → TOXIN (pressure-suit-gated oxygen drain)
#   urban      → SETTLEMENT (negotiation flavor — no damage)
#   else       → NONE (desert/temperate heat/drain handled elsewhere)
static func hazard_kind(biome: String) -> HazardKind:
	match biome:
		"alien_tech":
			return HazardKind.SENSORS
		"jungle":
			return HazardKind.TRAPS
		"toxic":
			return HazardKind.TOXIN
		"urban":
			return HazardKind.SETTLEMENT
		_:
			return HazardKind.NONE


# True when a biome requires the pressure_suits_found flag before it may be
# rolled (the Toxic gate). Surfaces PlanetGenerator.biome_required_flag() so the
# HUD / tests can ask without re-reading biomes.json.
static func requires_pressure_suit(biome: String) -> bool:
	var gen: Script = load(GEN_PATH)
	if gen == null:
		return biome == "toxic"
	return gen.biome_required_flag(biome) == "pressure_suits_found"


# --- No-death recovery integration ------------------------------------------

# Route a biome hazard knockout through the InjurySystem so the no-death
# recovery loop fires with the correct InjuryCause. Maps the biome's hazard
# `cause` string (from data/biomes.json) to the InjurySystem InjuryCause enum,
# then calls InjurySystem.register_injury(character_id, cause, severity).
#
# `severity` is clamped to [0, 1.0]; at or above FATAL_SEVERITY_THRESHOLD (0.85)
# the injury is FATAL — but biome hazards are RECOVERABLE by design (no death),
# so callers should pass a severity under the fatal threshold (the default
# 0.5 is well below). Returns the InjuryTag (0 = RECOVERABLE, 1 = FATAL) or -1
# when InjurySystem is absent.
#
# The InjurySystem delegates the actual downed beat to GameState.knock_out(...)
# itself (it owns that routing), so this method does NOT call knock_out — it
# only registers the injury record so the MedBay recovery loop is armed with
# the correct cause tag. This keeps the single no-death entry point intact.
static func register_hazard_injury(character_id: String, cause_str: String,
		severity: float = 0.5) -> int:
	var injury_sys: Node = _injury_system()
	if injury_sys == null:
		return -1
	var cause_int: int = int(CAUSE_TO_INJURY.get(cause_str, _IC_IMPACT))
	# register_injury returns an InjuryTag int (0 = RECOVERABLE, 1 = FATAL).
	return int(injury_sys.call("register_injury", character_id, cause_int,
		clampf(severity, 0.0, 1.0)))


# Whether a character has a recoverable injury registered (the MedBay can
# process it). False when InjurySystem is absent or the character has no
# injury record.
static func is_recoverable(character_id: String) -> bool:
	var injury_sys: Node = _injury_system()
	if injury_sys == null:
		return false
	return bool(injury_sys.call("is_recoverable", character_id))


# True when the character's recovery has completed (back on feet).
static func is_recovered(character_id: String) -> bool:
	var injury_sys: Node = _injury_system()
	if injury_sys == null:
		return false
	return bool(injury_sys.call("is_recovered", character_id))


# --- Helpers ----------------------------------------------------------------

static func _injury_system() -> Node:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null("InjurySystem")