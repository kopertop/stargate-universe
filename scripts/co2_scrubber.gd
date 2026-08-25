class_name Co2Scrubber
extends Interactable

# Life-support CO2 scrubber. Two flavours, selected by `scrubber_id`:
#
#   • E1 story scrubber (scrubber_id == ""): the south-corridor unit. Dr Rush
#     reveals it (scrubber_rush.gd); before diagnosis interacting just points the
#     player at him; after the lime run interacting repairs it and completes E1.
#
#   • Optional maintenance scrubber (scrubber_id set, e.g. "north_corridor"): a
#     wall panel the player DISCOVERS, OPENS, and recharges with one lime at
#     leisure. State lives in GameState's scrubber_units registry (one collection,
#     not per-unit bools). First interact discovers + slides the panel OPEN; with
#     lime in hand a second interact recharges it and the panel auto-slides SHUT;
#     the player can also just open/close it any time.
#
# The access panel ("hatch") slides laterally on a tween. The three cartridge
# bars are a charge gauge: green = charged, red = depleted.

const FRAME_SIZE: Vector3 = Vector3(1.5, 1.7, 0.12)
const HATCH_SIZE: Vector3 = Vector3(1.36, 1.56, 0.08)
const PANEL_Y: float = 1.3
const HATCH_SLIDE: float = 1.4
const HATCH_SLIDE_TIME: float = 0.45
const BAR_GREEN: Color = Color(0.72, 0.92, 0.38)
const BAR_RED: Color = Color(1.0, 0.26, 0.16)

# Set by room.gd BEFORE add_child for an optional unit; "" = the E1 story unit.
var scrubber_id: String = ""

var _bars: Array[MeshInstance3D] = []
var _hatch: MeshInstance3D = null
var _hatch_open: bool = false
var _hatch_tween: Tween = null

func _is_aux() -> bool:
	return scrubber_id != ""

func _ready() -> void:
	super()
	collision_layer = 1 | 4
	_build_visual()
	_refresh_prompt()
	if _is_aux():
		if not GameState.scrubber_unit_changed.is_connected(_on_scrubber_unit_changed):
			GameState.scrubber_unit_changed.connect(_on_scrubber_unit_changed)
	else:
		if not GameState.scrubber_level_changed.is_connected(_on_scrubber_level_changed):
			GameState.scrubber_level_changed.connect(_on_scrubber_level_changed)

func _exit_tree() -> void:
	if GameState.scrubber_level_changed.is_connected(_on_scrubber_level_changed):
		GameState.scrubber_level_changed.disconnect(_on_scrubber_level_changed)
	if GameState.scrubber_unit_changed.is_connected(_on_scrubber_unit_changed):
		GameState.scrubber_unit_changed.disconnect(_on_scrubber_unit_changed)

# Whether the access panel is drawn open on (re)build. Aux units mirror the
# registry; the E1 unit is open while exposed/under-repair and shuts once fixed.
func _initial_hatch_open() -> bool:
	if _is_aux():
		return GameState.is_scrubber_unit_open(scrubber_id)
	if GameState.scrubber_repaired:
		return false
	return GameState.scrubber_diagnosed or (
		GameState.air_crisis_started and not GameState.breaches_sealed.is_empty())

# Green cartridge bars to show: aux = full when repaired, else empty; the E1 unit
# reads its live charge gauge.
func _green_bars() -> int:
	if _is_aux():
		return 3 if GameState.is_scrubber_unit_repaired(scrubber_id) else 0
	return GameState.scrubber_green_bars()

# A nameplate is shown once the unit is identified (aux: discovered; E1: diagnosed).
func _identified() -> bool:
	if _is_aux():
		return GameState.is_scrubber_unit_discovered(scrubber_id)
	return GameState.scrubber_diagnosed

