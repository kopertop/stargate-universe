class_name KinoPageShipSystems
extends Node

# Console-only page: ship-level systems (power / O2 / hull) and a life-support
# diagnostics block. Distinct from the personal STATUS page (Eli's vitals) — a
# control terminal reads the ship, not the crewman holding it.

var _coordinator: Node
var _page: Control

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "ShipSystems"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 10)
	parent.add_child(_page)
	_label(_page, "SHIP SYSTEMS", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(_page, "  Main power:  —", 14, Color.WHITE).name = "SysPower"
	_label(_page, "  Atmosphere O2:  —", 14, Color.WHITE).name = "SysOxygen"
	_label(_page, "  Hull integrity:  —", 14, Color.WHITE).name = "SysHull"
	_page.add_child(HSeparator.new())
	_label(_page, "LIFE SUPPORT", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(_page, "  Exposed section:  —", 14, Color.WHITE).name = "SysBreach"
	_label(_page, "  CO2 scrubber:  —", 14, Color.WHITE).name = "SysScrubber"
	return _page

func refresh() -> void:
	var power: Label = _page.get_node_or_null("SysPower") as Label
	var oxygen: Label = _page.get_node_or_null("SysOxygen") as Label
	var hull: Label = _page.get_node_or_null("SysHull") as Label
	var breach: Label = _page.get_node_or_null("SysBreach") as Label
	var scrubber: Label = _page.get_node_or_null("SysScrubber") as Label
	if power != null:
		power.text = "  Main power:  %s" % _format_status("", GameState.power_percent).strip_edges()
	if oxygen != null:
		oxygen.text = "  Atmosphere O2:  %d%%" % int(GameState.oxygen)
	if hull != null:
		hull.text = "  Hull integrity:  %s" % _format_status("", GameState.hull_percent).strip_edges()
	if breach != null:
		if not GameState.air_crisis_started:
			breach.text = "  Exposed section:  nominal"
		elif GameState.breaches_sealed.is_empty():
			breach.text = "  Exposed section:  VENTING — seal required"
		else:
			breach.text = "  Exposed section:  sealed"
	if scrubber != null:
		if GameState.scrubber_repaired:
			# Phase G: include the live lime-charge percentage so the player can
			# see at a glance when a top-up run is due.
			var pct: int = int(round(GameState.scrubber_level))
			if pct <= 0:
				scrubber.text = "  CO2 scrubber:  EMPTY — lime needed"
			elif pct <= int(GameState.SCRUBBER_WARN_PERCENT):
				scrubber.text = "  CO2 scrubber:  low (%d%%)" % pct
			else:
				scrubber.text = "  CO2 scrubber:  online (%d%%)" % pct
		elif GameState.scrubber_diagnosed:
			scrubber.text = "  CO2 scrubber:  FAULT — lime required"
		elif GameState.air_crisis_started:
			scrubber.text = "  CO2 scrubber:  FAULT detected"
		else:
			scrubber.text = "  CO2 scrubber:  nominal"

func is_available() -> bool:
	return true

func _format_status(label: String, value: float) -> String:
	if value <= GameState.STATUS_OFFLINE + 0.001:
		return "%s  OFFLINE" % label
	return "%s  %d%%" % [label, int(value)]

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l