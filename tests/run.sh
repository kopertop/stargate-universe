#!/usr/bin/env bash
# Smoke + flow + playthrough test runner for Stargate Universe (Godot 4.6).
# Validates the E1 vertical slice at multiple levels:
#   1. scene_boot   — every gameplay scene loads with critical nodes intact
#   2. e1_flow      — GameState mutators + win-condition logic
#   3. quest        — quest-tracker BFS + GameState.quest_target + Kino route
#   4. playthrough  — real cross-scene transitions via SceneRouter +
#                     Interactable.interact() pipelines, end-to-end
#   5. autopilot    — Kino-drone auto-search patrol (1/2/3 drone coordination)
#   6. questlog     — data-driven QuestLog autoload (predicate + event advance,
#                     save round-trip, old-format migration)
#
# Usage: tests/run.sh [lint|scene|flow|quest|playthrough|resume|autopilot|questlog|inventory|atmosphere|kino-doors|kino-autoexplore|gamepad|npc-chat|shaders|ancient-text|save|all]
#                                                                          (default: all)
#
# Pre-commit hook: .githooks/pre-commit invokes the lint subset via
# tests/lint/check_save_registration.sh --staged. Install once with:
#   git config core.hooksPath .githooks

set -u
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	# Fall back to PATH lookup.
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "ERROR: cannot find Godot. Set GODOT_BIN or add 'godot' to PATH." >&2
		exit 2
	fi
fi

MODE="${1:-all}"
RAN_SCENE=0
RAN_FLOW=0
RAN_QUEST=0
RAN_PLAY=0
RAN_LINT=0
RAN_RESUME=0
RAN_AUTOPILOT=0
RAN_QUESTLOG=0
RAN_INV=0
RAN_SAVE=0
RAN_ATMO=0
RAN_KINODOORS=0
RAN_KINOEXPLORE=0
RAN_KINODISC=0
RAN_GAMEPAD=0
RAN_NPCCHAT=0
RAN_SHADER=0
RAN_ANCIENTTEXT=0
RC_SCENE=0
RC_FLOW=0
RC_QUEST=0
RC_PLAY=0
RC_LINT=0
RC_FORKS=0
RC_INV=0
RC_RESUME=0
RC_AUTOPILOT=0
RC_QUESTLOG=0
RC_SAVE_UNIT=0
RC_SAVE_RESUME=0
RC_ATMO=0
RC_KINODOORS=0
RC_KINOEXPLORE=0
RC_KINODISC=0
RC_GAMEPAD=0
RC_NPCCHAT=0
RC_SHADER=0
RC_ANCIENTTEXT=0

# Run a SceneTree-extending script (synchronous, no autoloads).
#
# --quit-after is a frame-count ceiling, not a target. Scripts call quit(0|1)
# explicitly so a higher ceiling only matters when the test silently hangs.
# Per memory feedback_godot_quit_after_frames.md, truncated runs exit code 0
# and masquerade as PASS — keep generous so growing scene lists do not slip
# into that failure mode.
run_script_test() {
	local label="$1"
	local script="$2"
	echo
	echo "==============================="
	echo " $label"
	echo "==============================="
	"$GODOT_BIN" --headless --quit-after 600 -s "$script" 2>&1
	return $?
}

# Run a regular scene with autoloads active (used for the playthrough).
# The scene's script is responsible for calling get_tree().quit(0|1). The
# --quit-after value is a fail-safe ceiling; if it fires we lose visibility
# into PASS/FAIL so it must stay generous and the runner must self-time-out
# below it (see TIMEOUT_SEC in playthrough_runner.gd).
run_scene_test() {
	local label="$1"
	local scene="$2"
	echo
	echo "==============================="
	echo " $label"
	echo "==============================="
	"$GODOT_BIN" --headless --quit-after 100000 "$scene" 2>&1
	return $?
}

if [[ "$MODE" == "lint" || "$MODE" == "all" ]]; then
	echo
	echo "==============================="
	echo " save-registration lint"
	echo "==============================="
	tests/lint/check_save_registration.sh
	RC_LINT=$?
	echo
	echo "==============================="
	echo " collection-fork lint"
	echo "==============================="
	tests/lint/check_collection_forks.sh
	RC_FORKS=$?
	RAN_LINT=1
