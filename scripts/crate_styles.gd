class_name CrateStyles
extends RefCounted

# Issue #37 — improved crate visual styles.
#
# ShuttleCrate (the lootable Ancient-tech crate in the Shuttle Dock) ships
# with ONE style: the Ancient-tech storage crate (dark navy/charcoal metallic,
# reinforced corner brackets, glowing cyan trim). This module is the style
# REGISTRY that future crates (and a refactor of ShuttleCrate) draw from so
# the four styles the issue names — military, supply, ancient, damaged —
# each get a distinct visual language:
#
#   • military — olive-drab steel, stenciled corner brackets, no glow.
#       Reads as a Marine supply crate from the Icarus base evac.
#   • supply  — yellow industrial, thick banding straps, black corner caps.
#       Reads as a generic ration / parts container.
#   • ancient — dark navy/charcoal metallic, glowing cyan trim, hinged lid.
#       The existing ShuttleCrate look, factored out so it can be reused.
#   • damaged — rust-streaked, cracked panels, missing corner brackets,
#       dark scorch. Reads as a crate that came through the gate hard.
#
# Each style is a Dictionary of material + geometry parameters that the crate
# builder consumes. Keeping the style data separate from the builder means a
# designer can tune a style here without touching the build code, and the
# smoke test can assert the registry is complete without instantiating a
# single mesh.

# ── Style ids ───────────────────────────────────────────────────────────────
const STYLE_MILITARY: String = "military"
const STYLE_SUPPLY: String = "supply"
const STYLE_ANCIENT: String = "ancient"
const STYLE_DAMAGED: String = "damaged"

# ── Style registry ───────────────────────────────────────────────────────────
# Each entry carries:
#   • body_color : Color — base albedo
#   • panel_color : Color — recessed face panel albedo (darker than body)
#   • bracket_color : Color — corner bracket albedo (usually darkest)
#   • interior_color : Color — dark interior floor
#   • accent_color : Color — glow / trim color (emissive)
#   • accent_energy : float — emissive energy multiplier (0 = no glow)
#   • metallic : float — base metallic for the body material
#   • roughness : float — base roughness for the body material
#   • has_glow : bool — whether to emit glowing trim (military/supply = false)
#   • lid_hinge : bool — whether the lid swings open (ancient = true)
#   • bracket_t : float — corner bracket thickness
#   • damaged : bool — whether to apply damage weathering (rust streaks,
#       scorch, missing brackets)
const STYLES: Dictionary = {
	STYLE_MILITARY: {
		"body_color": Color(0.22, 0.24, 0.14),       # olive drab
		"panel_color": Color(0.16, 0.18, 0.10),
		"bracket_color": Color(0.10, 0.11, 0.07),
		"interior_color": Color(0.06, 0.07, 0.04),
		"accent_color": Color(0.5, 0.55, 0.3),       # dull khaki (no glow)
		"accent_energy": 0.0,
		"metallic": 0.6,
		"roughness": 0.7,
		"has_glow": false,
		"lid_hinge": false,
		"bracket_t": 0.10,
		"damaged": false,
	},
	STYLE_SUPPLY: {
		"body_color": Color(0.78, 0.62, 0.12),       # industrial yellow
		"panel_color": Color(0.60, 0.48, 0.08),
		"bracket_color": Color(0.05, 0.05, 0.05),     # black corner caps
		"interior_color": Color(0.10, 0.08, 0.04),
		"accent_color": Color(0.05, 0.05, 0.05),
		"accent_energy": 0.0,
		"metallic": 0.3,
		"roughness": 0.6,
		"has_glow": false,
		"lid_hinge": false,
		"bracket_t": 0.09,
		"damaged": false,
	},
	STYLE_ANCIENT: {
		"body_color": Color(0.09, 0.12, 0.18),       # dark navy/charcoal
		"panel_color": Color(0.13, 0.18, 0.26),
		"bracket_color": Color(0.05, 0.07, 0.11),
		"interior_color": Color(0.04, 0.06, 0.09),
		"accent_color": Color(0.18, 0.78, 1.0),      # electric-cyan glow
		"accent_energy": 2.4,
		"metallic": 0.65,
		"roughness": 0.45,
		"has_glow": true,
		"lid_hinge": true,
		"bracket_t": 0.10,
		"damaged": false,
	},
	STYLE_DAMAGED: {
		# Damaged = the ancient style with rust streaks, scorch, and missing
		# brackets — reads as a crate that came through the gate hard.
		"body_color": Color(0.10, 0.08, 0.06),       # rust-tinted dark
		"panel_color": Color(0.12, 0.09, 0.07),
		"bracket_color": Color(0.04, 0.03, 0.02),     # scorched
		"interior_color": Color(0.03, 0.03, 0.02),
		"accent_color": Color(0.18, 0.78, 1.0),      # cyan, but dimmer
		"accent_energy": 0.8,                        # flickering / damaged glow
		"metallic": 0.5,                             # less metallic (oxidized)
		"roughness": 0.8,                             # rougher (weathered)
		"has_glow": true,
		"lid_hinge": true,                            # lid still present, may hang
		"bracket_t": 0.05,                            # thinner (some missing)
		"damaged": true,
	},
}

