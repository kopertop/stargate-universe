class_name HudTheme
extends RefCounted

# Single source of truth for the WoW-style HUD skin (gold-on-dark).
# Every code-built HUD widget (unit frames, action bar, quest tracker, minimap
# frame, chat panel, discovery toast) reads its palette + styleboxes from here so
# the skin stays cohesive across the whole HUD. See docs/hud-redesign/HANDOFF.md §4.
#
# The previous skin used a cool-blue primary accent; this gold-primary palette
# matches the reference concept (docs/hud-redesign/wow-hud-reference.png). The
# hud_wow.gd cohesion smoke test mirrors these values as its contract — keep the
# two in sync when calibrating.

# --- Palette ----------------------------------------------------------------
const ACCENT_GOLD: Color = Color(0.83, 0.66, 0.32, 1.0)        # PRIMARY border / header
const ACCENT_GOLD_DIM: Color = Color(0.52, 0.42, 0.21, 1.0)    # inactive border
const ACCENT_GOLD_BRIGHT: Color = Color(1.0, 0.84, 0.42, 1.0)  # attention / quest title
const PANEL_BG: Color = Color(0.035, 0.035, 0.045, 0.82)       # near-black translucent fill
const BORDER_DARK: Color = Color(0.0, 0.0, 0.0, 0.9)           # outer hairline

const HEALTH_FILL: Color = Color(0.34, 0.74, 0.26, 0.97)       # WoW green
const HEALTH_CRIT: Color = Color(0.90, 0.25, 0.22, 0.98)
const OXYGEN_FILL: Color = Color(0.35, 0.72, 0.92, 0.97)       # SGU oxygen (cyan)

const TEXT_PRIMARY: Color = Color(0.96, 0.92, 0.80, 1.0)       # warm off-white
const TEXT_GOLD: Color = ACCENT_GOLD_BRIGHT
const TEXT_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.9)

const CORNER_RADIUS: int = 4
const BORDER_WIDTH: int = 2

# Role / class icon badge accent (Phase 1 — small icon over the portrait).
# Sci-fi engineer role placeholder for Eli; wired to a constant so a future
# role system can re-tint without touching every badge.
const ROLE_ICON_COLOR: Color = Color(1.0, 0.84, 0.42, 1.0)
const ROLE_ICON_BG: Color = Color(0.06, 0.05, 0.04, 0.92)

# Below this fraction of max HP the health bar turns red and pulses.
const HEALTH_CRITICAL_FRAC: float = 0.3


# Framed-panel stylebox: gold border + translucent dark fill + shared corner
# radius. `border` opts a widget into the bright gold (attention) or dim accent
# while keeping the same fill + corners, so every framed widget reads as one skin.
static func panel_stylebox(
		border: Color = ACCENT_GOLD,
		border_width: int = BORDER_WIDTH,
		bg: Color = PANEL_BG) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(CORNER_RADIUS)
	return sb


# Fill stylebox for a vitals/resource ProgressBar (no border, shared corner).
static func bar_fill_stylebox(fill: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(CORNER_RADIUS)
	return sb


# Apply the shared label treatment (color + black outline) so text reads over
# the bright 3D world. `color` defaults to the warm primary; pass TEXT_GOLD for
# headers / quest titles.
static func style_label(label: Label, font_size: int, color: Color = TEXT_PRIMARY, outline: int = 5) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", TEXT_OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