fi

if [[ "$MODE" == "scene" || "$MODE" == "all" ]]; then
	run_script_test "scene_boot" "res://tests/smoke/scene_boot.gd"
	RC_SCENE=$?
	RAN_SCENE=1
fi

if [[ "$MODE" == "flow" || "$MODE" == "all" ]]; then
	run_script_test "e1_flow" "res://tests/smoke/e1_flow.gd"
	RC_FLOW=$?
	RAN_FLOW=1
fi

if [[ "$MODE" == "quest" || "$MODE" == "all" ]]; then
	run_script_test "quest_waypoint" "res://tests/smoke/quest_waypoint.gd"
	RC_QUEST=$?
	RAN_QUEST=1
fi

if [[ "$MODE" == "playthrough" || "$MODE" == "all" ]]; then
	run_scene_test "e1_playthrough" "res://tests/playthrough/playthrough.tscn"
	RC_PLAY=$?
	RAN_PLAY=1
fi

if [[ "$MODE" == "resume" || "$MODE" == "all" ]]; then
	run_scene_test "resume_probe" "res://tests/resume/probe.tscn"
	RC_RESUME=$?
	RAN_RESUME=1
fi

if [[ "$MODE" == "autopilot" || "$MODE" == "all" ]]; then
	run_script_test "kino_autopilot" "res://tests/smoke/kino_autopilot.gd"
	RC_AUTOPILOT=$?
	RAN_AUTOPILOT=1
fi

if [[ "$MODE" == "questlog" || "$MODE" == "all" ]]; then
	run_script_test "quest_log" "res://tests/smoke/quest_log.gd"
	RC_QUESTLOG=$?
	RAN_QUESTLOG=1
fi

if [[ "$MODE" == "inventory" || "$MODE" == "all" ]]; then
	run_script_test "inventory" "res://tests/smoke/inventory.gd"
	RC_INV=$?
	RAN_INV=1
fi

if [[ "$MODE" == "atmosphere" || "$MODE" == "all" ]]; then
	run_script_test "atmosphere" "res://tests/smoke/atmosphere.gd"
	RC_ATMO=$?
	RAN_ATMO=1
fi

if [[ "$MODE" == "kino-doors" || "$MODE" == "all" ]]; then
	run_script_test "kino_doors" "res://tests/smoke/kino_doors.gd"
	RC_KINODOORS=$?
	RAN_KINODOORS=1
fi

if [[ "$MODE" == "kino-autoexplore" || "$MODE" == "all" ]]; then
	run_script_test "kino_autoexplore" "res://tests/smoke/kino_autoexplore.gd"
	RC_KINOEXPLORE=$?
	RAN_KINOEXPLORE=1
fi

if [[ "$MODE" == "kino-discovery" || "$MODE" == "all" ]]; then
	run_script_test "kino_discovery" "res://tests/smoke/kino_discovery.gd"
	RC_KINODISC=$?
	RAN_KINODISC=1
fi

if [[ "$MODE" == "gamepad" || "$MODE" == "all" ]]; then
	run_script_test "gamepad" "res://tests/smoke/gamepad.gd"
	RC_GAMEPAD=$?
	RAN_GAMEPAD=1
fi

if [[ "$MODE" == "shaders" || "$MODE" == "all" ]]; then
	run_script_test "ancient_metal_shader" "res://tests/smoke/ancient_metal_shader.gd"
	RC_SHADER=$?
	RAN_SHADER=1
fi

if [[ "$MODE" == "ancient-text" || "$MODE" == "all" ]]; then
	run_script_test "ancient_text" "res://tests/smoke/ancient_text.gd"
	RC_ANCIENTTEXT=$?
	RAN_ANCIENTTEXT=1
fi

if [[ "$MODE" == "npc-chat" || "$MODE" == "all" ]]; then
	# Scene-based (autoloads active) because npc.gd references the GameState
	# autoload singleton, which won't compile under a bare -s script.
	run_scene_test "npc_chat" "res://tests/smoke/npc_chat.tscn"
	RC_NPCCHAT=$?
	RAN_NPCCHAT=1
fi

