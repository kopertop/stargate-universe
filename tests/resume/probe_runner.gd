extends Node

# Resume-path probe. Boots with real autoloads (scene-launched, not -s),
# writes a known DEEP save to a test path, resets GameState, calls
# SaveManager.load_and_resume(), then reports the resulting quest_step,
# current_room_id, and loaded scene. Lives at /root so it survives the
# scene change load_and_resume triggers (same pattern as the playthrough).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SceneRouter.instant_mode = true
	SaveManager.configure_test_paths("resume_probe")

	# A deep save: mid-Air-crisis, in the far-south breached section, quest
	# at find_scrubber. Mirrors the real save.json the user reported.
	var snapshot: Dictionary = {
		"version": 2,
		"scene_path": "res://scenes/room.tscn",
		"player": {"pos": [-7.7, 0.0, 0.96], "yaw": 0.0},
		"systems": {
			"game_clock": {"elapsed_seconds": 120.0},
			"npc_state": {"npcs": {}},
			"game_state": {
				"quest_step": "find_scrubber",
				"current_room_id": "breached_section_south",
				"objective": "Find the CO2 scrubber.",
				"met_scott": true, "met_rush": true,
				"eli_quarters_visited": true, "kino_acquired": true,
				"air_crisis_started": true, "control_room_returned": true,
				"life_support_diagnosed": true, "scrubber_diagnosed": false,
				"door_panel_examined": true, "small_fuse_found": true,
				"large_fuse_found": true, "breaches_sealed": ["breach_a"],
				"rooms_discovered": [
					"gate_room", "stargate_corridor_east_connector", "east_corridor",
					"north_corridor", "control_approach_north", "control_interface_room",
					"cr_corridor_2", "eli_quarters", "control_approach_south",
					"south_corridor", "south_spur", "breached_section_south",
				],
				"resources": {"lime": 0},
			},
		},
	}
	var store: SaveStore = SaveStore.new(SaveManager._store.saves_root)
	var meta: Dictionary = store.build_meta_from_snapshot("autosave", snapshot)
	store.write_snapshot("autosave", snapshot, meta)
	print("[probe] wrote save to ", store.primary_path("autosave"))
	print("[probe] has_save() = ", SaveManager.has_save())

	# Wipe in-memory state the way New Game would, so we know the resume —
	# not residual state — is what populates GameState.
	GameState.reset()
	print("[probe] after reset: quest_step=", GameState.quest_step)

	var ok: bool = SaveManager.load_and_resume()
	print("[probe] load_and_resume() returned: ", ok)
	print("[probe] post-deserialize (pre-scene): quest_step=", GameState.quest_step,
		" current_room_id=", GameState.current_room_id,
		" next_room_id=", GameState.next_room_id)

	# Let the scene transition settle.
	var attempts: int = 0
	while attempts < 240:
		await get_tree().process_frame
		attempts += 1

	var scene_path: String = "(null)"
	if get_tree().current_scene != null:
		scene_path = get_tree().current_scene.scene_file_path
	print("[probe] FINAL: quest_step=", GameState.quest_step,
		" current_room_id=", GameState.current_room_id,
		" scene=", scene_path)

	# A correct resume restores the exact mid-game beat — never the opening
	# step. "Started over" = load failed or we rewound to talk_scott / no room.
	var resumed_ok: bool = (ok
		and GameState.quest_step == "find_scrubber"
		and GameState.current_room_id == "breached_section_south")
	print("[probe] RESULT: ", "RESUMED OK" if resumed_ok else "STARTED OVER (bug)")
	SaveManager.wipe()
	get_tree().quit(0 if resumed_ok else 1)