func _build_visual() -> void:
	var cs: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.5, 1.8, 0.6)
	cs.shape = box
	cs.position = Vector3(0.0, PANEL_Y, 0.0)
	add_child(cs)

	# Recessed frame set into the wall (front face toward +Z, the room side).
	_box(Vector3(0.0, PANEL_Y, 0.0), FRAME_SIZE, _mat(Color(0.10, 0.11, 0.13), 0.6, 0.4))

	# Warning strip + three cartridge bars (the charge gauge).
	_box(Vector3(0.0, PANEL_Y + 0.62, 0.045), Vector3(1.1, 0.12, 0.04), _emis(Color(1.0, 0.40, 0.12), 2.6))
	var green_bars: int = _green_bars()
	var bar_x: Array[float] = [-0.42, 0.0, 0.42]
	for i in 3:
		var col: Color = BAR_GREEN if i < green_bars else BAR_RED
		_bars.append(_box(Vector3(bar_x[i], PANEL_Y - 0.1, 0.045),
			Vector3(0.24, 0.7, 0.04), _emis(col, 1.4)))

	# Sliding access hatch.
	_hatch_open = _initial_hatch_open()
	_hatch = MeshInstance3D.new()
	_hatch.name = "Hatch"
	var hm: BoxMesh = BoxMesh.new()
	hm.size = HATCH_SIZE
	_hatch.mesh = hm
	_hatch.material_override = _mat(Color(0.34, 0.36, 0.40), 0.7, 0.35)
	_hatch.position = Vector3(HATCH_SLIDE if _hatch_open else 0.0, PANEL_Y, 0.09)
	add_child(_hatch)

	if _identified():
		_add_label()

