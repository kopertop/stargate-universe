#!/usr/bin/env bash
# Smoke + flow + playthrough test runner for Stargate Universe (Godot 4.6).
# Validates the E1 vertical slice at three levels:
#   1. scene_boot   — every gameplay scene loads with critical nodes intact
#   2. e1_flow      — GameState mutators + win-condition logic
#   3. playthrough  — real cross-scene transitions via SceneRouter +
#                     Interactable.interact() pipelines, end-to-end
#
# Usage: tests/run.sh [scene|flow|playthrough|all]   (default: all)

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
RAN_PLAY=0
RC_SCENE=0
RC_FLOW=0
RC_PLAY=0

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

if [[ "$MODE" == "playthrough" || "$MODE" == "all" ]]; then
	run_scene_test "e1_playthrough" "res://tests/playthrough/playthrough.tscn"
	RC_PLAY=$?
	RAN_PLAY=1
fi

echo
echo "==============================="
echo " final"
echo "==============================="
[[ $RAN_SCENE -eq 1 ]] && echo "scene_boot:          $([[ $RC_SCENE -eq 0 ]] && echo PASS || echo "FAIL ($RC_SCENE)")" || echo "scene_boot:          SKIPPED"
[[ $RAN_FLOW  -eq 1 ]] && echo "e1_flow:             $([[ $RC_FLOW  -eq 0 ]] && echo PASS || echo "FAIL ($RC_FLOW)")"  || echo "e1_flow:             SKIPPED"
[[ $RAN_PLAY  -eq 1 ]] && echo "e1_playthrough:      $([[ $RC_PLAY  -eq 0 ]] && echo PASS || echo "FAIL ($RC_PLAY)")"  || echo "e1_playthrough:      SKIPPED"

if [[ ( $RAN_SCENE -eq 1 && $RC_SCENE -ne 0 ) || ( $RAN_FLOW -eq 1 && $RC_FLOW -ne 0 ) || ( $RAN_PLAY -eq 1 && $RC_PLAY -ne 0 ) ]]; then
	exit 1
fi
exit 0