# ── Registry queries ─────────────────────────────────────────────────────────
# True when `style_id` is a registered crate style.
static func has_style(style_id: String) -> bool:
	return STYLES.has(style_id)

# The style Dictionary for `style_id`. Falls back to STYLE_ANCIENT (the
# canonical ShuttleCrate look) for unknown ids so a bad id degrades to the
# existing visual rather than a crash.
static func style_for(style_id: String) -> Dictionary:
	if STYLES.has(style_id):
		return (STYLES[style_id] as Dictionary).duplicate()
	return (STYLES[STYLE_ANCIENT] as Dictionary).duplicate()

# All registered style ids.
static func all_style_ids() -> Array[String]:
	var out: Array[String] = []
	for id in STYLES.keys():
		out.append(String(id))
	return out

# The default style (the canonical Ancient-tech crate look).
const DEFAULT_STYLE: String = STYLE_ANCIENT

static func default_style_id() -> String:
	return DEFAULT_STYLE

# ── Material builders ────────────────────────────────────────────────────────
# Build a StandardMaterial3D for the body of a crate in the given style.
# Static so a smoke test can verify the material parameters without a scene.
static func body_material(style_id: String) -> StandardMaterial3D:
	var s: Dictionary = style_for(style_id)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(s.get("body_color", Color(0.1, 0.1, 0.1)))
	m.metallic = float(s.get("metallic", 0.5))
	m.roughness = float(s.get("roughness", 0.5))
	return m

# Build the recessed-panel material (darker than the body).
static func panel_material(style_id: String) -> StandardMaterial3D:
	var s: Dictionary = style_for(style_id)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(s.get("panel_color", Color(0.08, 0.08, 0.08)))
	m.metallic = float(s.get("metallic", 0.5)) * 0.85
	m.roughness = float(s.get("roughness", 0.5)) * 1.1
	return m

# Build the corner-bracket material (darkest).
static func bracket_material(style_id: String) -> StandardMaterial3D:
	var s: Dictionary = style_for(style_id)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(s.get("bracket_color", Color(0.04, 0.04, 0.04)))
	m.metallic = float(s.get("metallic", 0.5)) * 0.7
	m.roughness = float(s.get("roughness", 0.5)) * 1.2
	return m

# Build the dark interior floor material.
static func interior_material(style_id: String) -> StandardMaterial3D:
	var s: Dictionary = style_for(style_id)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(s.get("interior_color", Color(0.03, 0.03, 0.03)))
	m.metallic = 0.2
	m.roughness = 0.7
	return m

# Build the accent (glow / trim) material. For non-glow styles (military,
# supply) this is a flat non-emissive material in the accent color; for glow
# styles (ancient, damaged) it is emissive.
static func accent_material(style_id: String) -> StandardMaterial3D:
	var s: Dictionary = style_for(style_id)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(s.get("accent_color", Color(0.5, 0.5, 0.5)))
	m.metallic = 0.0
	m.roughness = 0.4
	if bool(s.get("has_glow", false)):
		m.emission_enabled = true
		m.emission = Color(s.get("accent_color", Color(0.18, 0.78, 1.0)))
		m.emission_energy_multiplier = float(s.get("accent_energy", 0.0))
	return m

# ── Damage weathering ─────────────────────────────────────────────────────────
# True when the style applies damage weathering (rust streaks, scorch,
# missing brackets). Used by the crate builder to decide whether to skip some
# corner brackets and tint panels rust.
static func is_damaged(style_id: String) -> bool:
	return bool(style_for(style_id).get("damaged", false))

# ── Lid behavior ─────────────────────────────────────────────────────────────
# True when the style's lid swings open on a hinge (ancient, damaged). Military
# and supply crates use a removable top (no hinge animation).
static func has_hinged_lid(style_id: String) -> bool:
	return bool(style_for(style_id).get("lid_hinge", false))