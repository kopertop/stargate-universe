#!/usr/bin/env bash
# Smoke + flow test runner for Stargate Universe (Godot 4.6).
# Boots each gameplay scene headlessly and asserts the E1 win condition.
#
# Usage: tests/run.sh [scene|flow|all]   (default: all)

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
RC_SCENE=0
RC_FLOW=0

run_test() {
	local label="$1"
	local script="$2"
	echo
	echo "==============================="
	echo " $label"
	echo "==============================="
	"$GODOT_BIN" --headless --quit-after 80 -s "$script" 2>&1
	return $?
}

if [[ "$MODE" == "scene" || "$MODE" == "all" ]]; then
	run_test "scene_boot" "res://tests/smoke/scene_boot.gd"
	RC_SCENE=$?
	RAN_SCENE=1
fi

if [[ "$MODE" == "flow" || "$MODE" == "all" ]]; then
	run_test "e1_flow" "res://tests/smoke/e1_flow.gd"
	RC_FLOW=$?
	RAN_FLOW=1
fi

echo
echo "==============================="
echo " final"
echo "==============================="
[[ $RAN_SCENE -eq 1 ]] && echo "scene_boot: $([[ $RC_SCENE -eq 0 ]] && echo PASS || echo "FAIL ($RC_SCENE)")" || echo "scene_boot: SKIPPED"
[[ $RAN_FLOW  -eq 1 ]] && echo "e1_flow:    $([[ $RC_FLOW  -eq 0 ]] && echo PASS || echo "FAIL ($RC_FLOW)")"  || echo "e1_flow:    SKIPPED"

if [[ ( $RAN_SCENE -eq 1 && $RC_SCENE -ne 0 ) || ( $RAN_FLOW -eq 1 && $RC_FLOW -ne 0 ) ]]; then
	exit 1
fi
exit 0
