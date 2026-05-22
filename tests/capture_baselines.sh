#!/usr/bin/env bash
# Walks the player a couple metres into each E1 room, then dumps a screenshot
# to tests/baseline_screenshots/<scene>.png.
#
# NOT headless: the dummy renderer cannot read viewport textures, so the
# capture must run with the real renderer attached. The captures still close
# themselves after one frame (test_capture.gd calls get_tree().quit()).
#
# Usage:
#   tests/capture_baselines.sh                 # capture all E1 rooms
#   tests/capture_baselines.sh gate_room ...   # subset

set -u
cd "$(dirname "$0")/.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		echo "ERROR: cannot find Godot. Set GODOT_BIN or add 'godot' to PATH." >&2
		exit 2
	fi
fi

OUT_DIR="tests/baseline_screenshots"
USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe"
SRC_PNG="$USER_DATA/capture.png"

ROOMS_DEFAULT=(
	gate_room
	destiny_corridor
	corridor_crew
	corridor_mess
	crew_quarters
	eli_quarters
	mess_hall
	control_room
	observation_room
	hull_breach
)

if [[ $# -gt 0 ]]; then
	ROOMS=("$@")
else
	ROOMS=("${ROOMS_DEFAULT[@]}")
fi

mkdir -p "$OUT_DIR"
FAILED=()

# Decor-heavy rooms where the angled 3/4 camera clips inside breach geometry
# or a wall; capture them with the camera directly behind the player.
declare -a EXTRA_ARGS
get_extra_args() {
	EXTRA_ARGS=()
	case "$1" in
		# Breach wall sits right behind player spawn (z=+3 vs z=+0.5), so the
		# default behind-camera jams into rupture geometry. Flip the camera to
		# the SOUTH side (yaw=180) so it looks north at player + rupture from
		# the open corridor-door side. Walk a short way to face the breach.
		hull_breach)   EXTRA_ARGS=(yaw=180 walk=0.5) ;;
		eli_quarters)  EXTRA_ARGS=(yaw=15 walk=0.4) ;;
	esac
}

for room in "${ROOMS[@]}"; do
	scene="res://scenes/${room}.tscn"
	dest="$OUT_DIR/${room}.png"
	echo "==> ${room}"
	rm -f "$SRC_PNG"
	get_extra_args "$room"
	"$GODOT_BIN" --quit-after 240 "$scene" ++ capture "${EXTRA_ARGS[@]}" 2>&1 | tail -3
	if [[ -f "$SRC_PNG" ]]; then
		cp "$SRC_PNG" "$dest"
		echo "    saved $dest ($(stat -f%z "$dest") bytes)"
	else
		echo "    FAILED: capture.png not produced"
		FAILED+=("$room")
	fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
	echo
	echo "FAILED: ${FAILED[*]}"
	exit 1
fi
echo "all captures saved to $OUT_DIR"
