extends SceneTree

# Smoke test for the character paper-doll / equip panel (#74).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/character_panel.gd
#
# Builds a CharacterPanel instance wired to the live Inventory autoload, drives
# the loadout through the panel's own click handlers (NOT Inventory directly),
# and asserts that:
#   - the paper-doll has one widget per equipment slot,
#   - clicking an inventory item equips it into its slot,
#   - the slot widget reflects the equipped item's icon (icon shown, glyph hidden),
#   - clicking a filled slot unequips it (icon hidden, glyph back),
#   - the panel stays in sync with Inventory.equipped_in via equipment_changed,
#   - the browse list only lists equippable, held items.
#
# Duck-types the panel via load() (a freshly-added class_name / autoload may
# parse-error in the same headless run; we go through the script + has_method).

const PANEL_SCRIPT_PATH: String = "res://scripts/character_panel.gd"


var _failures: Array[String] = []
var _passes: int = 0


func _initialize() -> void:
	print("=== character_panel smoke test ===")

	var inv: Node = root.get_node_or_null("Inventory")
	_expect(inv != null, "Inventory autoload attached")
	if inv == null:
		_report()
		return
	inv.call("reset")

	var PanelScript: Script = load(PANEL_SCRIPT_PATH)
	_expect(PanelScript != null, "character_panel.gd loads")
	if PanelScript == null:
		_report()
		return

	var panel: Node = PanelScript.new()
	panel.name = "CharacterPanelUnderTest"
	root.add_child(panel)
	# Headless: no frame has ticked so the deferred _init_ui has not run yet
	# (SceneTree-script gotcha). Build the UI synchronously for the test.
	panel.call("_init_ui")
	# Open the pane: in real play the click handlers only ever fire while it is
	# visible, and the signal-driven refresh path is active only when open. Drive
	# the test through that same realistic state.
	panel.call("open")

	# --- paper-doll has one widget per slot --------------------------------
	var slot_widgets: Dictionary = panel.get("_slot_widgets")
	_expect(slot_widgets.size() == 4, "paper-doll built four slot widgets")
	for slot in ["head", "torso", "back", "legs"]:
		_expect(slot_widgets.has(slot), "slot widget exists for '%s'" % slot)

	# Force a refresh so the (empty) loadout is reflected.
	panel.call("_refresh")
	_expect(_glyph_visible(panel, "head"), "empty head slot shows its glyph")
	_expect(not _icon_visible(panel, "head"), "empty head slot hides its icon")

	# --- browse list lists only equippable, held items ---------------------
	# Give the player a non-equipment item + two equippables.
	inv.call("add_item", "rations", 2, "test")
	inv.call("add_item", "marine_helmet", 1, "test")
	inv.call("add_item", "tac_vest", 1, "test")
	panel.call("_refresh")
	var listed: Array = _listed_item_labels(panel)
	_expect(_any_contains(listed, "Marine Helmet"), "browse list shows the held helmet")
	_expect(_any_contains(listed, "Tactical Vest"), "browse list shows the held vest")
	_expect(not _any_contains(listed, "Rations"), "browse list excludes non-equipment (rations)")

	# --- clicking an inventory item equips it into its slot ----------------
	panel.call("_on_item_pressed", "marine_helmet")
	_expect(String(inv.call("equipped_in", "head")) == "marine_helmet",
		"clicking the helmet equips it into the head slot")
	# Panel reflects the new icon via the equipment_changed signal.
	_expect(_icon_visible(panel, "head"), "head slot now shows the equipped icon")
	_expect(not _glyph_visible(panel, "head"), "head slot hides its empty glyph once filled")
	_expect(_slot_icon_texture(panel, "head") != null, "head slot icon has a texture")

	# Equipping the helmet (count 1, non-stackable) removes it from the browse
	# list (no longer held) but it is now in the slot.
	panel.call("_refresh")
	_expect(not _any_contains(_listed_item_labels(panel), "Marine Helmet"),
		"equipped helmet no longer appears as a held browse item")

	# --- a second slot is independent --------------------------------------
	panel.call("_on_item_pressed", "tac_vest")
	_expect(String(inv.call("equipped_in", "torso")) == "tac_vest",
		"clicking the vest equips it into the torso slot")
	_expect(_icon_visible(panel, "torso"), "torso slot shows the equipped icon")
	_expect(_icon_visible(panel, "head"), "head slot still shows its icon (independent)")

	# --- swap the head slot cleanly ----------------------------------------
	inv.call("add_item", "recon_cap", 1, "test")
	panel.call("_on_item_pressed", "recon_cap")
	_expect(String(inv.call("equipped_in", "head")) == "recon_cap",
		"equipping the cap swaps it into the occupied head slot")
	# The swapped-out helmet returns to the pool, so it reappears in the list.
	panel.call("_refresh")
	_expect(_any_contains(_listed_item_labels(panel), "Marine Helmet"),
		"swapped-out helmet returns to the browse list")

	# --- clicking a filled slot unequips it --------------------------------
	var left_click: InputEventMouseButton = InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	panel.call("_on_slot_input", left_click, "head")
	_expect(String(inv.call("equipped_in", "head")) == "",
		"clicking the filled head slot unequips it")
	_expect(_glyph_visible(panel, "head"), "head slot shows its glyph again after unequip")
	_expect(not _icon_visible(panel, "head"), "head slot hides its icon after unequip")

	# Clicking an already-empty slot is a harmless no-op.
	panel.call("_on_slot_input", left_click, "head")
	_expect(String(inv.call("equipped_in", "head")) == "", "clicking an empty slot is a no-op")

	# --- live sync: a direct Inventory.equip refreshes the open panel ------
	panel.call("open")  # mark _open so the signal-driven refresh fires
	inv.call("equip", "marine_helmet")
	_expect(_icon_visible(panel, "head"),
		"direct Inventory.equip refreshes the open panel via equipment_changed")
	panel.call("close")

	# --- open/close gating does not crash + restores pause -----------------
	_expect(panel.call("is_open") == false, "panel is closed after close()")
	_expect(paused == false, "tree is unpaused after close()")

	panel.free()
	_report()


# --- helpers -----------------------------------------------------------------

func _slot_widget(panel: Node, slot: String) -> Panel:
	var widgets: Dictionary = panel.get("_slot_widgets")
	var w: Variant = widgets.get(slot, null)
	if w is Panel:
		return w as Panel
	return null


func _icon_visible(panel: Node, slot: String) -> bool:
	var w: Panel = _slot_widget(panel, slot)
	if w == null:
		return false
	var icon: TextureRect = w.get_node_or_null("Icon")
	return icon != null and icon.visible


func _glyph_visible(panel: Node, slot: String) -> bool:
	var w: Panel = _slot_widget(panel, slot)
	if w == null:
		return false
	var glyph: Label = w.get_node_or_null("Glyph")
	return glyph != null and glyph.visible


func _slot_icon_texture(panel: Node, slot: String) -> Texture2D:
	var w: Panel = _slot_widget(panel, slot)
	if w == null:
		return null
	var icon: TextureRect = w.get_node_or_null("Icon")
	return icon.texture if icon != null else null


func _listed_item_labels(panel: Node) -> Array:
	var out: Array = []
	var list: Node = panel.get("_item_list")
	if list == null:
		return out
	for c in list.get_children():
		if c is Button:
			out.append((c as Button).text)
	return out


func _any_contains(labels: Array, needle: String) -> bool:
	for l in labels:
		if String(l).contains(needle):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: %d / %d" % [_passes, _passes + _failures.size()])
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
