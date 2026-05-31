class_name AtmoReadout
extends RefCounted

# @no-save: pure render helper — holds no state, nothing to persist.
#
# Single source of truth for rendering an atmosphere readout into a VBox. Both
# the Kino recon HUD (kino_drone.gd, planet telemetry) and the always-on
# ship-side readout (hud.gd, GameState.room_atmosphere) call render() so the
# row layout + colour coding live in ONE place. Extracted from kino_drone.gd's
# inline _render_atmo / _atmo_row / _level_color so the two consumers can't
# drift apart.

const ACCENT: Color = Color(0.55, 0.85, 1.0, 1.0)
const GOOD: Color = Color(0.6, 1.0, 0.6, 1.0)
const WARN: Color = Color(1.0, 0.7, 0.3, 1.0)
const BAD: Color = Color(1.0, 0.45, 0.4, 1.0)


# Clear `vbox` and render the atmosphere dictionary into it as a header plus a
# row per reading. An empty dict renders a placeholder "awaiting telemetry"
# line (the Kino's in-ship pre-launch state).
static func render(vbox: VBoxContainer, atmo: Dictionary) -> void:
	if vbox == null:
		return
	for c in vbox.get_children():
		c.queue_free()
	_row(vbox, "ATMOSPHERIC SCAN", "", ACCENT, 14)
	if atmo.is_empty():
		_row(vbox, "— awaiting telemetry —", "", Color(0.7, 0.8, 0.9, 0.8), 12)
		return
	# Optional one-line status banner (ship readout uses it: NOMINAL / VENTING /
	# DEGRADED). The planet telemetry omits it, so it only renders when present.
	if atmo.has("status"):
		_row(vbox, "Status", String(atmo.get("status", "")),
			status_color(String(atmo.get("status", ""))), 13)
	_row(vbox, "Atmosphere", String(atmo.get("composition", "BREATHABLE")),
		breathable_color(atmo.get("breathable", true) == true), 13)
	var temp_c: int = int(atmo.get("temperature_c", 47))
	var temp_note: String = String(atmo.get("temperature_note", "HOT"))
	_row(vbox, "Temperature", "%d°C  %s" % [temp_c, temp_note],
		WARN if temp_note != "" else GOOD, 13)
	_row(vbox, "Radiation", String(atmo.get("radiation", "LOW")),
		level_color(String(atmo.get("radiation", "LOW"))), 13)
	_row(vbox, "Toxins", String(atmo.get("toxins", "NONE")),
		level_color(String(atmo.get("toxins", "NONE"))), 13)


static func _row(vbox: VBoxContainer, label: String, value: String, color: Color, size: int) -> void:
	var l: Label = Label.new()
	l.text = label if value == "" else ("%s:  %s" % [label, value])
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.08, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	vbox.add_child(l)


static func breathable_color(good: bool) -> Color:
	return GOOD if good else BAD


# Green for LOW/NONE/SAFE/TRACE/NEGLIGIBLE, amber otherwise — so radiation /
# toxin readouts read at a glance whether a space is safe.
static func level_color(level: String) -> Color:
	var safe: bool = level.to_upper() in ["LOW", "NONE", "SAFE", "TRACE", "NEGLIGIBLE"]
	return GOOD if safe else WARN


# Green for a NOMINAL section, amber for DEGRADED (CO2 climbing), red for a
# VENTING breach.
static func status_color(status: String) -> Color:
	match status.to_upper():
		"VENTING": return BAD
		"DEGRADED": return WARN
		_: return GOOD
