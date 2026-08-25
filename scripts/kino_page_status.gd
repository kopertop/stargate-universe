class_name KinoPageStatus
extends Node

# Status / Vitals page for the Kino Remote. Shows Eli's personal vitals
# (health, oxygen, lime, quest step, planet scan) and a per-resource
# scarcity block (issue #134).

var _coordinator: Node
var _page: Control

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "Status"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 10)
	parent.add_child(_page)
	_label(_page, "VITALS", 16, Color(0.55, 0.85, 1.0, 1.0))
	_label(_page, "  Crew member: Eli Wallace", 14, Color.WHITE)
	_label(_page, "  Vessel: Destiny (Ancient)", 14, Color.WHITE)
	_label(_page, "  Status: stranded, ambulatory", 14, Color.WHITE)
	var q: Label = _label(_page, "  Quest: —", 14, Color.WHITE)
	q.name = "QuestStepLabel"
	_page.add_child(HSeparator.new())
	_label(_page, "READINGS", 16, Color(0.55, 0.85, 1.0, 1.0))
	var h: Label = _label(_page, "  Health: —", 14, Color.WHITE)
	h.name = "HealthLabel"
	var o: Label = _label(_page, "  Oxygen: —", 14, Color.WHITE)
	o.name = "OxygenLabel"
	var r: Label = _label(_page, "  Lime: —", 14, Color.WHITE)
	r.name = "LimeLabel"
	var scan: Label = _label(_page, "  Planet scan: —", 14, Color(0.82, 0.92, 1.0, 0.9))
	scan.name = "PlanetScanLabel"
	# Scarcity block (issue #134): one row per tracked resource, scarcest first.
	# Rows are built once and updated by refresh via node names "Scarcity_<id>"
	# so the list never names a resource in code.
	_page.add_child(HSeparator.new())
	_label(_page, "RESOURCES", 16, Color(0.55, 0.85, 1.0, 1.0))
	var gs: Node = _scarcity_autoload()
	var ids: Array = gs.call("tracked_resource_ids") if gs != null else []
	for id in ids:
		var row_label: Label = _label(_page, "  %s: —" % id.capitalize(), 14, Color.WHITE)
		row_label.name = "Scarcity_%s" % id
	return _page

func refresh() -> void:
	var h: Label = _page.get_node_or_null("HealthLabel") as Label
	var o: Label = _page.get_node_or_null("OxygenLabel") as Label
	var q: Label = _page.get_node_or_null("QuestStepLabel") as Label
	var r: Label = _page.get_node_or_null("LimeLabel") as Label
	var scan: Label = _page.get_node_or_null("PlanetScanLabel") as Label
	if q != null:
		q.text = "  Quest:  %s" % GameState.quest_step_label()
	if h != null:
		h.text = "  Health:  %d / 100" % int(GameState.health)
	if o != null:
		o.text = "  Oxygen:  %d / 100" % int(GameState.oxygen)
	if r != null:
		r.text = "  Lime:  %d / %d" % [
			GameState.resource_count(GameState.AIR_LIME_RESOURCE),
			GameState.AIR_LIME_REQUIRED,
		]
	if scan != null:
		if GameState.lime_planet_dialed:
			scan.text = "  Planet scan: air_lime_world — lime deposits confirmed"
		elif GameState.ftl_drop_triggered:
			scan.text = "  Planet scan: viable address pending gate dial"
		else:
			scan.text = "  Planet scan: no active offworld scan"
	# Scarcity rows (issue #134): iterate registry order from resource_scarcity()
	# so the scarcest resource floats to the top. Tag LOW when deficit > 0.
	var scarcity: Array = GameState.resource_scarcity()
	for row in scarcity:
		var id: String = String((row as Dictionary).get("id", ""))
		var node_name: String = "Scarcity_%s" % id
		var lbl: Label = _page.get_node_or_null(node_name) as Label
		if lbl == null:
			continue
		var amount: int = int((row as Dictionary).get("amount", 0))
		var threshold: int = int((row as Dictionary).get("threshold", 0))
		var deficit: int = int((row as Dictionary).get("deficit", 0))
		var label_text: String = String((row as Dictionary).get("label", id.capitalize()))
		if deficit > 0:
			lbl.text = "  %s: %d  [LOW]" % [label_text, amount]
			lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35, 1.0))
		else:
			lbl.text = "  %s: %d / %d" % [label_text, amount, threshold]
			lbl.add_theme_color_override("font_color", Color.WHITE)

func is_available() -> bool:
	return true

func _scarcity_autoload() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameState")

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l