extends Node

# Slot-aware resume integration test. Boots with real autoloads, isolates the
# saves root, writes a deep save to a NON-default slot (manual_2), edits its
# scene_path + quest_step the way the save editor does, then resumes that
# specific slot and asserts the resumed scene / quest_step / current_room_id
# match the edit. Proves the edit -> Continue loop end-to-end and that resume
# is slot-targeted (not just "most recent autosave"). Mirrors probe_runner.gd.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SceneRouter.instant_mode = true
	SaveManager.set_saves_root("user://__slotresumetest/")

	var store: SaveStore = SaveStore.new("user://__slotresumetest/")
	store.wipe_all()

	# A deep save in manual_2, mid-Air-crisis in the far-south breach.
	var snapshot: Dictionary = {
		"version": 2,
		"timestamp": 500,
		"scene_path": "res://scenes/room.tscn",
		"player": {"pos": [-7.7, 0.0, 0.96], "yaw": 0.0},
		"systems": {
			"game_clock": {"elapsed_seconds": 120.0},
			"npc_state": {"npcs": {}},
			"game_state": {
				"quest_step": "find_scrubber",
				"current_room_id": "breached_section_south",
				"objective": "Find the CO2 scrubber.",
				"met_scott": true, "met_rush": true, "kino_acquired": true,
				"eli_quarters_visited": true, "air_crisis_started": true,
				"control_room_returned": true, "life_support_diagnosed": true,
				"scrubber_diagnosed": false, "door_panel_examined": true,
				"small_fuse_found": true, "large_fuse_found": true,
				"breaches_sealed": ["breach_a"],
				"rooms_discovered": [
					"gate_room", "east_corridor", "north_corridor",
					"control_interface_room", "eli_quarters", "south_corridor",
					"breached_section_south",
				],
			},
		},
	}
	store.write_snapshot("manual_2", snapshot, store.build_meta_from_snapshot("manual_2", snapshot))

	# Edit the slot the way `save.sh set player.pos=...` does: mutate a field
	# via the SaveStore rewrite path and confirm it survives resume. player.pos
	# is never recomputed on load, so it's the clean proof the edit landed.
	var data: Dictionary = store.read_snapshot("manual_2")
	data["player"]["pos"] = [3.25, 0.0, -1.5]
	store.rewrite_snapshot("manual_2", data, store.build_meta_from_snapshot("manual_2", data))
	print("[slot_resume] edited manual_2 player.pos -> (3.25, 0, -1.5)")

	# Write a DIFFERENT, MORE-RECENT state to autosave: if resume were
	# slot-blind (most-recent), it would land in gate_room/talk_scott instead,
	# proving load_and_resume("manual_2") truly targets the requested slot.
	var other: Dictionary = snapshot.duplicate(true)
	other["timestamp"] = 9999
	other["systems"]["game_state"]["quest_step"] = "talk_scott"
	other["systems"]["game_state"]["current_room_id"] = "gate_room"
	store.write_snapshot("autosave", other, store.build_meta_from_snapshot("autosave", other))

	GameState.reset()

	var ok: bool = SaveManager.load_and_resume("manual_2")
	print("[slot_resume] load_and_resume('manual_2') returned: ", ok)
	# Capture the staged spawn BEFORE the room scene consumes/clears it.
	var staged_pos: Variant = GameState.pending_spawn_position
	var pos_ok: bool = staged_pos is Vector3 and absf((staged_pos as Vector3).x - 3.25) < 0.001

	var attempts: int = 0
	while attempts < 240:
		await get_tree().process_frame
		attempts += 1

	var scene_path: String = "(null)"
	if get_tree().current_scene != null:
		scene_path = get_tree().current_scene.scene_file_path
	print("[slot_resume] FINAL: quest_step=", GameState.quest_step,
		" current_room_id=", GameState.current_room_id, " scene=", scene_path,
		" staged_pos=", staged_pos)

	# Resume must land in manual_2's state (find_scrubber / breach), NOT
	# autosave's more-recent talk_scott/gate_room — proving slot targeting —
	# and the edited player.pos must have survived the rewrite.
	var resumed_ok: bool = (ok
		and GameState.quest_step == "find_scrubber"
		and GameState.current_room_id == "breached_section_south"
		and scene_path == "res://scenes/room.tscn"
		and pos_ok)
	print("[slot_resume] RESULT: ", "RESUMED OK" if resumed_ok else "WRONG SLOT / STATE (bug)")
	store.wipe_all()
	get_tree().quit(0 if resumed_ok else 1)