if [[ "$MODE" == "save" || "$MODE" == "all" ]]; then
	run_script_test "save_store" "res://tests/save/save_store_test.gd"
	RC_SAVE_UNIT=$?
	run_scene_test "save_slot_resume" "res://tests/save/slot_resume.tscn"
	RC_SAVE_RESUME=$?
	RAN_SAVE=1
fi

# Kino map visual captures — produces 4 PNGs under screenshots/result/ that
# can be eyeballed against the concept image (design/concept-art/sgu-map.png).
# Not part of `all` because it requires a headed Godot; opt-in via `visual`.
if [[ "$MODE" == "visual" || "$MODE" == "kino-map" ]]; then
	echo
	echo "==============================="
	echo " kino_map visual captures"
	echo "==============================="
	mkdir -p screenshots/result
	RC_VISUAL=0
	for s in fog partial locked full; do
		out_user="user://kino_map_${s}.png"
		"$GODOT_BIN" --rendering-driver opengl3 --quit-after 240 \
			res://scenes/title.tscn ++ kino_map_capture "scenario=${s}" "out=${out_user}" \
			2>&1 | grep -E "(\[kino_map_capture\]|ERROR.*kino)"
		# Find the abs path Godot resolved to (user:// → app_userdata).
		abs="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe/kino_map_${s}.png"
		if [[ -f "$abs" ]]; then
			cp "$abs" "screenshots/result/kino_map_${s}.png"
			echo "  ✓ screenshots/result/kino_map_${s}.png"
		else
			echo "  ✗ kino_map_${s} capture missing"
			RC_VISUAL=1
		fi
	done
fi

echo
echo "==============================="
echo " final"
echo "==============================="
[[ $RAN_LINT  -eq 1 ]] && echo "save_registration:   $([[ $RC_LINT  -eq 0 ]] && echo PASS || echo "FAIL ($RC_LINT)")"  || echo "save_registration:   SKIPPED"
[[ $RAN_LINT  -eq 1 ]] && echo "collection_forks:    $([[ $RC_FORKS -eq 0 ]] && echo PASS || echo "FAIL ($RC_FORKS)")" || echo "collection_forks:    SKIPPED"
[[ $RAN_SCENE -eq 1 ]] && echo "scene_boot:          $([[ $RC_SCENE -eq 0 ]] && echo PASS || echo "FAIL ($RC_SCENE)")" || echo "scene_boot:          SKIPPED"
[[ $RAN_FLOW  -eq 1 ]] && echo "e1_flow:             $([[ $RC_FLOW  -eq 0 ]] && echo PASS || echo "FAIL ($RC_FLOW)")"  || echo "e1_flow:             SKIPPED"
[[ $RAN_QUEST -eq 1 ]] && echo "quest_waypoint:      $([[ $RC_QUEST -eq 0 ]] && echo PASS || echo "FAIL ($RC_QUEST)")" || echo "quest_waypoint:      SKIPPED"
[[ $RAN_PLAY  -eq 1 ]] && echo "e1_playthrough:      $([[ $RC_PLAY  -eq 0 ]] && echo PASS || echo "FAIL ($RC_PLAY)")"  || echo "e1_playthrough:      SKIPPED"
[[ $RAN_RESUME -eq 1 ]] && echo "resume_probe:        $([[ $RC_RESUME -eq 0 ]] && echo PASS || echo "FAIL ($RC_RESUME)")" || echo "resume_probe:        SKIPPED"
[[ $RAN_AUTOPILOT -eq 1 ]] && echo "kino_autopilot:      $([[ $RC_AUTOPILOT -eq 0 ]] && echo PASS || echo "FAIL ($RC_AUTOPILOT)")" || echo "kino_autopilot:      SKIPPED"
[[ $RAN_QUESTLOG -eq 1 ]] && echo "quest_log:           $([[ $RC_QUESTLOG -eq 0 ]] && echo PASS || echo "FAIL ($RC_QUESTLOG)")" || echo "quest_log:           SKIPPED"
[[ $RAN_INV -eq 1 ]] && echo "inventory:           $([[ $RC_INV -eq 0 ]] && echo PASS || echo "FAIL ($RC_INV)")" || echo "inventory:           SKIPPED"
[[ $RAN_ATMO -eq 1 ]] && echo "atmosphere:          $([[ $RC_ATMO -eq 0 ]] && echo PASS || echo "FAIL ($RC_ATMO)")" || echo "atmosphere:          SKIPPED"
[[ $RAN_KINODOORS -eq 1 ]] && echo "kino_doors:          $([[ $RC_KINODOORS -eq 0 ]] && echo PASS || echo "FAIL ($RC_KINODOORS)")" || echo "kino_doors:          SKIPPED"
[[ $RAN_KINOEXPLORE -eq 1 ]] && echo "kino_autoexplore:    $([[ $RC_KINOEXPLORE -eq 0 ]] && echo PASS || echo "FAIL ($RC_KINOEXPLORE)")" || echo "kino_autoexplore:    SKIPPED"
[[ $RAN_KINODISC -eq 1 ]] && echo "kino_discovery:      $([[ $RC_KINODISC -eq 0 ]] && echo PASS || echo "FAIL ($RC_KINODISC)")" || echo "kino_discovery:      SKIPPED"
[[ $RAN_GAMEPAD -eq 1 ]] && echo "gamepad:             $([[ $RC_GAMEPAD -eq 0 ]] && echo PASS || echo "FAIL ($RC_GAMEPAD)")" || echo "gamepad:             SKIPPED"
[[ $RAN_NPCCHAT -eq 1 ]] && echo "npc_chat:            $([[ $RC_NPCCHAT -eq 0 ]] && echo PASS || echo "FAIL ($RC_NPCCHAT)")" || echo "npc_chat:            SKIPPED"
[[ $RAN_SHADER -eq 1 ]] && echo "ancient_metal_shader: $([[ $RC_SHADER -eq 0 ]] && echo PASS || echo "FAIL ($RC_SHADER)")" || echo "ancient_metal_shader: SKIPPED"
[[ $RAN_ANCIENTTEXT -eq 1 ]] && echo "ancient_text:        $([[ $RC_ANCIENTTEXT -eq 0 ]] && echo PASS || echo "FAIL ($RC_ANCIENTTEXT)")" || echo "ancient_text:        SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_store:          $([[ $RC_SAVE_UNIT -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_UNIT)")" || echo "save_store:          SKIPPED"
[[ $RAN_SAVE -eq 1 ]] && echo "save_slot_resume:    $([[ $RC_SAVE_RESUME -eq 0 ]] && echo PASS || echo "FAIL ($RC_SAVE_RESUME)")" || echo "save_slot_resume:    SKIPPED"

