class_name KinoPageQuest
extends Node

# Quest / Objectives page for the Kino Remote. Shows the current objective
# label and a hint pointing toward the quest target room.

var _coordinator: Node
var _page: Control

func setup(coordinator: Node) -> void:
	_coordinator = coordinator

func build(parent: Control) -> Control:
	_page = VBoxContainer.new()
	_page.name = "Quest"
	_page.anchor_right = 1.0
	_page.anchor_bottom = 1.0
	_page.add_theme_constant_override("separation", 8)
	parent.add_child(_page)
	_label(_page, "CURRENT", 16, Color(0.55, 0.85, 1.0, 1.0))
	var cur: Label = _label(_page, "  —", 14, Color.WHITE)
	cur.name = "CurrentObjective"
	_page.add_child(HSeparator.new())
	_label(_page, "NEXT STEP", 14, Color(0.55, 0.85, 1.0, 0.85))
	var hint: Label = _label(_page, "  —", 13, Color(0.8, 0.88, 1.0, 0.85))
	hint.name = "QuestHint"
	return _page

func refresh() -> void:
	var cur: Label = _page.get_node_or_null("CurrentObjective") as Label
	if cur != null:
		cur.text = "  [%s] %s" % [GameState.quest_step_label(), GameState.current_objective]
	var hint: Label = _page.get_node_or_null("QuestHint") as Label
	if hint != null:
		var target: Dictionary = GameState.quest_target()
		var room_id: String = String(target.get("room", ""))
		if room_id == "":
			hint.text = "  —"
		else:
			var room_data: Dictionary = ProceduralShip.room(room_id)
			var room_name: String = String(room_data.get("name", room_id))
			var anchor: String = String(target.get("anchor", ""))
			if anchor == "":
				hint.text = "  Head to %s." % room_name
			else:
				hint.text = "  In %s — interact with %s." % [room_name, anchor]

func is_available() -> bool:
	return true

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l