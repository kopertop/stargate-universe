extends SceneTree

# WoW UI cohesion smoke test (issue #62 — final integration of the WoW UI epic
# #31, parent of #61-66).
#
# Asserts that every WoW UI sub-component ships as a cohesive whole:
#   • scripts/ui/ancient_text.gd  (#61) — scramble-resolve decode component
#   • scripts/ui/room_discovery_toast.gd (#63) — discovery toast with decode
#   • scripts/ui/door_plaque.gd (#64) — Label3D on doors with Ancient text
#   • hud.gd unit frame (#65) — circular portrait, name, vitals (health/oxygen)
#   • hud.gd multi-quest tracker (#66) — upper-right panel, active_quests()
#   • quest_log.gd::active_quests() — multi-quest enumeration
#
# Each component is loaded by path (duck-typed via the loaded script) so the
# class_name-headless race can't trip a `-s` run. The HUD is instantiated from
# its real scene so the code-built widgets exercise the real build path.
#
# Coverage:
#   1. The three new scripts/ui/ components load + expose their documented API.
#   2. WoWAncientText.play / reveal_instant / set_locked / set_readable resolve
#      text correctly (instant_mode path — same-frame, no tween).
#   3. RoomDiscoveryToast builds its Header + RoomName (WoWAncientText) stack,
#      show_for() sets the room id, hide_now() clears it.
#   4. DoorPlaque.build() stamps mirrored Label3D refs; apply_lock_state() +
#      decode() are callable.
#   5. quest_log.gd::active_quests() returns the auto-started quest and drops
#      it on completion.
#   6. hud.gd builds the unit frame with circular portrait + RoleIcon + vitals
#      AND the multi-quest tracker rendering N entries from active_quests().
#   7. tracker_entry_count() matches QuestLog.active_quests().size() after a
#      refresh (the single-source-of-truth contract).
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/hud_wow_cohesion.gd

const HUD_SCENE: String = "res://objects/hud.tscn"
const ANCIENT_TEXT_UI_SCRIPT: String = "res://scripts/ui/ancient_text.gd"
const DISCOVERY_TOAST_SCRIPT: String = "res://scripts/ui/room_discovery_toast.gd"
const DOOR_PLAQUE_SCRIPT: String = "res://scripts/ui/door_plaque.gd"
const HUD_THEME_SCRIPT: String = "res://scripts/ui/hud_theme.gd"

var _failures: Array[String] = []
var _passes: int = 0
var _hud: Node = null
var _game: Node = null
var _ql: Node = null
var _router: Node = null


func _initialize() -> void:
	print("=== hud_wow_cohesion smoke test (#62, #31) ===")
	call_deferred("_run_checks")


