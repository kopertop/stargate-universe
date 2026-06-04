#!/usr/bin/env bash
# Fast gate-room cinematic render for the #30 art loop.
#   tests/shots/cine.sh <label>
# Env overrides: CAM_POS, CAM_LOOK, FOV, WAIT.
set -uo pipefail
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
LABEL="${1:-iter}"
CAM_POS="${CAM_POS:-0,2.4,-11}"
CAM_LOOK="${CAM_LOOK:-0,3.4,12.2}"
FOV="${FOV:-72}"
WAIT="${WAIT:-45}"
OUT="gate_cine_${LABEL}.png"
mkdir -p screenshots/result
timeout 115 "$GODOT_BIN" --quit-after 420 -s res://tests/shots/gate_cinematic_shot.gd ++ \
	out="user://$OUT" cam_pos="$CAM_POS" cam_look="$CAM_LOOK" fov="$FOV" wait="$WAIT" 2>&1 \
	| rg -i "SHOT |SCRIPT ERROR|shader.*error|parser error" | head
ABS="$HOME/Library/Application Support/Godot/app_userdata/Stargate Universe/$OUT"
if [[ -f "$ABS" ]]; then cp "$ABS" "screenshots/result/$OUT"; echo "-> screenshots/result/$OUT"; else echo "MISSING $OUT"; fi
