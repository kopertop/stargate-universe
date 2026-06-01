#!/usr/bin/env bash
# Repeatable screenshot harness for verifying gameplay/visual fixes without
# manually walking through the game. Renders with the PROJECT DEFAULT renderer
# (Forward+) so captures match what the player sees; pass `opengl3` as the 2nd
# arg to force the GL fallback.
#
# Usage:
#   tests/shots/capture.sh kino-planet            # Forward+ (default)
#   tests/shots/capture.sh kino-planet opengl3    # GL fallback
#
# Presets map to a scene + flags. Add new ones in the case block below.
# Output lands in screenshots/result/<preset>.png (and prints camera diagnostics).

set -u
cd "$(dirname "$0")/../.."

GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! [[ -x "$GODOT_BIN" ]]; then
	command -v godot >/dev/null 2>&1 && GODOT_BIN="$(command -v godot)" || { echo "ERROR: no Godot binary (set GODOT_BIN)"; exit 2; }
fi

PRESET="${1:-kino-planet}"
DRIVER="${2:-}"

case "$PRESET" in
	# flow=1 + empty spawn drives the real ship→planet gate crossing, so this
	# preset reproduces exactly what the player sees emerging from the gate
	# (a direct instantiate would skip SceneRouter and hide spawn-clobber bugs).
	kino-planet) ARGS="scene=res://scenes/planet.tscn out=user://${PRESET}.png kino_pilot=1 flow=1 spawn= wait=50" ;;
	planet)      ARGS="scene=res://scenes/planet.tscn out=user://${PRESET}.png kino_pilot=0 wait=50" ;;
	# Jungle biome (issue #88): dense flora + red-tinted hazard-trap tells.
	jungle)      ARGS="scene=res://scenes/planet.tscn out=user://${PRESET}.png biome=jungle kino_pilot=1 wait=60" ;;
	# Toxic / no-atmosphere biome (issue #89): barren toxic palette, thin sickly sky.
	toxic)       ARGS="scene=res://scenes/planet.tscn out=user://${PRESET}.png biome=toxic kino_pilot=1 wait=60" ;;
	# Urban/suburban biome (issue #90): graybox settlement + negotiation residents.
	urban)       ARGS="scene=res://scenes/planet.tscn out=user://${PRESET}.png biome=urban kino_pilot=1 wait=60" ;;
	gate-room)   ARGS="scene=res://scenes/gate_room.tscn out=user://${PRESET}.png kino_pilot=0 wait=50" ;;
	# Ship-side Kino recon (epic #45): the compass on a ship room (body), and a
	# Kino piloting a ship room with the auto-explore hint + atmosphere readout.
	ship-compass) ARGS="scene=res://scenes/room.tscn room=engineering_bay out=user://${PRESET}.png kino_pilot=0 wait=70" ;;
	ship-kino)    ARGS="scene=res://scenes/room.tscn room=engineering_bay out=user://${PRESET}.png kino_pilot=1 wait=70" ;;
	*) echo "Unknown preset: $PRESET"; exit 2 ;;
esac

DRIVER_FLAG=""
[[ -n "$DRIVER" ]] && DRIVER_FLAG="--rendering-driver $DRIVER"

mkdir -p screenshots/result
echo "=== capture $PRESET (driver=${DRIVER:-default/Forward+}) ==="
# No --headless: that disables rendering and the PNG comes back blank.
"$GODOT_BIN" $DRIVER_FLAG --quit-after 600 -s res://tests/shots/scene_shot.gd ++ $ARGS 2>&1 \
	| grep -E "CAM |UPRIGHT=|SHOT |SHOT_ERROR|SHOT_WARN"

ABS="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe/${PRESET}.png"
if [[ -f "$ABS" ]]; then
	cp "$ABS" "screenshots/result/${PRESET}.png"
	echo "  -> screenshots/result/${PRESET}.png"
else
	echo "  ✗ no image produced at $ABS"
fi