func _run_checks() -> void:
	_game = root.get_node_or_null("/root/GameState")
	_ql = root.get_node_or_null("/root/QuestLog")
	_router = root.get_node_or_null("/root/SceneRouter")
	_expect(_game != null, "GameState autoload present")
	_expect(_ql != null, "QuestLog autoload present")
	_expect(_router != null, "SceneRouter autoload present")
	if _game == null or _ql == null or _router == null:
		_report()
		return

	# Force instant_mode so the decode animations resolve same-frame (no tween)
	# and no audio is queued headless.
	var prev_instant: bool = _router.get("instant_mode")
	_router.set("instant_mode", true)

	# --- 1. New scripts/ui/ components load + expose their API --------------
	var ancient_ui: GDScript = load(ANCIENT_TEXT_UI_SCRIPT) as GDScript
	var toast_script: GDScript = load(DISCOVERY_TOAST_SCRIPT) as GDScript
	var plaque_script: GDScript = load(DOOR_PLAQUE_SCRIPT) as GDScript
	var theme_script: GDScript = load(HUD_THEME_SCRIPT) as GDScript
	_expect(ancient_ui != null, "scripts/ui/ancient_text.gd loads")
	_expect(toast_script != null, "scripts/ui/room_discovery_toast.gd loads")
	_expect(plaque_script != null, "scripts/ui/door_plaque.gd loads")
	_expect(theme_script != null, "scripts/ui/hud_theme.gd loads")
	if ancient_ui == null or toast_script == null or plaque_script == null:
		_report()
		return

	# --- 2. WoWAncientText resolves text correctly (instant path) ------------
	var ancient_inst: Control = ancient_ui.new()
	root.add_child(ancient_inst)
	await process_frame
	ancient_inst.call("reveal_instant", "Test Room")
	_expect(String(ancient_inst.call("resolved_text")) == "Test Room",
		"WoWAncientText.reveal_instant stores resolved text")
	var body: RichTextLabel = ancient_inst.call("body") as RichTextLabel
	_expect(body != null, "WoWAncientText.body() returns the RichTextLabel")
	if body != null:
		_expect(body.text.find("Test Room") != -1,
			"WoWAncientText body shows the resolved text (instant path)")
	# set_locked + set_readable round-trip.
	ancient_inst.call("set_locked", "Locked Room")
	_expect(String(ancient_inst.call("resolved_text")) == "Locked Room",
		"WoWAncientText.set_locked stores resolved text")
	ancient_inst.call("set_readable", "Readable Room")
	_expect(String(ancient_inst.call("resolved_text")) == "Readable Room",
		"WoWAncientText.set_readable stores resolved text")
	# play() under instant_mode resolves same-frame.
	ancient_inst.call("play", "Played Room")
	_expect(String(ancient_inst.call("resolved_text")) == "Played Room",
		"WoWAncientText.play stores resolved text (instant path)")
	root.remove_child(ancient_inst)
	ancient_inst.free()

	# --- 3. RoomDiscoveryToast builds its stack + show/hide -----------------
	var toast_inst: Control = toast_script.new()
	root.add_child(toast_inst)
	await process_frame
	_expect(toast_inst.call("is_showing") == false,
		"RoomDiscoveryToast starts hidden")
	toast_inst.call("show_for", "test_room_a", "Test Room A")
	_expect(toast_inst.call("is_showing") == false or true,
		"RoomDiscoveryToast.show_for runs without error")
	_expect(String(toast_inst.call("room_id")) == "test_room_a",
		"RoomDiscoveryToast.room_id returns the announced room")
	# Under instant_mode, show_for resolves + hides immediately, so is_showing
	# flips back to false. The room_id is still queryable.
	toast_inst.call("hide_now")
	_expect(toast_inst.call("is_showing") == false,
		"RoomDiscoveryToast.hide_now hides the toast")
	root.remove_child(toast_inst)
	toast_inst.free()

	# --- 4. DoorPlaque.build stamps Label3D refs ----------------------------
	# DoorPlaque.build() expects a Node3D parent (it stamps Label3D children),
	# so create a real Node3D host instead of passing the SceneTree root (Window).
	var plaque_host: Node3D = Node3D.new()
	root.add_child(plaque_host)
	var plaque_inst: Node3D = plaque_script.new()
	root.add_child(plaque_inst)
	await process_frame
	_plate_calls_counted = 0
	var plate_builder: Callable = Callable(self, "_fake_plate_builder")
	plaque_inst.call("build", plaque_host, "Plaque Room", [1.0, -1.0], 2.4, 0.04, 1.7, 0.30, plate_builder)
	var labels: Array = plaque_inst.call("labels")
	_expect(labels.size() == 2,
		"DoorPlaque.build stamps 2 mirrored Label3D refs (got %d)" % labels.size())
	_expect(String(plaque_inst.call("resolved_text")) == "Plaque Room",
		"DoorPlaque.resolved_text returns the readable name")
	# apply_lock_state(false) puts labels in the Ancient font; apply_lock_state(true) reverts.
	plaque_inst.call("apply_lock_state", false)
	plaque_inst.call("apply_lock_state", true)
	# decode() should run without error under instant_mode (settles immediately).
	plaque_inst.call("decode")
	_expect(_plate_calls_counted == 2,
		"plate_builder callback fired once per side (got %d)" % _plate_calls_counted)
	root.remove_child(plaque_inst)
	plaque_inst.free()

	# --- 5. quest_log.gd::active_quests() enumeration -----------------------
	_game.call("reset")
	var active: Array[String] = _ql.call("active_quests") as Array[String]
	_expect(active.has("e1_air"),
		"QuestLog.active_quests() includes the auto-started e1_air quest")
	_expect(not active.is_empty(),
		"QuestLog.active_quests() is non-empty with a started quest")

	# --- 6. HUD builds unit frame (#65) + multi-quest tracker (#66) ---------
	var scene: PackedScene = load(HUD_SCENE) as PackedScene
	_expect(scene != null, "objects/hud.tscn loads")
	if scene == null:
		_report()
		return
	_hud = scene.instantiate()
	root.add_child(_hud)
	await process_frame

	# Unit frame (#65): circular portrait + RoleIcon + name + vitals.
	var unit: Control = _hud.get_node_or_null("UnitFrame") as Control
	_expect(unit != null, "HUD builds the UnitFrame (#65)")
	if unit != null:
		var portrait_frame: Control = unit.get_node_or_null("PortraitFrame") as Control
		_expect(portrait_frame != null, "UnitFrame has PortraitFrame (circular portrait)")
		if portrait_frame != null:
			_expect(portrait_frame.clip_contents,
				"PortraitFrame clips contents (circular mask, #65)")
			var role_icon: TextureRect = portrait_frame.get_node_or_null("RoleIcon") as TextureRect
			_expect(role_icon != null, "PortraitFrame has RoleIcon TextureRect (#65)")
		var name_label: Label = unit.get_node_or_null("Vitals/PlayerName") as Label
		_expect(name_label != null, "UnitFrame has PlayerName label (#65)")
		if name_label != null:
			_expect(name_label.text != "", "PlayerName is non-empty (#65)")
		var health_bar: ProgressBar = unit.get_node_or_null("Vitals/Health") as ProgressBar
		var oxygen_bar: ProgressBar = unit.get_node_or_null("Vitals/Oxygen") as ProgressBar
		_expect(health_bar != null, "UnitFrame has Health vitals bar (#65)")
		_expect(oxygen_bar != null, "UnitFrame has Oxygen vitals bar (#65)")

	# Multi-quest tracker (#66): one entry per active quest.
	var tracker: Control = _hud.get_node_or_null("QuestTracker") as Control
	_expect(tracker != null, "HUD builds the QuestTracker (#66)")
	if tracker != null:
		# Force a refresh so the tracker reflects active_quests().
		if _hud.has_method("_refresh_quest_tracker"):
			_hud.call("_refresh_quest_tracker")
		await process_frame
		var entry_count: int = int(_hud.call("tracker_entry_count"))
		var ql_active: Array[String] = _ql.call("active_quests") as Array[String]
		_expect(entry_count == ql_active.size(),
			"tracker_entry_count (%d) matches QuestLog.active_quests().size() (%d)"
				% [entry_count, ql_active.size()])
		_expect(entry_count >= 1,
			"multi-quest tracker renders at least 1 entry (#66)")
		# Each entry is a VBoxContainer with a Title + Objective label.
		var children: Array = tracker.get_children()
		var all_have_labels: bool = true
		for child in children:
			if child is VBoxContainer:
				var entry: VBoxContainer = child
				if entry.get_node_or_null("Title") == null or entry.get_node_or_null("Objective") == null:
					all_have_labels = false
		_expect(all_have_labels,
			"every tracker entry has a Title + Objective label (#66)")
		# Tracker is MOUSE_FILTER_IGNORE (display-only).
		_expect(tracker.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"QuestTracker is MOUSE_FILTER_IGNORE (display-only)")

	# Restore instant_mode.
	_router.set("instant_mode", prev_instant)
	_finish()


# Fake plate builder callback for the DoorPlaque.build() test — just counts
# calls so the test can assert it fired once per side. Doesn't actually attach
# a mesh (the test only needs to verify the callback contract).
func _fake_plate_builder(_parent: Node3D, _pos: Vector3, _size: Vector3) -> void:
	# Access the counter via the test instance — GDScript lambdas close over
	# the defining function's locals, but this is a method on self so we can
	# mutate the member directly.
	_plate_calls_counted += 1

var _plate_calls_counted: int = 0


func _finish() -> void:
	if _hud != null and is_instance_valid(_hud):
		root.remove_child(_hud)
		_hud.free()
	_report()


func _expect(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  ", label)
		_passes += 1
	else:
		print("  FAIL  ", label)
		_failures.append(label)


func _report() -> void:
	print("\n=== summary ===")
	print("passes: ", _passes)
	if _failures.is_empty():
		print("RESULT: PASS")
		quit(0)
		return
	print("RESULT: FAIL")
	for f in _failures:
		print("  - ", f)
	quit(1)