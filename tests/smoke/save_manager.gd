extends SceneTree

# Smoke test for issue #83 — Save Profiles + Permanent Checkpoints.
#
# Run with:
#   godot --headless --quit-after 600 -s res://tests/smoke/save_manager.gd
#
# Asserts:
#   • save_to_slot writes a permanent checkpoint into slot_01..slot_04.
#   • load_from_slot(hydrate_only=true) restores every registered system
#     (game_state + quest_log + inventory) from the slot, round-tripping
#     character state, inventory, quest progress, discovered rooms, and log
#     entries.
#   • The four profile slots are INDEPENDENT: writing slot_02 doesn't disturb
#     slot_01; loading slot_01 doesn't pull slot_02's state.
#   • quick_save / quick_load target slot_01 and round-trip state.
#   • Checkpoint.trigger() writes to its configured slot and emits
#     checkpoint_reached(slot_id).
#
# Uses the live autoloads (GameState + QuestLog + Inventory + SaveManager),
# staged like profile_orchestration_runner.gd: a fake Node3D player in the
# "player" group + a non-empty current_scene_path / current_room_id so
# SaveManager._build_snapshot() captures a real snapshot.

var _passes: int = 0
var _failures: Array[String] = []
var _player: Node3D = null
var _store: SaveStore = null
const ROOT: String = "user://__smoke_save_manager/"