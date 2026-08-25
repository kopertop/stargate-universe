extends Node

# Headless test for the in-game save + profile management UI (issue #81).
#
# Boots with real autoloads, isolates the saves root, then drives the REAL
# title.gd New Game handler and the REAL pause_menu.gd Save handler (no
# reimplementation) and asserts against SaveStore — the on-disk ground truth.
#
# Acceptance criteria exercised:
#   AC: New Game creates a NAMED profile and starts in it.
#   AC: Pause-menu Save writes a PERMANENT manual checkpoint + confirms.
#   AC: No accidental cross-profile writes (save lands ONLY in the active
#       profile; a sibling profile is untouched).
#
# (Profile delete from the Load browser is covered by load_browser_runner.gd.)

var _pass: int = 0
var _fail: int = 0
var _store: SaveStore = null
var _player: Node3D = null
var _title: Node = null
var _pause: Node = null

const TEST_ROOT: String = "user://__ingameuitest/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SceneRouter.instant_mode = true
	_store = SaveStore.new(TEST_ROOT)
	_wipe_test_root()
	_clear_active_pointer(TEST_ROOT)
	SaveManager.set_saves_root(TEST_ROOT)

	_install_fake_player()
	GameState.reset()
	GameState.current_scene_path = "res://scenes/room.tscn"
	GameState.current_room_id = "gate_room"
	GameState.current_objective = "Explore the Destiny"

	_test_new_game_named_profile()
	_test_pause_menu_save()
	_test_no_cross_profile_writes()

	_wipe_test_root()
	print("\ningame_ui: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ---- New Game naming -----------------------------------------------------

func _test_new_game_named_profile() -> void:
	_title = _instantiate_title()
	_check(_title != null, "instantiated title.tscn")
	if _title == null:
		return
	await get_tree().process_frame

	# Drive the real naming flow: open the New Game prompt, type a name,
	# confirm. The dialog's confirmed handler reads the LineEdit text.
	_title.call("_on_new_game_pressed")
	var edit: LineEdit = _title.get("_new_game_name_edit")
	_check(edit != null, "New Game prompt has a name field")
	if edit == null:
		return
	# A dated default is pre-filled so the player can accept or override it.
	_check(edit.text.strip_edges() != "", "New Game name field pre-fills a default (got '%s')" % edit.text)
	edit.text = "Test Run Alpha"
	_title.call("_on_new_game_confirmed")

	# New Game must create + activate a named profile (the player's chosen name),
	# NOT wipe a single global save. The deferred scene transition into gate_room
	# (how the player enters) is exercised by the playthrough suite; here we
	# assert the save-side contract: a fresh, named, active profile exists.
	var pid: String = SaveManager.active_profile_id()
	_check(pid != "" and _store.has_profile(pid), "New Game created + activated a profile (id='%s')" % pid)
	var meta: Dictionary = _store.read_profile(pid)
	_check(String(meta.get("display_name", "")) == "Test Run Alpha",
		"profile carries the player-entered name (got '%s')" % meta.get("display_name", ""))
	# An empty name falls back to a sensible default (never an empty profile name).
	_title.call("_on_new_game_pressed")
	var edit2: LineEdit = _title.get("_new_game_name_edit")
	edit2.text = ""
	_title.call("_on_new_game_confirmed")
	var pid2: String = SaveManager.active_profile_id()
	var meta2: Dictionary = _store.read_profile(pid2)
	_check(String(meta2.get("display_name", "")) != "",
		"empty name falls back to a non-empty default (got '%s')" % meta2.get("display_name", ""))
	_check(pid2 != pid, "a second New Game mints a DISTINCT profile (no wipe of the first)")
	_check(_store.has_profile(pid), "the first New Game profile still exists after a second New Game (AC: no destructive wipe)")
	# Free the title so its queued scene transitions can't perturb the active
	# profile under test below. We seed a clean active profile for the save test.
	if _title != null and is_instance_valid(_title):
		_title.queue_free()
		_title = null
		await get_tree().process_frame


# ---- Pause-menu Save -----------------------------------------------------

func _test_pause_menu_save() -> void:
	# Seed a clean, explicitly-active profile so the Save test is deterministic
	# (independent of whatever the New Game flow's deferred transition left set).
	var pid: String = SaveManager.create_profile("Pause Save Run")
	_arm_playable("gate_room", "Explore the Destiny")
	var before: int = _count_kind(pid, "manual")
	_pause = _instantiate_pause_menu()
	_check(_pause != null, "instantiated pause_menu autoload script")
	if _pause == null:
		return
	# Build the UI (deferred in _ready under the autoload; call directly here).
	_pause.call("_init_ui")

	_pause.call("_on_save_pressed")
	var after: int = _count_kind(pid, "manual")
	_check(after == before + 1, "pause-menu Save wrote one PERMANENT manual checkpoint (%d -> %d)" % [before, after])

	# The newest manual checkpoint is flagged permanent.
	var newest_manual: String = _newest_kind(pid, "manual")
	_check(newest_manual != "", "found the manual checkpoint just written")
	if newest_manual != "":
		var cpmeta: Dictionary = _store.read_checkpoint_meta(pid, newest_manual)
		_check(cpmeta.get("permanent", false) == true, "manual checkpoint is permanent")

	# Confirmation surfaced to the player (status label + log).
	var status: Label = _pause.get("_status")
	_check(status != null and status.text == "Game saved.",
		"Save confirms via status text (got '%s')" % (status.text if status != null else "<null>"))


# ---- No cross-profile writes ---------------------------------------------

func _test_no_cross_profile_writes() -> void:
	var active_pid: String = SaveManager.active_profile_id()
	# Seed a SIBLING profile with one manual checkpoint, NOT active.
	var other_pid: String = _store.create_profile("Bystander", "bystander")
	_write_manual(other_pid, "manual_seed", 1_700_000_000)
	var other_before: int = _store.list_checkpoints(other_pid).size()

	# Save into the ACTIVE profile via the pause menu again.
	_arm_playable("control_interface_room", "Talk to Rush")
	_pause.call("_on_save_pressed")

	var other_after: int = _store.list_checkpoints(other_pid).size()
	_check(other_after == other_before,
		"saving the active profile did NOT touch the sibling profile (%d -> %d)" % [other_before, other_after])
	_check(SaveManager.active_profile_id() == active_pid, "active profile unchanged by a save")


# ---- harness helpers -----------------------------------------------------

func _arm_playable(room: String, objective: String) -> void:
	GameState.current_scene_path = "res://scenes/room.tscn"
	GameState.current_room_id = room
	GameState.current_objective = objective


func _instantiate_title() -> Node:
	var packed: PackedScene = load("res://scenes/title.tscn") as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	get_tree().root.add_child(inst)
	return inst


# Builds a standalone PauseMenu node from the autoload script so we can drive
# its handlers without depending on the real autoload's deferred init timing.
func _instantiate_pause_menu() -> Node:
	var script: Script = load("res://scripts/pause_menu.gd") as Script
	if script == null:
		return null
	var inst: Node = Node.new()
	inst.name = "TestPauseMenu"
	inst.set_script(script)
	get_tree().root.add_child(inst)
	return inst


func _write_manual(pid: String, cid: String, ts: int) -> void:
	var snapshot: Dictionary = {
		"version": SaveStore.SAVE_VERSION,
		"timestamp": ts,
		"scene_path": "res://scenes/room.tscn",
		"player": {"pos": [1.0, 0.3, 2.0], "yaw": 0.0},
		"systems": {"game_state": {"current_room_id": "x", "current_objective": "y"}},
	}
	var meta: Dictionary = {
		"version": SaveStore.SAVE_VERSION,
		"timestamp": ts,
		"playtime_seconds": 1.0,
		"scene_path": "res://scenes/room.tscn",
		"room_id": "x",
		"objective": "y",
		"kind": "manual",
		"label": "seed",
		"episode": "",
		"slot_id": cid,
	}
	_store.write_checkpoint(pid, cid, snapshot, meta)


func _count_kind(profile_id: String, kind: String) -> int:
	var n: int = 0
	for cp in _store.list_checkpoints(profile_id):
		if String(cp.get("kind", "")) == kind:
			n += 1
	return n


func _newest_kind(profile_id: String, kind: String) -> String:
	for cp in _store.list_checkpoints(profile_id):  # newest-first
		if String(cp.get("kind", "")) == kind:
			return String(cp.get("checkpoint_id", ""))
	return ""


func _install_fake_player() -> void:
	_player = Node3D.new()
	_player.name = "FakePlayer"
	_player.add_to_group("player")
	_player.global_position = Vector3(1.0, 0.0, 2.0)
	get_tree().root.add_child(_player)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


func _wipe_test_root() -> void:
	_store.wipe_all()
	for prof in _store.list_profiles():
		_store.delete_profile(String(prof.get("id", "")))


func _clear_active_pointer(root: String) -> void:
	var path: String = root + "active.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