func _add_label() -> void:
	if get_node_or_null("Label") != null:
		return
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = "LIFE SUPPORT"
	label.pixel_size = 0.004
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 6
	label.shaded = false
	label.modulate = Color(0.75, 0.95, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(0.0, PANEL_Y + 1.05, 0.0)
	add_child(label)

# Slide the hatch open/shut. Tweened when in the live game; snapped in
# instant_mode (headless tests, captures) so nothing depends on timing.
func _set_hatch(want_open: bool, animate: bool = true) -> void:
	_hatch_open = want_open
	if _hatch == null:
		return
	var target_x: float = HATCH_SLIDE if want_open else 0.0
	var instant: bool = SceneRouter.instant_mode or not animate
	if instant:
		_hatch.position.x = target_x
		return
	if _hatch_tween != null and _hatch_tween.is_valid():
		_hatch_tween.kill()
	_hatch_tween = create_tween()
	_hatch_tween.set_trans(Tween.TRANS_SINE)
	_hatch_tween.set_ease(Tween.EASE_IN_OUT)
	_hatch_tween.tween_property(_hatch, "position:x", target_x, HATCH_SLIDE_TIME)

func _mat(col: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = roughness
	return m

func _emis(col: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _refresh_bars() -> void:
	var green: int = _green_bars()
	for i in _bars.size():
		var col: Color = BAR_GREEN if i < green else BAR_RED
		(_bars[i] as MeshInstance3D).material_override = _emis(col, 1.4)

func _on_scrubber_level_changed(_level: float) -> void:
	_refresh_bars()
	_refresh_prompt()

func _on_scrubber_unit_changed(id: String) -> void:
	if id != scrubber_id:
		return
	_refresh_bars()
	if _identified():
		_add_label()
	_refresh_prompt()

func _on_interact(_by: Node) -> void:
	if _is_aux():
		_interact_aux()
	else:
		_interact_e1()
	_refresh_prompt()

# --- optional maintenance unit ------------------------------------------------

func _interact_aux() -> void:
	var id: String = scrubber_id
	if not GameState.is_scrubber_unit_discovered(id):
		# First sighting: identify it and pop the panel open.
		GameState.discover_scrubber_unit(id, _aux_name())
		_add_label()
		_set_hatch(true)
		return
	if not GameState.is_scrubber_unit_repaired(id):
		if GameState.resource_count(GameState.AIR_LIME_RESOURCE) >= GameState.SCRUBBER_REPAIR_LIME_COST:
			if GameState.repair_scrubber_unit(id):
				_refresh_bars()
				_set_hatch(false)   # cartridge seated → panel slides shut
			return
		# No lime: let the player open/close the panel at will.
		var now_open: bool = not GameState.is_scrubber_unit_open(id)
		GameState.set_scrubber_unit_open(id, now_open)
		_set_hatch(now_open)
		if now_open:
			GameState.add_log("This scrubber is dead — it needs one lime to recharge.")
		return
	# Repaired: the panel is just an inspect-toggle now.
	var toggled: bool = not GameState.is_scrubber_unit_open(id)
	GameState.set_scrubber_unit_open(id, toggled)
	_set_hatch(toggled)

func _aux_name() -> String:
	for row in GameState.AUX_SCRUBBERS:
		if String((row as Dictionary).get("id", "")) == scrubber_id:
			return String((row as Dictionary).get("name", "CO2 Scrubber"))
	return "CO2 Scrubber"

# --- E1 story unit ------------------------------------------------------------

func _interact_e1() -> void:
	if GameState.scrubber_repaired:
		# Post-repair maintenance: top up if charge dropped (panel pops open for
		# it); otherwise toggle the panel open/closed to inspect.
		if GameState.scrubber_level < 100.0 and GameState.resource_count(GameState.AIR_LIME_RESOURCE) > 0:
			GameState.top_up_scrubber()
			_set_hatch(true)
		else:
			_set_hatch(not _hatch_open)
		return
	if not GameState.scrubber_diagnosed:
		# The reveal scene is Rush's — defer to him rather than self-diagnosing.
		GameState.add_log("Dr Rush is working the open panel. Talk to him.")
		return
	if GameState.resource_count(GameState.AIR_LIME_RESOURCE) >= GameState.SCRUBBER_REPAIR_LIME_COST:
		if GameState.repair_scrubber_with_lime():
			_set_hatch(false)   # panel slides shut once the scrubber is repaired
	else:
		GameState.add_log("The scrubber needs lime. Current lime: %d." %
			GameState.resource_count(GameState.AIR_LIME_RESOURCE))
		GameState.advance_air_quest()

func _refresh_prompt() -> void:
	if _is_aux():
		_refresh_prompt_aux()
	else:
		_refresh_prompt_e1()

func _refresh_prompt_aux() -> void:
	var id: String = scrubber_id
	if not GameState.is_scrubber_unit_discovered(id):
		prompt = "Examine wall panel"
	elif GameState.is_scrubber_unit_repaired(id):
		prompt = "CO2 scrubber online (%s)" % ("close" if GameState.is_scrubber_unit_open(id) else "open")
	elif GameState.resource_count(GameState.AIR_LIME_RESOURCE) >= GameState.SCRUBBER_REPAIR_LIME_COST:
		prompt = "Recharge scrubber (1 lime)"
	else:
		prompt = "%s scrubber panel — needs lime" % ("Close" if GameState.is_scrubber_unit_open(id) else "Open")

func _refresh_prompt_e1() -> void:
	if GameState.scrubber_repaired:
		if GameState.scrubber_level < 100.0 and GameState.resource_count(GameState.AIR_LIME_RESOURCE) > 0:
			prompt = "Top up scrubber (%d%%)" % int(round(GameState.scrubber_level))
		else:
			prompt = "CO2 scrubber stable"
	elif not GameState.scrubber_diagnosed:
		prompt = "Examine the open panel"
	elif GameState.resource_count(GameState.AIR_LIME_RESOURCE) >= GameState.SCRUBBER_REPAIR_LIME_COST:
		prompt = "Repair CO2 scrubber"
	else:
		prompt = "CO2 scrubber needs lime"
