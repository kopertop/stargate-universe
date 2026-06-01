extends Node

# Headless test for the title-screen two-level Load Game browser (issue #80).
#
# Boots with real autoloads, isolates the saves root, seeds ONE profile with a
# full checkpoint set (episode + manual + 3 autosaves + quicksave), then
# instantiates title.tscn and drives its populate paths directly, asserting:
#
#   1. Profile level lists the seeded profile (and only profiles WITH a save).
#   2. Selecting a profile drills into its checkpoints.
#   3. Permanent (episode + manual) rows are visually separated from rolling
#      (autosave + quicksave) via section headers, permanent first.
#   4. All 3 autosaves are individually listed (the ring, not one slot).
#   5. Selecting a checkpoint resumes via load_and_resume_checkpoint.
#   6. Back walks checkpoint -> profile -> (overlay hidden).
#   7. The overlay uses CACHED node refs (no string-path lookups) — exercised
#      implicitly: if the cached Rows ref were broken, every populate would
#      produce zero rows and these assertions would fail.
#
# Asserts against the live title.gd's _load_rows children so we test the real
# UI build path, not a reimplementation.

var _pass: int = 0
var _fail: int = 0
var _store: SaveStore = null
var _title: Node = null

const TEST_ROOT: String = "user://__loadbrowsertest/"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SceneRouter.instant_mode = true
	_store = SaveStore.new(TEST_ROOT)
	_wipe_test_root()
	_clear_active_pointer(TEST_ROOT)

	var pid: String = _seed_profile()
	SaveManager.set_saves_root(TEST_ROOT)
	SaveManager.set_active_profile(pid)

	_title = _instantiate_title()
	if _title == null:
		print("\nload_browser: could not instantiate title.tscn")
		get_tree().quit(2)
		return
	# Let title.gd._ready() run.
	await get_tree().process_frame

	_test_profile_level(pid)
	_test_checkpoint_level(pid)
	_test_sections_and_ring()
	_test_resume(pid)
	_test_back_navigation()

	_wipe_test_root()
	print("\nload_browser: %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ---- seeding ------------------------------------------------------------

# Seeds a "Default" profile with: 1 episode, 1 manual, 3 autosaves, 1 quicksave.
# Timestamps are spaced so newest-first ordering is deterministic.
func _seed_profile() -> String:
	var pid: String = _store.create_profile("Default", "default")
	var base: int = 1_700_000_000
	# 3 autosaves (rolling) — distinct unix-stamped ids.
	for i in range(3):
		var ts: int = base + i
		var cid: String = "autosave_%d" % ts
		_write_cp(pid, cid, "autosave", "Autosave", "", "room_%d" % i, "Explore room %d" % i, ts)
	# quicksave (rolling)
	_write_cp(pid, "quicksave", "quicksave", "Quicksave", "", "kino_room", "Pilot the Kino", base + 5)
	# manual (permanent) — seeded WITH an episode, matching what _build_meta now
	# writes for every checkpoint. A blank episode here would let the missing
	# meta-wiring regression (issue #80 AC1) slip past unnoticed.
	_write_cp(pid, "manual_%d" % (base + 10), "manual", "Before the leak", "air", "control_interface_room", "Talk to Rush", base + 10)
	# episode (permanent)
	_write_cp(pid, "episode_air", "episode", "Episode 1: Air — Complete", "1", "breached_section_south", "Survive", base + 8)
	return pid


func _write_cp(pid: String, cid: String, kind: String, label: String, episode: String, room: String, objective: String, ts: int) -> void:
	var snapshot: Dictionary = {
		"version": SaveStore.SAVE_VERSION,
		"timestamp": ts,
		"scene_path": "res://scenes/room.tscn",
		"player": {"pos": [1.0, 0.3, 2.0], "yaw": 0.0},
		"systems": {"game_state": {"current_room_id": room, "current_objective": objective}},
	}
	var meta: Dictionary = {
		"version": SaveStore.SAVE_VERSION,
		"timestamp": ts,
		"playtime_seconds": 134.0,
		"scene_path": "res://scenes/room.tscn",
		"room_id": room,
		"objective": objective,
		"kind": kind,
		"label": label,
		"episode": episode,
		"slot_id": cid,
	}
	_store.write_checkpoint(pid, cid, snapshot, meta)


func _instantiate_title() -> Node:
	var packed: PackedScene = load("res://scenes/title.tscn") as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	get_tree().root.add_child(inst)
	return inst


# ---- level 1: profiles --------------------------------------------------

func _test_profile_level(pid: String) -> void:
	_title.call("_show_profile_level")
	var rows: VBoxContainer = _title.get("_load_rows")
	var btns: Array = _button_rows(rows)
	_check(btns.size() == 1, "profile level lists exactly 1 playable profile (got %d)" % btns.size())
	if btns.size() >= 1:
		var label: String = (btns[0] as Button).text
		_check(label.contains("Default"), "profile row shows display name (got '%s')" % label)
		# Newest checkpoint is the manual (base+10) — its objective surfaces on
		# the profile row so the player can tell playthroughs apart.
		_check(label.contains("Talk to Rush"), "profile row shows newest checkpoint objective (got '%s')" % label)
		# AC1: the row must show the EPISODE, sourced from the newest checkpoint's
		# meta.episode. This is the structural assertion that catches the missing
		# _build_meta wiring (issue #80) — with episode="air" seeded, the label
		# must render "Episode air", never the "—" placeholder.
		_check(label.contains("Episode air"),
			"profile row shows newest checkpoint episode (AC1) (got '%s')" % label)


# ---- level 2: checkpoints -----------------------------------------------

func _test_checkpoint_level(pid: String) -> void:
	_title.call("_on_profile_chosen", pid)
	var level: int = int(_title.get("_load_level"))
	_check(level == 1, "selecting a profile drilled into checkpoint level (LoadLevel.CHECKPOINT=1)")
	var rows: VBoxContainer = _title.get("_load_rows")
	var btns: Array = _button_rows(rows)
	# 3 autosaves + 1 quicksave + 1 manual + 1 episode = 6 loadable rows.
	_check(btns.size() == 6, "checkpoint level lists all 6 checkpoints (got %d)" % btns.size())


func _test_sections_and_ring() -> void:
	var rows: VBoxContainer = _title.get("_load_rows")
	# Walk children IN ORDER: expect a "CHECKPOINTS" header, then the permanent
	# rows, then a "RECENT" header, then the rolling rows.
	var children: Array = rows.get_children()
	var checkpoints_idx: int = -1
	var recent_idx: int = -1
	for i in range(children.size()):
		var c: Node = children[i]
		if c is Label:
			var t: String = (c as Label).text
			if t == "CHECKPOINTS":
				checkpoints_idx = i
			elif t == "RECENT":
				recent_idx = i
	_check(checkpoints_idx >= 0, "permanent section header 'CHECKPOINTS' present")
	_check(recent_idx >= 0, "rolling section header 'RECENT' present")
	_check(checkpoints_idx >= 0 and recent_idx > checkpoints_idx,
		"permanent section appears BEFORE the rolling section")

	# Between the two headers: episode + manual = 2 permanent button rows.
	var permanent_btns: int = 0
	var rolling_btns: int = 0
	var autosave_btns: int = 0
	for i in range(children.size()):
		var c: Node = children[i]
		if not (c is Button):
			continue
		if recent_idx >= 0 and i > recent_idx:
			rolling_btns += 1
			if (c as Button).text.begins_with("Autosave"):
				autosave_btns += 1
		elif checkpoints_idx >= 0 and i > checkpoints_idx:
			permanent_btns += 1
	_check(permanent_btns == 2, "permanent section holds episode + manual (got %d)" % permanent_btns)
	# The episode checkpoint's human label surfaces verbatim on its row.
	var has_episode_label: bool = false
	for c in children:
		if c is Button and (c as Button).text.begins_with("Episode 1: Air"):
			has_episode_label = true
	_check(has_episode_label, "episode checkpoint row shows its human label")
	_check(rolling_btns == 4, "rolling section holds 3 autosaves + quicksave (got %d)" % rolling_btns)
	_check(autosave_btns == 3, "all 3 autosaves individually listed in rolling section (got %d)" % autosave_btns)


# ---- resume -------------------------------------------------------------

func _test_resume(pid: String) -> void:
	# Re-show checkpoints (the resume test mutates state), then choose the
	# manual checkpoint and assert it resumes to the right room.
	_title.call("_on_profile_chosen", pid)
	GameState.reset()
	# Resume the manual checkpoint directly through the chosen-handler path.
	var manual_cid: String = ""
	for cp in _store.list_checkpoints(pid):
		if String(cp.get("kind", "")) == "manual":
			manual_cid = String(cp.get("checkpoint_id", ""))
			break
	_check(manual_cid != "", "found a manual checkpoint id to resume")
	_title.call("_on_checkpoint_chosen", manual_cid)
	# load_and_resume_checkpoint stages a spawn + triggers a scene change.
	var staged: Variant = GameState.pending_spawn_position
	_check(staged is Vector3, "checkpoint resume staged a player spawn position")
	# Wait for the deferred scene change to settle.
	var attempts: int = 0
	while attempts < 240:
		await get_tree().process_frame
		attempts += 1
	_check(GameState.current_room_id == "control_interface_room",
		"resumed the manual checkpoint's room (got '%s')" % GameState.current_room_id)
	var overlay: Control = _title.get("_load_overlay")
	_check(not overlay.visible, "overlay hidden after a checkpoint is chosen")


# ---- back navigation ----------------------------------------------------

func _test_back_navigation() -> void:
	# From the checkpoint level, Back returns to the profile level (not closed).
	_title.call("_on_load_pressed")  # opens at profile level
	_title.call("_on_profile_chosen", "default")
	_check(int(_title.get("_load_level")) == 1, "drilled to checkpoint level for back test")
	_title.call("_on_load_back_pressed")
	_check(int(_title.get("_load_level")) == 0, "Back from checkpoint level returns to profile level")
	var overlay: Control = _title.get("_load_overlay")
	_check(overlay.visible, "overlay still visible at profile level after one Back")
	# A second Back from the profile level closes the overlay.
	_title.call("_on_load_back_pressed")
	_check(not overlay.visible, "Back from profile level closes the overlay")


# ---- helpers ------------------------------------------------------------

func _button_rows(rows: VBoxContainer) -> Array:
	var out: Array = []
	if rows == null:
		return out
	for child in rows.get_children():
		if child is Button:
			out.append(child)
	return out


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % msg)
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


# Full clean: flat slots + every profile dir (wipe_all only touches flat slots,
# so leftover profile dirs from a prior run would inflate the listing).
func _wipe_test_root() -> void:
	_store.wipe_all()
	for prof in _store.list_profiles():
		_store.delete_profile(String(prof.get("id", "")))


func _clear_active_pointer(root: String) -> void:
	var path: String = root + "active.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