if [[ ( $RAN_LINT -eq 1 && $RC_LINT -ne 0 ) || ( $RAN_LINT -eq 1 && $RC_FORKS -ne 0 ) || ( $RAN_SCENE -eq 1 && $RC_SCENE -ne 0 ) || ( $RAN_FLOW -eq 1 && $RC_FLOW -ne 0 ) || ( $RAN_QUEST -eq 1 && $RC_QUEST -ne 0 ) || ( $RAN_PLAY -eq 1 && $RC_PLAY -ne 0 ) || ( $RAN_RESUME -eq 1 && $RC_RESUME -ne 0 ) || ( $RAN_AUTOPILOT -eq 1 && $RC_AUTOPILOT -ne 0 ) || ( $RAN_QUESTLOG -eq 1 && $RC_QUESTLOG -ne 0 ) || ( $RAN_INV -eq 1 && $RC_INV -ne 0 ) || ( $RAN_ATMO -eq 1 && $RC_ATMO -ne 0 ) || ( $RAN_KINODOORS -eq 1 && $RC_KINODOORS -ne 0 ) || ( $RAN_KINOEXPLORE -eq 1 && $RC_KINOEXPLORE -ne 0 ) || ( $RAN_KINODISC -eq 1 && $RC_KINODISC -ne 0 ) || ( $RAN_GAMEPAD -eq 1 && $RC_GAMEPAD -ne 0 ) || ( $RAN_NPCCHAT -eq 1 && $RC_NPCCHAT -ne 0 ) || ( $RAN_SHADER -eq 1 && $RC_SHADER -ne 0 ) || ( $RAN_ANCIENTTEXT -eq 1 && $RC_ANCIENTTEXT -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_UNIT -ne 0 ) || ( $RAN_SAVE -eq 1 && $RC_SAVE_RESUME -ne 0 ) ]]; then
	exit 1
fi
exit 0
